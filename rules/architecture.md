# アーキテクチャ規約

**このファイルは tightrope 固有の構造規約。** 言語共通の Rust 規約は d-market-rust の
`rust-rules-plugin` が持つ（`AGENTS.md`「規約の持ち場」）。実例（過去に踏んだ形）は
[`harness/case-law/architecture.md`](../harness/case-law/architecture.md)。

## 段の構成

crate を層に、crate の中を役割のフォルダに分ける。責務と向きは `docs/report/technical-spec.md`「段の構成」、向きを落とす検査は次の節の表。

- **bin を除く crate の `lib.rs` は、役割フォルダの `pub mod` だけを置く**
- **domain の型は何を持つかでフォルダを選ぶ。** 判定の規則（しきい値・傾き・判定表）なら `policy/`、集約ルートなら
  `aggregate/`、同一性を持つなら `entity/`、ワークフローの stage の型なら `workflow/`、それ以外の値は `value_object/`
- **ワークフロー（`domain/workflow/`）は stage ごとに型を変えた純粋な関数で並べ、I/O は stage の間で `usecase` が port を通して行う**
- **DTO を domain の型にする変換（とその変換での検証）は `mapping/inbound` だけに置き、`Result` で返す。**
  外部の形式を読む（`translation/`・`controller/`）・値の制約を守る（`value_object/` の生成）とは別の持ち場
- **feature は役割フォルダの中のファイル名に出し、層をまたいで同じ名前にする**
- **「使わない」（`--no-lsp` など）は同じ port の Null Object で表し、既定値で埋めず「取れなかった」を返す**

## 依存方向のルール（必須要件）

- **構文解析は意味情報（LSP）を知らない。** `translation/syntax/`・`adapter/syntax` は `translation/lsp_definition`・
  `adapter/declaration/`・`driver/lsp/` を使わない（下の表の検査はこの区別を見ない）。知ると「LSP 無しでも動く」が壊れる
- **adapter はオーケストレーションを持たない。** 複数の port を呼ぶ手順は `usecase` の責務
- **出力は判定をやり直さない。** `coupling.json` が持つ値を見せ方に変えるだけ。漏れると JSON と HTML で答えが食い違う
- 循環依存は全面禁止（同じフォルダの中のファイル同士は、下の表の検査が見ない）

**下の表の検査が落とす向き・I/O・serde・`mod.rs` は、文で再掲しない**（許可表の根拠は `docs/report/technical-spec.md`「段の構成」）。

| 縛るもの | 検査 |
|---|---|
| crate 間の向き・使ってよい外部 crate | 各 crate の `[dependencies]` と `harness/githooks/lib/crate-deps.sh` の `allowed_dependencies` |
| I/O を持ってよい crate | `harness/githooks/lib/clippy-config-cases.sh` の `io_crates` と、それ以外の crate の `clippy.toml` |
| フォルダ間の向き・I/O と serde を持ってよいフォルダ・`lib.rs` からの参照 | `harness/githooks/lib/folder-deps.sh` の `allowed_dependencies` |
| `mod.rs`（`tests/` の下は落とさない） | 根の `Cargo.toml` の `mod_module_files` |

## ロジックの帰属先

**判断の起点は「その規則は誰の性質か」。** 値を組み立てる・判定する・変換するコードは、その値を
表す型の `impl` に置く。迷ったら、そのコードが第 1 引数（`self`）に取るべき型を見る。

- 2 つの値が**常に対で意味を持つ**なら、対を表す型を作ってそちらに帰属させる
- 引数を 4 つも 5 つも取る中間ヘルパーや `(String, String)` のようなタプルは、
  「名前の付いていない型がここにある」というサイン

## 判定は 1 箇所にだけ置く

**3 軸 → 判定（`risk` / `warn` / `tolerated` / `ok`）の決定木と、しきい値の既定値は `domain/policy/` にだけ書く。**
解析や出力の側に判定が漏れると、レポートが出す理由と実際の判定が食い違い、
**このツールの価値（理由付きで見せること）が壊れる。** 設定（`tightrope.toml`）を読む側は
**書かれていたかどうかと値だけ**を持ち、既定値を持たない。

## 取れなかった値を既定値で埋めない

LSP が起動しない・問い合わせに答えない・git 履歴が無いは、**すべて「取れなかった」として構造に出す。**
0 や「中立」で埋めると、実際にその値だったのか取れなかったのかを後段も読者も区別できない
（`rules/coding.md`「不正な状態を型で表現できなくする」の適用）。

| NG | OK |
|---|---|
| `volatility: u32` に履歴が無いとき 0 を入れる | `Option` / 理由を持つ enum で不在を表し、レポートに理由を出す |

**そのシグナルの答えに効く材料が欠けたときだけ「取れなかった」にする。** 効かない材料の欠けまで
「取れなかった」にすると、判定に効かない欠けで答えが消える。

## 問い合わせの単位を答えの単位に揃える

LSP・git・ファイルシステムへの問い合わせは、**答えが何に対して一意か**（参照箇所 / ファイル /
プロジェクト）を確かめてから、その単位で 1 回だけ呼び、同じキーを持つものへ配る。
1 ファイルから N 個の参照を拾って、ファイル単位で決まる答えを N 回尋ねない。

**Why**: LSP への問い合わせは同期的な往復を伴うプロセス外呼び出しで、件数に比例して往復が増える。

## モジュールの公開 API

- `pub` は最小限にする。**モジュール外から触る必要があるものだけ** `pub` にする
- モジュールの内部構造へ外から直接触らない（`pub(crate)` で段階を作る）

## lib と bin を分ける

bin の crate（`crates/tightrope`）は `lib.rs` と `main.rs` に分け、`main.rs` は引数を受けて `lib.rs` を呼ぶだけにする。

**Why**: bin だけの構成だと、テストからしか使われていない公開 API が `dead_code` になり、`#[allow(dead_code)]` で
黙らせると `rules/coding.md`「禁止事項」の lint 抑制に当たる。統合テスト（`tests/`）が書けるようになる利点もある。
