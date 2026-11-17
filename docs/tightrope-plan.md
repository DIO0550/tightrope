# 結合バランス分析ツール（構想メモ）

『ソフトウェア設計における結合のバランス』（Vlad Khononov）のモデルを使い、プロジェクトのモジュールごとに「統合強度・距離・変動性」を算出して、CLI と HTML レポートで見せるツール。

- 最終更新：2026-11-17
- HTML レポートのラフ：https://claude.ai/artifact/TJuCKTyq1m7htFWNAo1Gr2
- 参考にする既存リポジトリ：DIO0550/dryguard（同じ解析基盤を持つ自作 CLI）

## 決定事項

- **実装言語は Rust**（2026-11-17 決定）
- **解析対象は dryguard と同じ**（2026-11-17 決定）：TypeScript（.ts / .tsx / .mts / .cts）・Rust・Java・Swift
- 解析の作りも dryguard に揃える：**tree-sitter で構文、LSP で意味情報**

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

変動性が低ければ（ほとんど変更されなければ）、密結合でも「許容」にする。

判定は4段階：risk（要注意）／ warn（注意）／ tolerated（許容）／ ok（バランス）。

## 既存ツールとの差

- 既存：cargo-coupling（Rust のみ）、dotnet-coupling（C#）、coupling-meter（PHP）、archfit（Go / TS / Python。TS の解析は dependency-cruiser ベースで import 単位）
- このツールの差：
  - **1つのバイナリで TS / Rust / Java / Swift を同じモデルで測れる**
  - **LSP の型情報で統合強度を分類する**（import 単位ではなく、何を共有しているかまで見る）
  - レポート（JSON / HTML、依存マップ）で見せ方に差をつける

## 技術スタック（dryguard と共通）

- CLI：clap
- 構文：tree-sitter（tree-sitter-typescript / -rust / -java / -swift）。grammar は拡張子で選ぶ（TS と TSX は別）
- 意味情報：LSP（lsp-types で型だけ借り、JSON-RPC の往復は自前）
  - TS：typescript-language-server / Rust：rust-analyzer / Java：jdtls / Swift：sourcekit-lsp
  - 使う問い合わせ：hover（型）、definition（宣言の場所）、references（参照数 refs）、callHierarchy（呼び出し関係）
- 並列化：rayon
- 出力：serde_json。HTML テンプレートは include_str! でバイナリに埋め込む
- git 履歴：git コマンドを呼ぶか gix / git2（未決定）
- 設定：`.coupling.toml`（パッケージ・チームの定義、強度の判定ルールの上書き、しきい値）
- 共通化の案：dryguard と LSP クライアントや言語ごとの走査部分を共通 crate に切り出せるか、実装しながら検討

## 3つの軸の測り方（案）

- **統合強度**（tree-sitter で参照箇所を拾い、LSP で中身を確かめる）
  - Intrusive（侵入）：公開されていない内部への参照（公開用の index / pub 境界を飛ばした深い参照、`as any` などで内部に触る箇所）
  - Functional（機能）：実装を持つ関数・メソッド・クラスの呼び出し（callHierarchy で確認）
  - Model（モデル）：ドメインのエンティティ型をそのまま共有（hover / definition で型の宣言元を確認）
  - Contract（契約）：DTO や interface / trait / protocol だけへの依存
  - Model と Contract の区別は型情報だけで決めきれない場合があるので、パスの規約（`contracts/`、`dto/` など）や設定で補う
- **距離**：同一ファイル → 同一ディレクトリ → 同一パッケージ → 別パッケージ（monorepo / workspace） → 別チーム（CODEOWNERS）
- **変動性**：git 履歴の変更頻度（例：直近6か月）。一緒に変更されやすいファイル（co-change）も出せると良い
- **参照数（refs）**：依存ごとの参照箇所の数（LSP の references で数える）。依存行列や被依存数の集計に使う

## 全体構成

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
- 例：`coupling report --format html -o report.html`
- 開発順：先に JSON と terminal 出力で解析ロジックを固め、HTML は後から足す
- 言語は1つずつ足す（最初の1言語を決めて縦に通してから、残りを追加）

## HTML レポートの構成（ラフで作成済み）

1. **サマリー**：モジュール数、依存の数（参照箇所）、要注意 / 注意の件数、平均バランススコア
2. **強度×距離マトリクス**：本の 2×2 の上に依存を点で配置。円の大きさ＝変動性
3. **選択中の依存**：判定、理由、根拠のコード（`ファイル:行` と参照箇所）、改善のヒント
4. **誰がどれだけ依存しているか**
   - 依存行列（行＝依存する側、列＝される側、数字＝参照数、要注意を含むマスに印）
   - パッケージごとの「依存されている量 / している量」の棒グラフと不安定度 I（Martin の指標。判定には使わず参考値）
   - 選んだパッケージに依存している相手の内訳
5. **依存マップ**（下記）
6. **ホットスポット一覧**：スコアの低い順、「要注意・注意のみ」で絞り込み

## 依存マップの設計

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
- [ ] 最初に縦に通す1言語を決める
- [ ] リポジトリ名を決める
- [ ] dryguard と共通化する範囲を決める（LSP クライアント、言語ごとの走査など）
- [ ] coupling.json のスキーマを決める
  - ファイル：path、language、loc、commits、package、team
  - 依存：from、to、strength、distance、volatility、refs、verdict、score、reason、evidence（`ファイル:行` とコード）、hint
- [ ] スコアの計算式と、判定のしきい値を決める
- [ ] MVP：CLI でモジュールのペアごとに強度・距離・変動性と判定を JSON / Markdown で出す
