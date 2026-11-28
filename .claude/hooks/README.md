# .claude/hooks — Claude Code のフック（層 3）

`.claude/settings.json` から配線する。**どれも enforcement として数えない** —
フック自体が読まれない実行環境があり、しかもフェイルオープンかつサイレントなので、
通ったのか検査されなかったのかを区別できない。ゲートは層 2（`harness/githooks/`）と
層 1（`.github/workflows/`）にある。

移植元は dryguard（Rust の検査・カナリア・セッション URL・マージ後の促し）と
design-composer（サブエージェントの制御・発火ログ）。どちらかの記録から生まれた介入のうち、
tightrope の記録にまだ根拠が無いものは持ってきていない（`AGENTS.md`「実装を始める前に」）。

## 何が走るか

| フック | イベント | すること |
| --- | --- | --- |
| `wire-githooks.sh` | `SessionStart` | `core.hooksPath` を `harness/githooks` へ向ける（`harness/githooks/README.md`「配線 — cargo に `prepare` が無い」） |
| `session-url-notice.sh` | `SessionStart` | このセッションの URL（`https://claude.ai/code/session_<id>`）を組み立ててコンテキストに出す。ブランチが `claude/issue-<N>-...` なら Issue 番号も添える |
| `record-firings.sh` | `SessionStart` / `PostToolUse`（`Skill` / `Task` / `Agent`） | セッション見出しと、スキル・サブエージェントの発火を `${TMPDIR:-/tmp}/tightrope-firings-<session_id>.log` へ 1 行ずつ書く |
| `pre-push-check.sh` | `PreToolUse`（`Bash`） | コマンドに `git push` があれば `harness/githooks/pre-push` を走らせ、落ちたら exit 2 で止める |
| `hook-canary.sh` | `PreToolUse`（`Bash`） | コマンドが `echo hook-canary` そのものなら exit 2 で止める。このセッションでフックが発火しているかを確かめるためだけのもの |
| `block-git-during-verification-agent.sh` | `PreToolUse`（`Bash`） | 作業ツリーを書き換えるサブエージェント（`implementer` / `test-reviewer`）の実行中は、`git add` / `commit` / `push` を拒否する |
| `track-verification-agent-activity.sh` | `PreToolUse` / `PostToolUse`（`Task` / `Agent`） | 上の 2 つのサブエージェントの実行中の印を置く・消す。背景での起動は拒否する |
| `block-parent-session-edit.sh` | `PreToolUse`（`Edit` / `Write`） | 発火ログに `implementation-flow` の区切りがあれば、親セッションによるリポジトリの中の編集を拒否する（編集は `implementer` が担う） |
| `post-edit-rust.sh` | `PostToolUse`（`Edit` / `Write` / `MultiEdit`） | `.rs` を編集したら、そのクレートに `cargo fmt` をかけ、`cargo clippy` が落ちたら診断を exit 2 で返す |
| `post-merge-review.sh` | `PostToolUse`（`mcp__github__merge_pull_request` / `Bash`） | PR のマージ（MCP のマージか `gh pr merge`）を検知したら、Issue への追記と `harness-record` の記録を `additionalContext` で促す。止めない |

## 配線

[`.claude/settings.json`](../settings.json) の `hooks` から参照する。パスは `${CLAUDE_PROJECT_DIR:-.}` 基準。

`lib/` はフック本体から読む共有部品と、フックの判定を固定する判定表(`*-cases.sh`)の置き場。
`settings.json` からは参照しない。判定表はどれも `harness/githooks/pre-push` が走らせ、CI の
`harness` ジョブがそれを `PRE_PUSH_REQUIRE_ALL=1` で走らせる（層 1）。

