# tightrope 計画書

『ソフトウェア設計における結合のバランス』（Vlad Khononov）のモデルを使い、プロジェクトのモジュールごとに「統合強度・距離・変動性」を算出して、バランスを理由付きで判定する CLI。CLI と HTML レポートで見せる。

- 最終更新：2026-11-17
- HTML レポートのラフ：https://claude.ai/artifact/TJuCKTyq1m7htFWNAo1Gr2
- 参考にする既存リポジトリ：DIO0550/dryguard（同じ解析基盤を持つ自作 CLI）

この文書は 2 部構成。**前半（「MVP 仕様」まで）が実装の拠り所**で、後半（「MVP の後」以降）は構想として残している。

## 決定事項

| 日付 | 決めたこと |
|---|---|
| 2026-11-17 | 実装言語は **Rust** |
| 2026-11-17 | 解析対象は dryguard と同じ：TypeScript（.ts / .tsx / .mts / .cts）・Rust・Java・Swift。作りも揃える（**tree-sitter で構文、LSP で意味情報**） |
| 2026-11-17 | リポジトリ名・コマンド名は **`tightrope`**、設定ファイルは **`tightrope.toml`**（構想メモの `coupling` / `.coupling.toml` から変更。dryguard の `dryguard.toml` と揃える） |
| 2026-11-17 | **最初に縦に通す言語は TypeScript**（下の「なぜ TypeScript から始めるか」） |
| 2026-11-17 | **dryguard のコードはコピーで移植する。** 共通 crate へ切り出すかは 2 言語目を足すときに決める（下の「dryguard との関係」） |
| 2026-11-17 | **git 履歴は `git` コマンドを呼んで取る**（gix / git2 は使わない） |
| 2026-11-17 | **MVP では数値スコアを出さない。** 3 軸を段階で持ち、決定木で判定する |
| 2026-11-17 | **変動性が取れないときは判定を「保留」にして理由を出す**（tolerated で埋めない） |

### なぜ TypeScript から始めるか

- dryguard で最も作り込まれている言語で、import の抽出と解決をそのまま移植できる
- 公開用の `index.ts` を飛ばした深い import が、構文だけで Intrusive として拾える
- 自作の TypeScript リポジトリ（design-composer）を実データとして試せる

**Why not（Rust から始める）**: tightrope 自身で試せる利点はあるが、rust-analyzer の起動と索引作りが重く、`pub` 境界の判定にモジュール宣言の解決が要る。

### dryguard との関係

- 移植するのは `lsp/`（JSON-RPC のフレーミングと往復・サーバの起動・hover / definition / references）、`syntax/tree.rs`（`Grammar`）、`syntax/import.rs` の TypeScript 部分、`codebase` の git 呼び出し
- `lsp/` が dryguard の他のモジュールから使っているのは `SourcePosition` と `Grammar` だけなので、この 2 つと一緒に持ってくれば閉じる
- **移植元のコミットを記録する**（移植する PR の本文と、移植したモジュールの module doc）。dryguard 側の修正を追いかけるときの起点にする
- 移植時点の dryguard の HEAD は `082c274`（2026-11-17）

**Why not（今すぐ共通 crate に切り出す）**: dryguard はまだ活発に変わっており（206 コミット）、切り出すと両方の変更が共通 crate の版上げ待ちになる。2 言語目を足す時点で、移植したコードがどれだけ手を入れられたかを見て決める。

## 判定の基本

```
MODULARITY = STRENGTH XOR DISTANCE
COMPLEXITY = STRENGTH AND DISTANCE
BALANCE    = (STRENGTH XOR DISTANCE) OR NOT VOLATILITY
```

| | 距離が近い | 距離が遠い |
|---|---|---|
| 強度が弱い | 低凝集（複雑） | 疎結合（バランス良） |
| 強度が強い | 高凝集（バランス良） | 密結合（要注意） |

変動性が低ければ（ほとんど変更されなければ）、バランスが悪くても「許容」にする。

## MVP 仕様

### MVP の範囲

