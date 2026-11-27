# tightrope report - 技術仕様（バックエンド）

> **機能**: [tightrope report（MVP）](./index.md)

## 概要

段の構成、I/O を持つ場所、dryguard から移植するもの、依存クレート、横断的なエラー処理を決める。

## 段の構成

crate を層に、crate の中を役割フォルダに分ける。拠り所にした原則・使うデザインパターン・却下した案は #252。
見出しの「段」は crate と役割フォルダの構成を指し、ワークフロー（`domain/workflow/`）の段階は stage と呼ぶ。
フォルダとファイルは置き場所の約束で、中身ができた回に作る。`application` crate はまだ無い（下の図と表は目標の構成）。

```
presentation ──→ application ──→ domain
                     ↑
infrastructure ──────┘
tightrope（bin）→ すべて（組み立てるだけ）
```

| crate | フォルダ | 責務 |
|:------|:---------|:-----|
| `domain` | `value_object/` | 制約付きの単純型と enum（choice 型）。生成時に検証し、同値で比べる |
| | `entity/` | 同一性を持つもの（`Module` は path、`Dependency` は from → to）と不変条件 |
| | `policy/` | 判定の規則。しきい値と既定値・値をしきい値に当てた `lean`・判定表 |
| | `aggregate/` | 集約ルート `Coupling`。並びの決定性と summary の一致を守る |
| | `workflow/` | report のワークフロー。stage ごとの型と、stage から stage への純粋な関数 |
| `application` | `dto/` | 境界の形。`inbound/` は port から入る検証前の値、`outbound/` は外へ出す値（`coupling.json` の契約・LSP への問い合わせ）、`request.rs` は presentation から入る値 |
| | `port/` | 外への口（trait）。引数と戻り値は `dto` だけ |
| | `mapping/` | `inbound` = DTO → domain（持ち場は `rules/architecture.md`「段の構成」）、`outbound` = domain → DTO |
| | `usecase/` | I/O の殻。port を呼ぶ → `mapping::inbound` → `domain::workflow` → `mapping::outbound` |
| | `error/` | 始められない失敗（終了コード 2）の種類 |
| `infrastructure` | `driver/` | 外部とのやり取り（ファイル・子プロセス・stdio）。文字列・バイト・パスで返し、application の型を知らない |
| | `translation/` | 腐敗防止。外部の形式（TOML・`git log` の出力・LSP の応答・構文木）→ `application::dto::inbound`。純粋 |
| | `adapter/` | port の実装。`driver` で取り、`translation` で直して返す |
| `presentation` | `controller/` | 引数の受け口（clap）と `ReportRequest` への変換 |
| | `view_model/` | 表示用モデル（行・reason の文・改善のヒント） |
| | `presenter/` | `ReportDocument` / `StartError` → 表示用モデル |
| | `view/` | 表示用モデル → 文字列（terminal / markdown）、`ReportDocument` → `coupling.json`。書き出しはしない |
| `tightrope`（bin） | `main.rs` | `lib.rs` との分け方は `rules/architecture.md`「lib と bin を分ける」 |
| | `lib.rs` | controller → usecase → presenter → view → 書き出し |
| | `composition.rs` | adapter を組み立てて port に差す（`--no-lsp` なら `adapter/declaration/disabled`） |
| | `sink.rs` | 標準出力 / `-o` のファイルへの書き出し |
| | `exit_code.rs` | 0 / 1 / 2 |

- 使ってよい相手は表に写さない。`rules/architecture.md`「依存方向のルール（必須要件）」の表が指す検査が持つ
- 層をまたいで揃える名前は `rules/architecture.md`「段の構成」の port の名前。置いたファイル名と責務の表は、置いた回にこの節へ足す
- git と LSP は「出力・応答を受け取ってから先」を `translation/` の純粋な関数に切り出して TDD する（`rules/tdd.md`）

## dryguard からの移植