| ファイル | 使う側 | 内容 |
| --- | --- | --- |
| `lib/command-segments.sh` | `lib/git-push-command.sh` / `lib/gh-pr-merge-command.sh` | 引用符の中身を落とし、`&&` / `||` / `;` / `|` / `&` / 括弧 / 改行でコマンドを区切る |
| `lib/git-push-command.sh` | `pre-push-check.sh` | 区切った 1 つずつの先頭が `git push` かを見る。読み損ねた形は「push ではない」側へ倒す |
| `lib/gh-pr-merge-command.sh` | `post-merge-review.sh` | 区切った 1 つずつの先頭が `gh pr merge` か（`--auto` / `--disable-auto` は除く）を見る |
| `lib/hook-input.sh` | `record-firings.sh` / `track-verification-agent-activity.sh` / `block-git-during-verification-agent.sh` / `block-parent-session-edit.sh` | 標準入力の JSON から文字列の値を取り出す `extract`。jq を使わず bash の組み込みだけで読む |
| `lib/firings-log.sh` | `record-firings.sh` / `block-parent-session-edit.sh` | 発火ログのパスを組み立てる `firings_log_path <session_id>` |
| `lib/cases-report.sh` | `lib/verification-agent-cases.sh` / `lib/parent-session-edit-cases.sh` / `lib/cases-report-cases.sh` / `harness/records/count-cases.sh` / `harness/githooks/lib/*-cases.sh` / `harness/githooks/lib/cases-allowlist.sh` / `harness/deps/tool-cooldown-cases.sh` / `.github/scripts/*-cases.sh` | 判定表が共有する、判定の読み取り（`decide` / `decide_by_permission` / `hook_verdict_by_permission` / `normalize_miss`）と報告（`report` / `cases_failed`）と、判定表の最後の文の照合（`last_statement` / `report_exits_with_cases_failed`） |
| `lib/cases-report-cases.sh` | `harness/githooks/pre-push` | `cases-report.sh` 自身の判定表。`cases-report.sh` を source する判定表の最後の文が `exit "$cases_failed"` かも見る |
| `lib/cases-fixtures.sh` | `lib/verification-agent-cases.sh` / `lib/parent-session-edit-cases.sh` / `harness/githooks/lib/test-placement-cases.sh` / `harness/githooks/lib/test-file-length-cases.sh` / `.github/scripts/red-commits-cases.sh` / `.github/scripts/lock-publish-age-cases.sh` / `harness/deps/tool-cooldown-cases.sh` / `harness/githooks/lib/rust-checks-cases.sh` / `harness/githooks/lib/clippy-config-cases.sh` / `harness/githooks/lib/check-roots-cases.sh` / `harness/githooks/lib/crate-deps-cases.sh` / `harness/githooks/lib/folder-deps-cases.sh` / `harness/githooks/lib/lints-inheritance-cases.sh` / `harness/githooks/lib/lint-level-attributes-cases.sh` / `harness/githooks/lib/cargo-config-rustflags-cases.sh` / `post-edit-rust-test.sh` | 判定表が共有する、ケースの前提の置き方（サブエージェントの中の呼び出しの入力、使い捨ての git リポジトリへの入り方、偽の sparse index への版の置き方、cargo を走らせる使い捨てのクレートの置き方など） |
| `lib/verification-agent-cases.sh` | `harness/githooks/pre-push` | `track-verification-agent-activity.sh` と `block-git-during-verification-agent.sh` へ呼び出しを順に流し、起動の拒否と git 操作の拒否が期待どおりかを報告する |
| `lib/parent-session-edit-cases.sh` | `harness/githooks/pre-push` | 本物の `record-firings.sh` に発火ログを書かせてから `block-parent-session-edit.sh` へ Edit / Write を流し、親の編集の拒否と素通りが期待どおりかを報告する |

## 強制力の序列

序列そのものは `AGENTS.md`「強制力の序列」が持つ。**push 前検査の enforcement は git hooks と CI が担う。**
ここにある `pre-push-check.sh` / `post-edit-rust.sh` は、同じ検査を編集中に走らせる**最速フィードバック層**。
`harness-growth` が「`hook` に置く」と判断したときは、`harness/githooks/` か CI のどちらかに置き、
Claude Code 側はその共有版として足す。

### カバー範囲と残る穴

git hooks へ移せるのは **push 前に痕跡が残る検査だけ**。CI の代替が「**無し**」の行は、
発火しない環境では効かず、git のイベントに対応物が無いので移設もできない。

