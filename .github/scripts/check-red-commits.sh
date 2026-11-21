#!/usr/bin/env bash
#
# PR の Red のコミット(`red-commits.sh` が拾うもの)で pre-push が落ち、PR の先端で通ることを確かめる。
# Red が 2 つ以上なら落とす(rules/tdd.md「Red はコミットに残し、落ちたのを確かめてから Green へ進む」)。
# git は呼んだ側のカレントのリポジトリへ打ち、呼んだ側の HEAD と作業ツリーは変えない。
#
# 使い方:
#   bash .github/scripts/check-red-commits.sh <base> <head>
#
# 引数が 2 つでないときと一時ディレクトリを作れないときのほかは、最後の行が `Red のコミットの検査: 結果 ` で
# 始まり、`通過` / `失敗` / `確かめられない` のどれかが続く。pre-push の出力は標準エラーへ流す。
# 判定表は `.github/scripts/red-commits-cases.sh`。
#
# 終了コード:
#   0 = 通過(Red で落ちて先端で通った・Red の印のコミットが無い)
#   1 = 失敗(Red が 2 つ以上ある・先端で落ちた・Red で落ちなかった)
#   2 = 確かめられない(引数が 2 つでない・Red を拾えない・pre-push の結果を読めない・結果の分け方に無い値が出た・
#       一時ディレクトリを作れない)
#   127 = 読み込む `lib/usage.sh` を読み込めない
#
# Why(リポジトリの外に作業ツリーを作る): その場で Red を checkout すると、Red の木にはこのスクリプトが
# 無いことがあり、走っているスクリプトがその木のものに置き換わる。
set -uo pipefail

# Why: 外から受け継いだ GIT_DIR などが残ると、カレントではなくそちらのリポジトリを読む。
# linked worktree から push すると、pre-push とその子に GIT_DIR が渡る。
unset $(git rev-parse --local-env-vars)

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 127
. "$scripts_dir/lib/usage.sh" || exit 127

[ $# -eq 2 ] || usage

passed_prefix='pre-push: 結果 すべて通過'
failed_pattern='^pre-push: 結果 失敗\(失敗 [1-9][0-9]* /'

work="$(mktemp -d)" || exit 2
tree="$work/tree"

# 作業ツリーが残っていれば外し、一時ディレクトリを消す。
#
# Why: 作業ツリーの場所を固定にしておく。取り出しは `$(..)` の中で走るので、そこで決めた場所は
# この trap から見えない。
remove_work() {
  [ ! -d "$tree" ] || git worktree remove --force "$tree" >&2
  rm -rf "$work"
}
trap remove_work EXIT

# 最後の行を出して終わる。
#
# $1 終了コード
# $2 `Red のコミットの検査: 結果 ` に続ける見出し
exit_with_result() {
  echo "Red のコミットの検査: 結果 $2"
  exit "$1"
}

# pre-push の終了コードと最後の行を、落ちた / 通った / 読めない に分ける。
#
# Why: 終了コードだけでは分けない。`finish_checks`(harness/githooks/lib/check-tally.sh)の戻り値は、落ちた検査が
# 無くても 1 になることがある。pre-push が無ければ 127 になる。
#
# $1 pre-push の終了コード
# $2 pre-push の最後の行
# 出力: `failed` / `passed` / `unreadable`
outcome_of() {
  local status="$1" last="$2" is_failed_run=no is_passed_run=no
  [ "$status" = 1 ] && [[ "$last" =~ $failed_pattern ]] && is_failed_run=yes
  [ "$status" = 0 ] && [[ "$last" == "$passed_prefix"* ]] && is_passed_run=yes
  if [ "$is_failed_run" = yes ]; then
    echo failed
    return 0
  fi
  if [ "$is_passed_run" = yes ]; then
    echo passed
    return 0
  fi
  echo unreadable
}

# コミットの木を一時ディレクトリに取り出し、`PRE_PUSH_REQUIRE_ALL=1` で pre-push を走らせて結果を分ける。
#
# $1 走らせるコミット
# 出力: `outcome_of` の出力。取り出せなければ `unreadable`
prepush_outcome_at() {
  local status last
  if ! git worktree add -q --detach "$tree" "$1" >&2; then
    echo unreadable
    return 0
  fi
  (cd "$tree" && PRE_PUSH_REQUIRE_ALL=1 bash harness/githooks/pre-push) 2>&1 | tee "$work/prepush.log" >&2
  status="${PIPESTATUS[0]}"
  last="$(tail -n 1 "$work/prepush.log")"
  git worktree remove --force "$tree" >&2
  outcome_of "$status" "$last"
}

reds="$(bash "$scripts_dir/red-commits.sh" "$1" "$2")" ||
  exit_with_result 2 "確かめられない(Red の印のコミットを拾えない)"
[ -n "$reds" ] || exit_with_result 0 "通過(Red の印のコミットが無い)"

red_count="$(grep -c '' <<<"$reds")"
[ "$red_count" -eq 1 ] || exit_with_result 1 "失敗(Red が 2 つ以上ある: ${red_count} 件)"
echo "Red のコミット: ${reds}"

# Why: 先端を Red より先に走らせる。先端が落ちれば Red の結果によらず失敗なので、Red の分を省ける。
# Why(どちらの case にも `*)` を置く): bash の case は枝の網羅を確かめない。`outcome_of` の値を増やして枝を
# 直し忘れても、通過や Red の確かめへ素通りさせず、確かめられない側へ倒す。
head_outcome="$(prepush_outcome_at "$2")"
case "$head_outcome" in
  passed) ;;
  failed) exit_with_result 1 "失敗(PR の先端で検査が通らない)" ;;
  unreadable) exit_with_result 2 "確かめられない(PR の先端の pre-push の結果を読めない)" ;;
  *) exit_with_result 2 "確かめられない(PR の先端の結果が分け方に無い値: ${head_outcome})" ;;
esac

red_outcome="$(prepush_outcome_at "$reds")"
case "$red_outcome" in
  failed) exit_with_result 0 "通過(Red で落ち、PR の先端で通った)" ;;
  passed) exit_with_result 1 "失敗(Red のコミットで検査が落ちない: ${reds})" ;;
  unreadable) exit_with_result 2 "確かめられない(Red のコミットの pre-push の結果を読めない)" ;;
  *) exit_with_result 2 "確かめられない(Red のコミットの結果が分け方に無い値: ${red_outcome})" ;;
esac
