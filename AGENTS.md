# AGENTS.md — 実装規約

このリポジトリで実装を行う AI エージェントは、以下の規約に**必ず**従うこと。
各規約は `rules/` 配下にあり、以下の `@` import で常にコンテキストへ読み込まれる。

## プロジェクト構成

- 何を作るか: **モジュール間の結合を統合強度・距離・変動性から測り、バランスを理由付きで判定する
  CLI**（`docs/tightrope-plan.md`）。出力は `coupling.json` を元に terminal / markdown / html
- 言語: Rust（edition 2024）。構成: `crates/` の Cargo workspace。`crates/tightrope/src/main.rs` は引数を受けて呼ぶだけ
- 解析: tree-sitter（構文）＋ LSP（意味情報）＋ git 履歴（変動性）。対象は TypeScript / Rust / Java / Swift
- 外部依存: `clap`（derive。引数）・`toml`（`tightrope.toml` の読み込み）。足すときは「依存の更新は cooldown を通す」に従い、ここへ足す

## 規約一覧（常時ロード）

- @rules/architecture.md — 段の構成・依存方向・ロジックの帰属先・判定の置き場所・公開 API
- @rules/coding.md — エラーと不在の表現・生成時の検証・値の語彙を型で閉じる・コメント・禁止事項
- @rules/naming.md — 名前と実体の一致・このツールの語彙の固定
- @rules/testing.md — 振る舞いのテスト・assert が落ちうるか・モック禁止
- @rules/tdd.md — どこに TDD が効くか・判定ルールを変えるときの順番

## 規約の持ち場

**言語共通の Rust 規約は d-market-rust の `rust-rules-plugin` が持ち、tightrope 固有の規約は
`rules/` が持つ。** 同じ話題が両方に出たら `rules/` が勝つ（逸脱するなら `rules/` に理由を書く）。
**プラグイン側にあることを `rules/` に再掲しない**（二重管理になり、片方だけ古くなる）。

## 規範と判例を分ける

`rules/` に置くのは**規範**（こうする）だけ。**判例**（この回こうだった / NG・OK の実例 /
このリポジトリ固有のシンボル名 / PR 番号）は `harness/case-law/` に置き、**常時ロードしない**
（判例は毎回増え、規範は増えない）。

- 判断軸は「**別のリポジトリへ持っていって意味が通るか**」。通るなら `rules/`、通らないなら判例
- 読むのは**その分類で迷ったとき・指摘を受けたとき**と検証エージェント。誰が書くかは `harness/case-law/README.md`

## 常時ロードは増やさない

**`AGENTS.md` + `rules/` の合計は、`harness/records/count.sh` の `always_loaded_cap` を超えない。**
足すなら同量を削る。上限は縮めたときに下げるだけで、上げない。常時ロードの 1 行は読む側が
毎セッション払う。

- 検査: `bash harness/records/count.sh --ratchet`（pre-push と CI が走らせ、ずれていれば落ちる）
- 削り先が出せないなら、その追加は `rules/` ではなく判例かフックに置く

## 実装の進め方

実装は `implementation-flow` スキルの手順で進める（`.claude/skills/implementation-flow/`）。
ゴールの確定 → タスクの分割 → 計画（`planner`）→ **計画の検証（`plan-reviewer`）** → 実装
（`implementer`）→ **実装の検証（観点別の `*-reviewer`）** → PR → マージ後の追記、までが 1 セット。
親セッションは指示役で、計画も実装も自分では書かない。検証の観点は `.claude/agents/` が持つ
（検証のときにしか要らないものを常時ロードへ入れないため）。

**計画・却下した案・その理由は、すべて Issue に追記する**（PR 本文は差分の説明、Issue は
判断の履歴。採用した案だけ残すと、同じ案が再浮上したときに前回やめた理由が失われる）。

マージ後は `harness-record` スキルでその回の評価を `harness/records/` に記録する。記録を数えて
フックや判例へ手を入れるのは `harness-growth` スキルで、別の機会に行う。

## タスクの分割

**タスクが大きくなりそうな場合は、Issue を分離して新たに登録する。** 判断軸は
「**独立してマージできるか**」。分けたら元の Issue に理由とリンクを、分けた側に「何をスコープ外に
したか」を書く。**分けないと決めた場合も、その理由を Issue に書く。**

## 着手した Issue は、その回で閉じる

**着手したら自分をアサインし、PR 本文の `Closes #<番号>` で閉じる。** 手では閉じない（例外は PR を出さない
`flow:investigation` だけ）。閉じる Issue を持たない PR は `.github/workflows/pr-closing-issue.yml` が落とす
（例外は `harness-record` の記録 PR）。続きが要るものは**新しい Issue を立てて元からリンクする**。
閉じた Issue は開け直さない。