| 効かなくなるもの | CI の代替 |
| --- | --- |
| `pre-push-check.sh` / `post-edit-rust.sh`(即時フィードバック) | 結果は push 前の検査(git hooks)と CI が拾う。**即時性だけが失われる** |
| `block-git-during-verification-agent.sh`(セッション中の行為の禁止) | **無し**。競合はセッションの実行タイミングだけが原因で、コミット後のリポジトリには痕跡が残らない |
| `block-parent-session-edit.sh`(セッション中の行為の禁止) | **無し**。誰が編集したか(親かサブエージェントか)はコミットに残らない |
| `record-firings.sh`(発火ログ) | **無し**。セッション見出しが無いログは `harness-record` が「計測対象外」と書くので、誤ったゼロにはならない。ただし同じログを読む `block-parent-session-edit.sh` は、区切りが無ければ素通りする |
| `session-url-notice.sh`(セッション URL の提示) | **無し**。落ちても情報が 1 つ足りないだけでガードは破れない |

`block-parent-session-edit.sh` が発火する環境でも残る穴。

| 残る穴 | 内容 |
| --- | --- |
| 区切りがログに残らない起動 | Skill ツールを通らない起動(打ったスラッシュコマンド・手順を読んで進める回)は、スキルの起動がログに残らない。区切りが無いので親の編集を止めない |
| matcher の外の道具 | `NotebookEdit` / `MultiEdit` は matcher(`Edit\|Write`)に入っていない |
| Bash 経由の書き換え | `sed -i` やリダイレクトでの書き換えは見ない。コマンド文字列から書き換え先のパスを確定できない |
| 正規化しないパス | `..` を挟んだ絶対パスや symlink 越しのパスは、綴りがルートと前方一致しないとリポジトリの外として通る |

**不発がカナリアで確定したら、「記録のみ」で終わらせず手で肩代わりする。**

| 不発したフック | 手動で確認すること |
| --- | --- |
| `block-git-during-verification-agent.sh` | サブエージェントの実行中に作られたコミットの diff を、そのエージェントが返したはずの内容とだけ照合する |
| `block-parent-session-edit.sh` | このセッションの親の Edit / Write の履歴を見直し、implementation-flow の中でリポジトリの中のファイルを編集していないか確認する |

## `pre-push-check.sh` — 層 2 との違いは発火条件だけ

**検査の本体を二重管理にしない。** 呼ぶのは `harness/githooks/pre-push` そのもので、
検査の並びを持つのはそこだけ。こちらが足すのは、**Bash のコマンドが実行される前に**、
落ちた検査の出力を Claude に返すことだけ。

**`core.hooksPath` が配線されていても走る。** 同じ push で検査が 2 回走るが、
配線済みなら飛ばす形にすると `git push --no-verify` が素通りする。

**黙って通す条件**: `jq` が無い・入力の JSON が読めない・`CLAUDE_PROJECT_DIR` が
git の作業ツリーでない。**タイムアウトは 600 秒**（`cargo test` がビルドから始まると長い）。

## `post-edit-rust.sh` — 最速のフィードバック

**ゲートではない。** exit 2 は診断を Claude に返すだけで、**編集は取り消されない**。

- **検査するのは、編集したファイルから上へ最も近い `Cargo.toml` のクレート。** テスト用の
  フィクスチャなど別のクレートを根で走らせると、そのファイルを fmt も clippy も見ない
- **`rustfmt <file>` ではなく `cargo fmt`**。版（edition）を `Cargo.toml` と二重に持たない
- **fmt が落ちたら clippy は走らせない。** fmt が落ちるのは構文が壊れているときで、
  clippy は同じエラーを重ねて出すだけ
- clippy は層 1 / 層 2 と同じ `harness/githooks/lib/rust-checks.sh clippy` で走らせる（引数と lock の扱いはそちらが持つ）

**黙って通す条件**: `jq` か `cargo` が無い・`file_path` が `.rs` でない / 存在しない・
上へ辿っても `Cargo.toml` が無い。**タイムアウトは 300 秒**。

## `hook-canary.sh` — 発火しているかを確かめる

push の前に `echo hook-canary` を 1 度実行する。**止められれば**このセッションでフックが
発火しており、**通ってしまえば**発火していない（PR 本文と `harness/records/` の記録に残す）。

**止めるのは害の無いコマンド 1 つだけで、ゲートではない。**