| 入れる | 入れない（MVP の後） |
|---|---|
| TypeScript だけ（.ts / .tsx / .mts / .cts） | Rust / Java / Swift |
| `tightrope report <dir>` | HTML レポート・依存マップ |
| 出力：`coupling.json`・terminal の表・markdown | co-change（一緒に変わるファイル） |
| `--fail-on` で CI を落とす | チーム（CODEOWNERS）による距離 |
| `tightrope.toml` でしきい値を変える | 数値スコア・不安定度 I |
| | tsconfig の `paths` エイリアスの解決 |
| | dryguard との共通 crate |

### 用語

| 語 | MVP で指すもの |
|---|---|
| `module` | **ファイル 1 つ**。走査の根（`<dir>`）の下にある TypeScript のファイル |
| `dependency` | ある module から別の module への依存 1 本。`from` が import を書いた側、`to` が import が解決した先 |
| `evidence` | 依存の根拠になった参照箇所 1 つ。`ファイル:行` と、その箇所の強度 |
| `refs` | 依存 1 本が持つ evidence の数 |
| `package` | そのファイルから上へ辿って最初に見つかる `package.json` のディレクトリ |

### 依存の取り方

1. 走査の根の下の TypeScript ファイルを集める（`node_modules` / `dist` / `build` など依存・生成物の置き場は降りない。一覧は dryguard の `codebase` と同じものを移植する。`.gitignore` は読まない）
2. 各ファイルの import 宣言（`import` / `export ... from` / `require` / `import x = require()`）を tree-sitter で拾う
3. 相対指定（`./` / `../`）を、**集めたファイルの集合に照らして**解決する。拡張子の省略（`.ts` / `.tsx` / `.mts` / `.cts` / `.d.ts`）とディレクトリの `index.*` を試す
4. 解決できたものだけを依存にする。パッケージ名の import（`react` など）は走査の外なので数えない。**相対指定なのに解決できなかったものは件数と位置を出す**（黙って捨てない）

- `to` は **import が解決したファイル**で、宣言が実際に書かれたファイルではない。`index.ts` 経由の import は `index.ts` への依存になる（公開口に依存しているので、それが正しい結合の相手）
- 解決は集めたファイルの集合に対する照合なので、解析の段は I/O を持たない（ファイルを集めて読むところだけが I/O の境界）

**Why not（dryguard の `ModulePath` をそのまま使う）**: dryguard は「同じ依存先を共有しているか」を見るだけなので、指定子を綴りのまま畳めば足りた。tightrope は依存の相手をファイルとして特定する必要がある。

### 統合強度

参照箇所（evidence）ごとに強度を決め、**依存 1 本の強度は evidence のうち最も強いもの**にする。

| 強度 | 何で決めるか | LSP が要るか |
|---|---|---|
| Intrusive | 公開口を飛ばした深い import。`to` の祖先ディレクトリのうち `index.*` を持ち、`from` を含まないものが 1 つでもあれば（`to` がその `index.*` 自身なら当たらない）。その import から来た evidence はすべて Intrusive | 要らない |
| Functional | import した名前を値として使っている（呼び出し・`new`・値としての参照） | 要らない |
| Model | 型の位置で使っていて、宣言が `class` / `enum` | **要る**（definition） |
| Contract | `import type`、または型の位置で使っていて、宣言が `interface` / `type` | `import type` なら要らない |

- 強度の順は Intrusive > Functional > Model > Contract
- 型の位置の参照は、宣言の場所を LSP の definition で確かめ、そこを tree-sitter で読んで Model / Contract を決める
- **LSP が答えなかった型の位置の参照は、Model か Contract かを「取れなかった」にする。** 0 や Contract で埋めない
- ただし既定のしきい値では Model も Contract も「弱い」側なので、**強い / 弱いの判定には効かない**。判定に効かない欠けで判定を消さない（`rules/architecture.md`「取れなかった値を既定値で埋めない」）。しきい値を `model` に下げた設定のときだけ、その依存の強弱が「取れなかった」になる
- 構想メモにあった「`as any` で内部に触る箇所」と、パスの規約（`contracts/` / `dto/`）による Model / Contract の補正は MVP に入れない