## 実装を始める前に

1. `docs/tightrope-plan.md` の該当節を読む
2. `rules/architecture.md`「段の構成」「依存方向のルール（必須要件）」「ロジックの帰属先」「判定は 1 箇所にだけ置く」
3. `rules/coding.md`「エラーと不在の表現」「値の語彙を型で閉じる」「不正な状態を型で表現できなくする」
4. `rules/naming.md`「名前と実体を一致させる」「その名前が既に別の意味を持っていないか確認する」

迷ったら `harness/case-law/` の同名ファイルを開く。**ここへ足してよいのは、このリポジトリの記録で
2 回以上出た指摘だけ**（他のリポジトリの項目を写すと、守る意味があるのかを読む側が判断できない）。

## 規約の更新

レビューで新しい判断基準が示されたら、その場の修正で終わらせない。**ルールに書くくらいなら
フックにする。** 機械的に判定できないものは判例に置き、`rules/` は増やさない。材料は
`harness/records/`、数えるのは `harness/records/count.sh` で、**人・bot・CI へ届いた指摘が最後の
介入より後に 2 回以上**ある分類にだけ手を入れる（手順は `harness-growth`）。

## 設計判断の確認

段をまたぐ移動や既存モジュールの再配置など、**他の規約と衝突しうる変更**は、実装前に選択肢と根拠を
示して確認する（勝手に進めず、判断だけを仰ぐ）。

## Issue に紐づいて起動したら、セッションの URL を Issue に残す

**着手した時点で**その Issue へセッションの URL（`https://claude.ai/code/session_<id>`）をコメントし、
判断待ちで止まるときも選択肢と根拠に併記する。経緯はそのセッションの中にしか無い。URL は
`SessionStart` のフック（`.claude/hooks/session-url-notice.sh`）がコンテキストに出す。
**組み立てられないと出たら、推測で書かない。**

## 強制力の序列

**Claude Code のフックは発火しない実行環境がある。** しかも**フェイルオープンかつサイレント**なので、
通ったのか検査されなかったのかを区別できない。したがって**フックを enforcement の最上位として数えない**。

| # | 層 | 効く範囲 | タイミング | 置き場所 |
| --- | --- | --- | --- | --- |
| 1 | CI | 無条件 | push の後 | `.github/workflows/` |
| 2 | git hooks | クライアント非依存 | commit / push の前 | `harness/githooks/` |
| 3 | Claude Code hooks | 配線が読まれたセッションのみ | 編集・コマンドの直前直後 | `.claude/hooks/` |
| 4 | skill / agents / rules | お願いベース | 読まれたとき | `.claude/` / `rules/` |

**ツールで落とせるものは規約の文に留めない**（`unwrap` / `expect` の禁止を `Cargo.toml` の
`[workspace.lints.clippy]` に置いてあるのがこの適用）。

### CI で使うアクション

- **バージョンは commit hash で固定する。** タグは動かせるので、層 1 で何が走るかを固定できない。
  hash の隣に `# v5.1.0` の形で版をコメントし、更新するときは両方を直す
- **既定は GitHub 公式（`actions/*`）。** ツールチェーンは `rustup` を呼べば足りるので、公式以外の
  アクションで書けることは `run:` に書き下す

## 依存の更新は cooldown を通す

**`cargo update` / `cargo add` を素で叩かない。`harness/deps/resolve.sh` を通す**
（詳細は `harness/deps/README.md`）。悪意あるバージョンは build script と proc macro が
`cargo build` の時点でローカル実行されるので、**解決の時点で止める** `.cargo/config.toml` の
`global-min-publish-age` だけが本当のブロックになる。stable では無言で無効になるため、
`resolve.sh` は nightly が無ければ落ちる。

```bash
bash harness/deps/resolve.sh add <crate> -p <メンバー>   # 根の [workspace.dependencies] に無い crate は、先に版を手で書く（harness/deps/README.md「依存を足す」）
bash harness/deps/resolve.sh update
```

## Common Commands

```bash
cargo build --locked                                    # ビルド
cargo run --locked -- <引数>                            # 実行
cargo fmt                                               # フォーマット
cargo clippy --locked --all-targets -- -D warnings      # Lint（テストコードも対象・警告をエラー扱い）
cargo test --locked                                     # テスト
PRE_PUSH_REQUIRE_ALL=1 bash harness/githooks/pre-push   # push 前の検査をすべて（CI の harness ジョブと同じ）
bash harness/records/count.sh                           # 分類ごとの再発の集計
```