- **判定も出力も bash の組み込みだけで行う。** `PreToolUse` は exit 2 以外の異常終了を
  素通りさせるので、`jq` が無くて exit 127 で落ちると、配線が読まれていないのと同じ見え方になる
- **止めたとき、他のフックが使う `jq` / `cargo` が無ければその名前も出す。** 発火していても、
  それらが欠けていれば他のフックは黙って素通りする
- **止め方は exit 2 と stderr。** stdout に `permissionDecision` の JSON を出す形は、
  組み立てを誤ると非ブロック扱いで黙って通る

**`echo hook-canary` が通っても、それだけでは不発と決まらない。** `.claude/settings.json` は
セッションの起動時に読まれるので、**起動した時点の** `PreToolUse` に `hook-canary.sh` が
配線されていたかを確かめる。配線より前のブランチから起動したセッションでは通って当たり前で、
そのときは「canary が無いので判定できなかった」と書く。`PreToolUse` には `pre-push-check.sh` も
配線されていて、こちらは canary を止めないので、`PreToolUse` があることだけを見て判断しない。

## `session-url-notice.sh` — URL はセッションの中からしか作れない

`AGENTS.md`「Issue に紐づいて起動したら、セッションの URL を Issue に残す」の材料。

- **ID は `CLAUDE_CODE_REMOTE_SESSION_ID`（`cse_<id>`）の接頭辞を `session_` に替えたもの。**
  stdin の `session_id` と `CLAUDE_CODE_SESSION_ID` はローカルの UUID で URL の ID とは別物
- **組み立てられないときは黙らず、組み立てられないと出す。** 黙ると不発と区別できず、
  URL を推測で書く余地が残る
- **Issue 番号はブランチ名だけから読む。** `claude/issue-<N>` の後ろが `-` か終わりのときだけ
- **終了コードは常に 0。** セッションの開始を止める理由は無い

## `post-merge-review.sh` — マージ後の振り返りへの入口

- **止めない。** `additionalContext` を返すだけで、終了コードは常に 0
- **検知するのは `mcp__github__merge_pull_request` と `gh pr merge` だけ。** 素の `git merge` は
  ベースブランチの取り込みで日常的に走るので見ない。`--auto` / `--disable-auto` 付きも見ない
- **読み損ねた形は「マージではない」側へ倒す。** マージでないコマンドをマージと読むと、
  まだ続いている PR の記録を書き始めさせてしまう
- **マージの成否は見ない。** 文言を「マージが成功していれば」に留める

## 終了コードまで見る

層 1（CI の `run:`）と層 2（`pre-push` の `run_check`）は**終了コードだけが配線**なので、
判定表・検査を手で確かめるときは標準出力の文字列だけで済ませず、`; echo "exit=$?"` を付ける。

**PreToolUse の deny だけは例外で、判定は出力に出る。** `permissionDecision` の JSON を返して
`exit 0` で終わるので、終了コードでは deny と pass が区別できない（判定表は `decide_by_permission` で読む）。

## 動作確認

```bash
# フック本体のテスト(dryguard から移したもの)
bash .claude/hooks/pre-push-check-test.sh
bash .claude/hooks/post-edit-rust-test.sh
bash .claude/hooks/hook-canary-test.sh
bash .claude/hooks/session-url-notice-test.sh
bash .claude/hooks/post-merge-review-test.sh

# 判定表(design-composer から移したもの。`ok` だけなら期待どおり)
bash .claude/hooks/lib/verification-agent-cases.sh
bash .claude/hooks/lib/parent-session-edit-cases.sh
bash .claude/hooks/lib/cases-report-cases.sh

# 発火ログが書き出されること(見出し + skill の 2 行)
d="$(mktemp -d)"
printf '{"session_id":"probe","hook_event_name":"SessionStart"}' | TMPDIR="$d" bash .claude/hooks/record-firings.sh
printf '{"session_id":"probe","hook_event_name":"PostToolUse","tool_name":"Skill","tool_input":{"skill":"implementation-flow"}}' | TMPDIR="$d" bash .claude/hooks/record-firings.sh
cat "$d"/tightrope-firings-probe.log
```

どれも `harness/githooks/pre-push` に入っており、CI の `harness` ジョブでも走る。