### 距離

`from` と `to` の位置関係で 3 段にする。

| 距離 | 条件 |
|---|---|
| `same-directory` | 同じディレクトリ |
| `other-directory` | ディレクトリが違い、`package` が同じ |
| `other-package` | `package` が違う（monorepo / workspace） |

- module がファイルなので「同一ファイル」の段は無い
- 「別チーム」の段は CODEOWNERS を読むときに足す（まだ動かない選択肢を enum に並べない）

### 変動性

- **依存先（`to`）のファイルの変更回数**で測る。依存される側が変わると、依存する側に変更が波及するため
- `git log --since=<期間> --name-only --format=<区切り>` を走査の根で 1 回だけ呼び、ファイルごとの回数を数える（ファイルごとに `git` を呼ばない）
- 既定の期間は **180 日**
- リネームは追わない（MVP）。リネーム前の履歴は数えない
- git のリポジトリでない・`git` が無い・履歴が 0 件は、**すべて「取れなかった」として理由ごとに出す**

### しきい値と既定値

| しきい値 | 既定値 | 意味 |
|---|---|---|
| 強いとみなす強度の下限 | `functional` | これ以上（Intrusive / Functional）を「強い」 |
| 遠いとみなす距離の下限 | `other-directory` | これ以上を「遠い」 |
| 変動性を測る期間 | 180 日 | |
| 変動性が高いとみなす変更回数 | 5 回 | 期間内にこの回数以上変わったら「高い」 |

既定値はこの 4 つを判定と同じ場所 1 箇所にだけ書く。`tightrope.toml` を読む側は既定値を持たない（`rules/architecture.md`「判定は 1 箇所にだけ置く」）。

### 判定

| 強度 | 距離 | 変動性が高い | 変動性が低い | 変動性が取れない |
|---|---|---|---|---|
| 強い | 遠い | **risk** | tolerated | 保留 |
| 弱い | 近い | **warn** | tolerated | 保留 |
| 強い | 近い | ok | ok | ok |
| 弱い | 遠い | ok | ok | ok |

- バランスが良い（強度 XOR 距離）ものは変動性に関わらず ok。**変動性が取れなくても判定できる**
- 強度が「取れなかった」依存（上の「統合強度」の最後の場合）も、判定に効くときだけ保留にする
- 判定（`verdict`）の語彙は `risk` / `warn` / `tolerated` / `ok` の 4 つのまま。**保留は判定の 5 つ目ではなく「判定できなかった」**として別に持ち、理由を付ける
- 判定には **reason**（どの軸が・どの値で・どちらへ傾けたか）を付ける。人が読む文は出力の側が reason から組み立てる

**Why（保留を tolerated で埋めない）**: git 履歴の無い環境で密結合がすべて tolerated になり、本当に変わらないのか測れなかったのかを読者が区別できない。

### CLI

```
tightrope report <dir> [--format terminal|json|markdown] [-o <file>] [--fail-on risk|warn] [--no-lsp]
```

- `--format` の既定は `terminal`。`json` が `coupling.json` の中身を出す
- `-o` が無ければ標準出力
- `--fail-on risk` は risk が 1 件でもあれば終了コード 1。`--fail-on warn` は warn 以上で 1。**保留では落とさない**（落とさなかった件数は出す）
- `--no-lsp` は LSP を起動しない。型の位置の Model / Contract は「取れなかった」になるが、既定のしきい値なら判定は変わらない
- LSP サーバ（typescript-language-server）が見つからないときも同じ扱いで続け、その旨を出す
- `--lang` は MVP では置かない（選べるのが TypeScript だけなので）

### `tightrope.toml`

走査の根に置く。無くても動く。

```toml
[thresholds]
strong_from = "functional"        # intrusive / functional / model / contract
far_from = "other-directory"      # same-directory / other-directory / other-package
volatility_window_days = 180
volatile_from_commits = 5
```

書かれていないキーは既定値になる。知らないキー・知らない値は**エラーにして止める**（黙って既定値にしない）。

