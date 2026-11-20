# harness/githooks — 実行環境に依存しない push 前検査

git ネイティブのフック置き場。`core.hooksPath` をここへ向けると、CLI・IDE・素の git の
どれから push しても同じ検査が走る。強制力の序列での位置は `AGENTS.md`「強制力の序列」の層 2。

## 何が走るか

| フック | 検査 |
| --- | --- |
| `pre-commit` | `cargo fmt --check`（整形だけのコミットを積まないため） |
| `pre-push` | `cargo fmt --check` / `cargo clippy --all-targets -- -D warnings` / `cargo doc --no-deps`（`rustdoc::private_intra_doc_links` を deny） / `cargo test`、常時ロードのラチェット（`harness/records/count.sh --ratchet`）、ハーネス自身の判定表（`*-cases.sh` / `*-test.sh`） |

検査の一覧の原本は [`pre-push`](pre-push) 自身。ここ・スキル・CI へ写さない
（CI の `harness` ジョブは `PRE_PUSH_REQUIRE_ALL=1 bash harness/githooks/pre-push` をそのまま走らせる）。

道具（`cargo` / `jq`）が無い区間は飛ばし、飛ばしたことを最後の行に出す（下の「結果の読み方」）。
無条件のゲートは CI（層 1）にある。

## 配線 — cargo に `prepare` が無い

npm / pnpm のリポジトリなら `package.json` の `prepare` が `install` のたびに配線できるが、
**cargo にこれに当たるフックは無い**。

**手で 1 度実行する形は採らない。** リモート実行環境は毎回クローンからやり直すうえ
DevContainer の `postCreateCommand` も走らない。そこは Claude Code のフックが読まれない環境と
同じなので、**層 2 と層 3 が同時に抜ける**。

代わりに、**配線する入口を重ねる**。どちらも [`set-hooks-path.sh`](set-hooks-path.sh) を呼ぶ。

| 入口 | 効く環境 |
| --- | --- |
| Claude Code の `SessionStart` フック（`.claude/hooks/wire-githooks.sh`） | Claude Code のセッションを開いたとき |
| DevContainer の `postCreateCommand`（`.devcontainer/devcontainer.json`） | DevContainer でコンテナを作ったとき |

`postCreateCommand` では `&&` ではなく `;` で繋ぐ。前段のセットアップが失敗しても配線だけは通したいため。

```bash
# 手元で配線する・配線されているかを確かめる
bash harness/githooks/set-hooks-path.sh
git config --get core.hooksPath   # → harness/githooks
```

## 配線の穴と、それを誰が塞ぐか

**単独で穴の無い入口は無い。** 残る穴を書き出しておく。

| 状況 | 層 2 | 層 3 | 塞ぐもの |
| --- | --- | --- | --- |
| DevContainer で開いた | 効く | 効く | — |
| Claude Code のセッション（フックが読まれる） | 効く | 効く | — |
| Claude Code のセッション（フックが読まれない） | **抜ける** | **抜ける** | **CI（層 1）** |
| 素の `git clone` + 別のクライアントから push | **抜ける** | **抜ける** | **CI（層 1）** |

**穴が残ることを承知で層 2 を置く。** 層 2 は「push の前に気づける」ための層で、
**ゲートそのものではない**。ゲートは層 1 にあり、そこは無条件に効く。

**Why not（CI で配線の有無を検査する）**: `core.hooksPath` はクローンごとのローカル設定で、
リポジトリには痕跡が残らない。CI が見られるのは push されたものだけなので、検査できない。

## 結果の読み方

**最後の行が結果を言う。** 落ちた検査があっても止めずに最後まで走らせ、最後に内訳と結果を出す
（集計は [`lib/check-tally.sh`](lib/check-tally.sh)）。

```
pre-push: 失敗した検査: cargo clippy
pre-push: 飛ばした検査: post-edit-rust のテスト
pre-push: 結果 失敗(失敗 1 / 通過 18 / 飛ばした 1)
```

| 最後の行 | 終了コード | 意味 |
| --- | --- | --- |
| `pre-push: 結果 すべて通過(…)` | 0 | すべて走って、すべて通った |
| `pre-push: 結果 飛ばした検査があるまま通過(…)` | 0 | 走ったものは通ったが、道具が無くて走らせていないものがある |
| `pre-push: 結果 失敗(…)` | 1 | 落ちた検査がある |

- **止めずに最後まで走らせるのは、結果を最後の 1 行で言うため。** 最初の失敗で止まる形だと、
  通ったことを「落ちた証拠が見当たらない」から推測するしかなく、途中の出力を読み落とすと読み違える
- **`PRE_PUSH_REQUIRE_ALL=1` のときは、飛ばした検査も失敗に数える。** push 前手順
  （`implementation-flow` フェーズ 7）と CI はこのモードで走らせ、「すべて確かめた」を終了コードだけで判定する。
  引数にしないのは、git が `pre-push` へリモート名と URL を位置引数で渡すため

## 動作確認

```bash
PRE_PUSH_REQUIRE_ALL=1 bash harness/githooks/pre-push   # push 前の検査をすべて
bash harness/githooks/lib/check-tally-cases.sh          # 集計そのものの判定表
bash harness/githooks/lib/test-placement-cases.sh       # テストの置き場所の検査の判定表
```
