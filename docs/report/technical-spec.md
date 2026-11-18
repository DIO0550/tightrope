# tightrope report - 技術仕様（バックエンド）

> **機能**: [tightrope report（MVP）](./index.md)

## 概要

段の構成、I/O を持つ場所、dryguard から移植するもの、依存クレート、横断的なエラー処理を決める。

## 段の構成

```
cli → pipeline ─┬→ codebase（ファイルを集めて読む・git log を呼ぶ）   ← I/O の境界
                ├→ lsp（typescript-language-server との会話）       ← I/O の境界
                ├→ syntax（import の抽出と解決・参照箇所と構文で決まる強度）
                ├→ volatility（git log の出力を変更回数に直す）
                ├→ judgement（3 軸 → 判定・reason）
                └→ report（coupling.json / terminal / markdown）
```

| モジュール | 責務 | 持たないもの |
|:-----------|:-----|:-------------|
| `cli` | 引数の受け口と値の解釈 | 判定・I/O の手順 |
| `config` | `tightrope.toml` を読み、書かれていた値にする | 既定値・判定 |
| `pipeline` | 段を呼ぶ順序・LSP への問い合わせの組み立て | 判定・構文の判別 |
| `codebase` | ファイルを集めて読む・`git log` を呼ぶ | 判定・出力の解釈 |
| `syntax` | import の抽出・解決・参照箇所・構文で決まる強度・宣言の種類 | I/O・LSP・判定 |
| `lsp` | 子プロセスの起動と JSON-RPC・応答をこちらの型へ直す | 複数の段にまたがる手順 |
| `volatility` | `git log` の出力を読んで変更回数にする | I/O |
| `judgement` | しきい値の既定値・決定木・reason | I/O・LSP・git |
| `report` | `coupling.json` / terminal / markdown | 判定のやり直し |

- モジュール名は目安。置いた回に `rules/architecture.md` の表と `rules/naming.md` の語彙へ足す
- 依存の向きは `rules/architecture.md`「依存方向のルール（必須要件）」に従う。`syntax` は LSP と判定を知らず、`judgement` は解析の結果を値として受け取る
- git と LSP は「出力・応答を受け取ってから先」を純粋な関数に切り出して TDD する（`rules/tdd.md`）

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

| 層 | テストの仕方 |
|:---|:-------------|
| `judgement` | 3 軸の組み合わせごとに期待する判定を先に書く（判定表の全行と保留） |
| `syntax` | 入力のソースと期待する依存・evidence・強度 |
| `volatility` | `git log` の出力の文字列から期待する回数 |
| `lsp` の応答の変換 | 応答の JSON から期待する型 |
| `cli` | 引数の並びと期待する解釈 |
| 段をつないだ結果 | `tests/` にフィクスチャのディレクトリを置いて `coupling.json` を見る |

- LSP サーバを要するテストは、無い環境で飛ばしたことが分かる形にする（`rules/testing.md`）。最初のサーバを要するテストを足す回に、CI に typescript-language-server を入れて走らせるステップを足す

## 制限事項

- Windows のパス区切りは `coupling.json` では `/` に直す。Windows での動作確認は MVP では行わない

## 関連仕様

- [index.md](./index.md) - 全体の処理フロー
- [dependency-spec.md](./dependency-spec.md) / [strength-spec.md](./strength-spec.md) / [distance-volatility-spec.md](./distance-volatility-spec.md) / [judgement-spec.md](./judgement-spec.md) - 各段の振る舞い