### `coupling.json`

出力はすべてこれを入力にする。terminal / markdown / html は判定をやり直さない。

```json
{
  "schema_version": 1,
  "root": "src",
  "thresholds": {
    "strong_from": "functional",
    "far_from": "other-directory",
    "volatility_window_days": 180,
    "volatile_from_commits": 5
  },
  "modules": [
    {
      "path": "src/order/order.ts",
      "language": "typescript",
      "loc": 120,
      "package": ".",
      "volatility": { "status": "measured", "commits": 7 }
    }
  ],
  "dependencies": [
    {
      "from": "src/billing/invoice.ts",
      "to": "src/order/order.ts",
      "strength": { "status": "measured", "value": "functional" },
      "distance": "other-directory",
      "refs": 3,
      "judgement": { "status": "judged", "verdict": "risk" },
      "reasons": [
        { "axis": "strength", "value": "functional", "threshold": "functional", "lean": "strong" },
        { "axis": "distance", "value": "other-directory", "threshold": "other-directory", "lean": "far" },
        { "axis": "volatility", "value": 7, "threshold": 5, "lean": "volatile" }
      ],
      "evidence": [
        { "path": "src/billing/invoice.ts", "line": 12, "strength": "functional", "code": "calculateTotal(order)" }
      ]
    }
  ],
  "unresolved_imports": [
    { "path": "src/app.ts", "line": 3, "specifier": "./missing" }
  ],
  "summary": {
    "modules": 42,
    "dependencies": 118,
    "verdicts": { "risk": 2, "warn": 5, "tolerated": 9, "ok": 100 },
    "undetermined": 2
  }
}
```

- 取れなかった値は `{ "status": "unavailable", "reason": "..." }` の形で出す（`volatility` / `strength` / `judgement` に共通）。保留の判定は `"judgement": { "status": "undetermined", "reason": "volatility-unavailable" }`
- 依存の変動性は `to` の module が持つので、依存の側には重ねて書かない（reason にだけ当てた値が出る）
- パスは走査の根の親からの相対で、区切りは `/`
- 配列の並びは決定的にする（`modules` はパス順、`dependencies` は `from`→`to` 順）。同じ入力から同じ JSON が出ないと、CI の成果物を比べられない
- 改善のヒント（構想メモの `hint`）は判定と reason から出力の側が組み立てるので、JSON には持たない

### 段の構成（MVP）

```
cli → pipeline ─┬→ codebase（ファイルを集めて読む・git log を呼ぶ）   ← I/O の境界
                ├→ lsp（typescript-language-server との会話）       ← I/O の境界
                ├→ syntax（import の抽出と解決・参照箇所と強度の候補）
                ├→ volatility（git log の出力を変更回数に直す）
                ├→ judgement（3 軸 → 判定・reason）
                └→ report（coupling.json / terminal / markdown）
```

- モジュール名は目安で、置くときに `rules/architecture.md` の表へ足す
- `syntax` と `judgement` は I/O を持たない。git と LSP は「出力・応答を受け取ってから先」を純粋な関数に切り出して TDD する（`rules/tdd.md`）

## MVP の後

### 既存ツールとの差

- 既存：cargo-coupling（Rust のみ）、dotnet-coupling（C#）、coupling-meter（PHP）、archfit（Go / TS / Python。TS の解析は dependency-cruiser ベースで import 単位）
- このツールの差：
  - **1つのバイナリで TS / Rust / Java / Swift を同じモデルで測れる**
  - **LSP の型情報で統合強度を分類する**（import 単位ではなく、何を共有しているかまで見る）
  - レポート（JSON / HTML、依存マップ）で見せ方に差をつける

### 技術スタック（dryguard と共通）

- CLI：clap
- 構文：tree-sitter（tree-sitter-typescript / -rust / -java / -swift）。grammar は拡張子で選ぶ（TS と TSX は別）
- 意味情報：LSP（lsp-types で型だけ借り、JSON-RPC の往復は自前）
  - TS：typescript-language-server / Rust：rust-analyzer / Java：jdtls / Swift：sourcekit-lsp
  - 使う問い合わせ：hover（型）、definition（宣言の場所）、references（参照数）、callHierarchy（呼び出し関係）