| 移植するもの | dryguard の場所 | 手を入れるところ |
|:-------------|:----------------|:----------------|
| LSP クライアント | `src/lsp.rs` / `src/lsp/` | TypeScript で使う分（handshake・document・definition・references）だけ残す |
| 位置の型 | `src/source_position.rs` | そのまま |
| 文法の選択 | `src/syntax/tree.rs`（`Grammar`） | TypeScript の拡張子だけにする |
| import の抽出 | `src/syntax/import.rs` の TypeScript 部分 | 綴りのまま畳む解決を、集めたファイルの集合に照らす解決へ置き換える |
| ファイルの収集 | `src/codebase.rs` | 降りないディレクトリの一覧を含めて移植 |
| git の呼び出し | `src/codebase/diff.rs` の `git_output_of` | `git log` を呼ぶ形にする |

- 移植元は dryguard の `082c274`（2026-11-17 時点の `main`）。移植する PR の本文と、移植したモジュールの module doc に移植元のコミットを書く
- 共通 crate への切り出しは、2 言語目を足すときに、移植後にどれだけ手を入れたかを見て決める

**Why not（今すぐ共通 crate に切り出す）**: dryguard はまだ活発に変わっており、切り出すと両方の変更が共通 crate の版上げ待ちになる。

## 依存クレート

`harness/deps/resolve.sh` を通して足す（`AGENTS.md`「依存の更新は cooldown を通す」）。

| クレート | 用途 |
|:---------|:-----|
| `clap`（derive） | 引数 |
| `tree-sitter` / `tree-sitter-typescript` | 構文 |
| `lsp-types` | LSP の要求・応答の型（JSON-RPC の往復は自前） |
| `serde` / `serde_json` | `coupling.json` の出力 |
| `toml` | `tightrope.toml` |
| `rayon` | ファイルごとの構文解析の並列化（要るようになったら） |

- git は `git` コマンドを呼ぶ。gix / git2 は使わない（依存が重く、cooldown を通す対象が増える）

## エラーハンドリング

| エラーケース | 発生条件 | 振る舞い | 終了コード |
|:------------|:---------|:---------|:-----------|
| 始められない | 引数・設定・走査の根・出力先 | 止める | 2 |
| 一部が取れない | LSP・git・個別のファイル | 「取れなかった」として構造に出して続ける | 0 / 1 |

- 取れなかった値を既定値で埋めない（`rules/architecture.md`「取れなかった値を既定値で埋めない」）
- エラー型は原因ごとにバリアントを分け、`Display` で人が読む文にする

## テスト

| 対象 | テストの仕方 |
|:---|:-------------|
| `domain/policy`・`domain/workflow` の判定 | 3 軸の組み合わせごとに期待する判定を先に書く（判定表の全行と保留） |
| `domain/workflow` の解決と強度 | 構文の事実と集めたファイルから期待する依存・evidence・強度 |
| `infrastructure/translation/syntax` | 入力のソースと期待する構文の事実（import・参照箇所・宣言の種類） |
| `infrastructure/translation/git_log` | `git log` の出力の文字列から期待する回数 |
| `infrastructure/translation/lsp_definition` | 応答の JSON から期待する型 |
| `infrastructure/driver` | `crates/infrastructure/tests/` のフィクスチャに対して実物の I/O で見る |
| `application/usecase` | port のフェイクを差して、手順と「取れなかった」の扱いを見る |
| `presentation/controller` | 引数の並びと期待する解釈 |
| 段をつないだ結果 | `crates/tightrope/tests/` にフィクスチャのディレクトリを置いて `coupling.json` を見る |

- LSP サーバを要するテストは、無い環境で飛ばしたことが分かる形にする（`rules/testing.md`）。最初のサーバを要するテストを足す回に、CI に typescript-language-server を入れて走らせるステップを足す

## 制限事項

- Windows のパス区切りは `coupling.json` では `/` に直す。Windows での動作確認は MVP では行わない

## 関連仕様

- [index.md](./index.md) - 全体の処理フロー
- [dependency-spec.md](./dependency-spec.md) / [strength-spec.md](./strength-spec.md) / [distance-volatility-spec.md](./distance-volatility-spec.md) / [judgement-spec.md](./judgement-spec.md) - 各段の振る舞い