- 並列化：rayon
- 出力：serde_json。HTML テンプレートは include_str! でバイナリに埋め込む

### 3 つの軸の拡張

- **統合強度**：Intrusive に `as any` などで内部に触る箇所を足す。Model と Contract の区別をパスの規約（`contracts/`、`dto/` など）や設定で補う。言語ごとの公開境界（Rust の `pub`、Java の `public` / パッケージ、Swift の `internal` / `public`）
- **距離**：別チーム（CODEOWNERS）の段を足す。module の単位をディレクトリ・パッケージへ広げる
- **変動性**：co-change（一緒に変更されやすいファイル）
- **数値スコア**：HTML のホットスポットの並べ替えに要るようになったら、3 軸の段階から導く式を決める

### 全体構成

```
解析（tree-sitter + LSP + git 履歴）
   ↓
coupling.json（すべてのデータの元）
   ↓
 ├─ terminal（表で表示 / CI で失敗させる判定）
 ├─ markdown（PR コメント用）
 └─ html（1ファイルで完結するレポート）
```

- HTML は JSON を `<script type="application/json">` に埋め込み、JS / CSS もインラインにする。サーバーなしで開け、CI の成果物や GitHub Pages に置きやすい
- 例：`tightrope report src --format html -o report.html`
- 言語は 1 つずつ足す

### HTML レポートの構成（ラフで作成済み）

1. **サマリー**：モジュール数、依存の数（参照箇所）、要注意 / 注意の件数
2. **強度×距離マトリクス**：本の 2×2 の上に依存を点で配置。円の大きさ＝変動性
3. **選択中の依存**：判定、理由、根拠のコード（`ファイル:行` と参照箇所）、改善のヒント
4. **誰がどれだけ依存しているか**
   - 依存行列（行＝依存する側、列＝される側、数字＝参照数、要注意を含むマスに印）
   - パッケージごとの「依存されている量 / している量」の棒グラフと不安定度 I（Martin の指標。判定には使わず参考値）
   - 選んだパッケージに依存している相手の内訳
5. **依存マップ**（下記）
6. **ホットスポット一覧**：判定の悪い順、「要注意・注意のみ」で絞り込み

### 依存マップの設計

- 参考：Map of GitHub（anvaka）、GMap / gvmap（Graphviz）、Software Cartography、CodeSurveyor、CodeCharta
- 配置：力学配置（d3-force 相当）で、結合が強いファイルほど近くに置く。乱数シード固定で毎回同じ配置
- 領域：1ファイル＝1領域。重み付き Voronoi を円で切り取って有機的なかたまりにする
- パッケージ境界は太線、チームは点線の枠、別チームは離れた位置に置く
- 色の濃さ＝変更回数（単色系。虹色グラデーションや発光は使わない）
- 大きさは切り替え式：**行数 / 依存されている参照数**
  - 被依存モードでは「大きくて濃い＝多くから頼られ、よく変わる」危ないファイルが目立つ
  - 被依存 0 のファイルにも最小サイズを残す
- 線の絡まり対策：初期表示はパッケージ単位に集約した依存（太さ＝参照数合計、色＝最も悪い判定）。ファイルを選んだときだけファイル単位の依存を出す
- 本番では HTML 側で d3-force / d3-delaunay を使う想定（ラフでは自前実装）

## 次にやること

- [x] 実装言語を決める → Rust
- [x] 解析の対象言語を決める → dryguard と同じ（TS / Rust / Java / Swift）
- [x] 最初に縦に通す1言語を決める → TypeScript
- [x] リポジトリ名を決める → tightrope
- [x] dryguard と共通化する範囲を決める → MVP はコピーで移植、2 言語目で再判断
- [x] coupling.json のスキーマを決める → 上の「`coupling.json`」
- [x] 判定の決め方としきい値を決める → 上の「しきい値と既定値」「判定」
- [ ] MVP をタスクに分けて Issue に切る
