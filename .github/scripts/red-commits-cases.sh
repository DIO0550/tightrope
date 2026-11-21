#!/usr/bin/env bash
#
# `red-commits.sh`(PR の範囲から Red の印のコミットを拾う)と `check-red-commits.sh`(Red のコミットで
# pre-push が落ち、PR の先端で通るかを確かめる)の判定表。使い捨てのリポジトリにコミットを積んで走らせ、
# 拾ったコミットの件名・終了コード・最後の行の見出し・偽の pre-push が残したログを照らす。
#
# 使い方: bash .github/scripts/red-commits-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。
#
# 偽の pre-push は `FAKE_PREPUSH_LOG` へ `<目印> <受け取った PRE_PUSH_REQUIRE_ALL>` を 1 行足し、本物の
# `harness/githooks/lib/check-tally.sh` の `run_check` と `finish_checks` で結果行を出す。
# Why: 結果行を写さずに本物で作る。写しだと、`finish_checks` の行の形を変えた差分でもこの表が通り、
# 読む側(`check-red-commits.sh`)が古い形のままでも気づけない。
set -uo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$scripts_dir/../.." && pwd)"
red_commits_script="$scripts_dir/red-commits.sh"
check_script="$scripts_dir/check-red-commits.sh"
tally_script="$repo_root/harness/githooks/lib/check-tally.sh"

source "$repo_root/.claude/hooks/lib/cases-report.sh"
source "$repo_root/.claude/hooks/lib/cases-fixtures.sh"

# 外から受け継いだものを消す。PRE_PUSH_REQUIRE_ALL は CI が渡し、残すと C6 は何を壊しても通る。
isolate_git_env
unset PRE_PUSH_REQUIRE_ALL

work="$(mktemp -d)" || exit 1
trap 'cd / && rm -rf "$work"' EXIT
export FAKE_PREPUSH_LOG="$work/prepush.log"
pick_stderr="$work/pick.err"

co_author='Co-Authored-By: cases <cases@example.invalid>'
heading_prefix='Red のコミットの検査: 結果 '

# 使い捨てのリポジトリを `main` で作って cd し、`main` に base のコミットを置いてから `pr` を分ける。
# HEAD は `pr` に置いたまま終わる。
#
# $1 リポジトリの名前(ケースごとに違える)
start_repo_on_pr() {
  mkdir -p "$work/$1" || exit 1
  git -C "$work/$1" init -q -b main || exit 1
  enter_repo "$work/$1"
  commit_with_prepush base pass base
  git checkout -q -b pr || exit 1
}

# 件名・本文・最後の段落(渡したトレーラと Co-Authored-By)を持つコミットメッセージを出す。
#
# $1 件名
# $2... 最後の段落の、Co-Authored-By より前に置く行
message_of() {
  printf '%s\n\n本文。\n\n' "$1"
  shift
  printf '%s\n' "$@" "$co_author"
}

# 渡したメッセージでコミットする。ステージした変更があればそれも含み、無ければ空のコミットになる。
#
# $1 コミットメッセージ
commit_with_message() {
  git commit -q --allow-empty -F - <<<"$1" || exit 1
}

# 偽の pre-push の中身を出す。
#
# $1 目印(ログに残す)
# $2 結果(pass = すべて通過 / fail = 検査が落ちた / skip = 飛ばした検査があるだけで、落ちた検査は無い)
#    silent = 結果行を出さずに exit 0
fake_prepush_of() {
  local marker="$1" checks
  case "$2" in
    pass) checks='run_check 偽の検査 true' ;;
    fail) checks='run_check 偽の検査 false' ;;
    skip) checks=$'run_check 偽の検査 true\nskip_following_checks 偽の道具が無い\nrun_check 飛ばす偽の検査 true' ;;
    silent) checks='exit 0' ;;
  esac
  cat <<EOF
#!/usr/bin/env bash
echo "$marker \${PRE_PUSH_REQUIRE_ALL-}" >>"\$FAKE_PREPUSH_LOG"
source $(printf '%q' "$tally_script")
$checks
finish_checks
EOF
}

# `harness/githooks/pre-push` を偽物に差し替えてコミットする。
#
# $1 目印(偽の pre-push がログに残す)
# $2 偽の pre-push の結果(`fake_prepush_of` の $2。none なら pre-push を置かない)
# $3 コミットメッセージ
commit_with_prepush() {
  mkdir -p harness/githooks || exit 1
  if [ "$2" = none ]; then
    rm -f harness/githooks/pre-push
  else
    fake_prepush_of "$1" "$2" >harness/githooks/pre-push
  fi
  git add -A || exit 1
  commit_with_message "$3"
}

# `main` に base、`pr` に Red(`TDD: red`)と先端を積む。HEAD は `main` に戻して終わる。
#
# Why: HEAD を PR の先端と違うコミットに置く。同じだと、作業ツリーを作らずにその場で走らせた先端の結果も
# 正しく見える。
#
# $1 リポジトリの名前
# $2 Red の偽の pre-push の結果(`commit_with_prepush` の $2)
# $3 先端の偽の pre-push の結果
start_repo_on_main_with_red_pr() {
  start_repo_on_pr "$1"
  commit_with_prepush red "$2" "$(message_of red 'TDD: red')"
  commit_with_prepush head "$3" head
  git checkout -q main || exit 1
}

# 拾ったハッシュ 1 行を件名に直す。完全なハッシュでなければ `?<行>`。
#
# $1 拾い方が出した 1 行
subject_of() {
  local full
  full="$(git rev-parse -q --verify "$1^{commit}" 2>/dev/null)"
  if [ "$full" = "$1" ]; then
    git log -1 --format=%s "$1"
    return 0
  fi
  printf '?%s' "$1"
}

# 拾い方を走らせ、`exit=<終了コード> picked=<拾ったコミットの件名を , でつないだもの>` を出す。
# 拾い方の標準エラーは `$pick_stderr` に残す。
#
# $@ `red-commits.sh` へ渡す引数
pick_summary_of() {
  local output status=0 line subjects=()
  output="$(bash "$red_commits_script" "$@" 2>"$pick_stderr")" || status=$?
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    subjects+=("$(subject_of "$line")")
  done <<<"$output"
  printf 'exit=%s picked=%s' "$status" "$(IFS=,; printf '%s' "${subjects[*]}")"
}

# 最後の行の見出しを出す。`Red のコミットの検査: 結果 ` を除き、最初の `:` より前だけを残す。
# その形でなければ `?<最後の行>`。
#
# Why: `:` の後ろはハッシュと件数で、ケースごとに変わる。
#
# $1 確かめ方の標準出力
heading_of() {
  local last
  last="$(tail -n 1 <<<"$1")"
  case "$last" in
    "$heading_prefix"*)
      last="${last#"$heading_prefix"}"
      printf '%s' "${last%%:*}"
      ;;
    *) printf '?%s' "$last" ;;
  esac
}

# 偽の pre-push が残した目印を , でつないで出す。
logged_markers() {
  cut -d ' ' -f 1 "$FAKE_PREPUSH_LOG" | paste -sd , -
}

# 偽の pre-push が残した `<目印>=<受け取った PRE_PUSH_REQUIRE_ALL>` を , でつないで出す。
logged_require_all() {
  tr ' ' '=' <"$FAKE_PREPUSH_LOG" | paste -sd , -
}

# 確かめ方を走らせ、`exit=<終了コード> heading=<見出し> log=<目印>` を出す。
#
# $@ `check-red-commits.sh` へ渡す引数
check_summary_of() {
  local output status=0
  : >"$FAKE_PREPUSH_LOG"
  output="$(bash "$check_script" "$@" 2>/dev/null)" || status=$?
  printf 'exit=%s heading=%s log=%s' "$status" "$(heading_of "$output")" "$(logged_markers)"
}

# --- 拾い方(red-commits.sh) ---

start_repo_on_pr l1
commit_with_message "$(message_of plain)"
commit_with_message "$(message_of red 'TDD: red')"
report "exit=0 picked=red" "$(pick_summary_of main pr)" \
  "L1 Co-Authored-By と同じ最後の段落に TDD: red を持つコミットを拾い、印の無いコミットは拾わない"

start_repo_on_pr l2
commit_with_message "$(message_of lower 'tdd: red')"
report "exit=0 picked=lower" "$(pick_summary_of main pr)" "L2 キーが小文字の tdd: red でも拾う"

start_repo_on_pr l3
commit_with_message "$(message_of capital 'TDD: Red')"
commit_with_message "$(message_of control 'TDD: red')"
report "exit=0 picked=control" "$(pick_summary_of main pr)" "L3 値が Red のものは拾わない"

start_repo_on_pr l4
commit_with_message "$(message_of extra 'TDD: red extra')"
commit_with_message "$(message_of control 'TDD: red')"
report "exit=0 picked=control" "$(pick_summary_of main pr)" "L4 値が red extra のものは拾わない"

start_repo_on_pr l5
commit_with_message "$(printf 'not-last\n\nTDD: red\n\n%s\n' "$co_author")"
commit_with_message "$(message_of control 'TDD: red')"
report "exit=0 picked=control" "$(pick_summary_of main pr)" "L5 最後の段落でない TDD: red は拾わない"

start_repo_on_pr l6
commit_with_message 'TDD: red'
commit_with_message "$(message_of control 'TDD: red')"
report "exit=0 picked=control" "$(pick_summary_of main pr)" "L6 件名だけが TDD: red のものは拾わない"

start_repo_on_pr l7
commit_with_message "$(message_of pr-red 'TDD: red')"
git checkout -q main || exit 1
commit_with_message "$(message_of main-red 'TDD: red')"
report "exit=0 picked=pr-red" "$(pick_summary_of main pr)" \
  "L7 PR が枝分かれした後に main 側で進めた(PR には取り込まない)コミットの印は拾わない"

start_repo_on_pr l8
commit_with_message "$(message_of pr-red 'TDD: red')"
git checkout -q main || exit 1
commit_with_message "$(message_of main-red 'TDD: red')"
git checkout -q pr && git merge -q --no-edit main || exit 1
report "exit=0 picked=pr-red" "$(pick_summary_of main pr)" \
  "L8 PR が main を取り込んだマージを含んでも、取り込んだ main 側の印は拾わない"

start_repo_on_pr l9
commit_with_message "$(message_of red 'TDD: red')"
pick_summary="$(pick_summary_of main)"
report "exit=2" "${pick_summary%% *}" "L9 引数が 2 つでなければ使い方を出す"

start_repo_on_pr l10
commit_with_message "$(message_of red 'TDD: red')"
pick_summary="$(pick_summary_of main no-such-revision)"
report "exit=2" "${pick_summary%% *}" "L10 範囲を解決できない(存在しない revision)なら止まる"

start_repo_on_pr l11-source
commit_with_message base2
commit_with_message "$(message_of red 'TDD: red')"
commit_with_message head
git clone -q --depth 2 "file://$work/l11-source" "$work/l11" || exit 1
enter_repo "$work/l11"
pick_summary="$(pick_summary_of HEAD~1 HEAD)"
reason_on_stderr=no
[ -s "$pick_stderr" ] && reason_on_stderr=yes
report "exit=2 reason_on_stderr=yes" "${pick_summary%% *} reason_on_stderr=$reason_on_stderr" \
  "L11 浅いクローン(git clone --depth 2 file://…)なら、標準エラーに理由を出して止まる"

start_repo_on_pr l12
commit_with_message "$(message_of two 'TDD: green' 'TDD: red')"
report "exit=0 picked=two" "$(pick_summary_of main pr)" "L12 TDD のトレーラが 2 つあり、片方が red なら拾う"

start_repo_on_pr l13
commit_with_message "$(message_of folded 'TDD: red' '  extra')"
commit_with_message "$(message_of control 'TDD: red')"
report "exit=0 picked=control" "$(pick_summary_of main pr)" "L13 折り返した TDD: red と継続行は拾わない"

start_repo_on_pr l14
commit_with_message "$(message_of order 'TDD: red' 'TDD: green')"
report "exit=0 picked=order" "$(pick_summary_of main pr)" "L14 TDD のトレーラが 2 つあり、red が先で後ろが green でも拾う"

start_repo_on_pr l15
commit_with_message "$(message_of red 'TDD: red')"
pick_summary="$(pick_summary_of main pr extra)"
usage_on_stderr=no
grep -q '^使い方:' "$pick_stderr" && usage_on_stderr=yes
report "exit=2 usage_on_stderr=yes" "${pick_summary%% *} usage_on_stderr=$usage_on_stderr" \
  "L15 引数が 3 つなら、標準エラーに使い方を出して止まる"

start_repo_on_pr l16
commit_with_message "$(message_of tab $'TDD: green\tred')"
commit_with_message "$(message_of control 'TDD: red')"
report "exit=0 picked=control" "$(pick_summary_of main pr)" "L16 値が green<TAB>red のものは拾わない"

start_repo_on_pr l17
commit_with_message "$(message_of red 'TDD: red')"
pick_summary="$(pick_summary_of main '')"
reason_on_stderr=no
[ -s "$pick_stderr" ] && reason_on_stderr=yes
report "exit=2 reason_on_stderr=yes" "${pick_summary%% *} reason_on_stderr=$reason_on_stderr" \
  "L17 head が空なら、HEAD と読まずに標準エラーに理由を出して止まる"

start_repo_on_pr l18
commit_with_message "$(message_of red 'TDD: red')"
: >'main..unknown' || exit 1
pick_summary="$(pick_summary_of main unknown)"
reason_on_stderr=no
[ -s "$pick_stderr" ] && reason_on_stderr=yes
report "exit=2 reason_on_stderr=yes" "${pick_summary%% *} reason_on_stderr=$reason_on_stderr" \
  "L18 存在しない revision は、作業ツリーに同じ名前のパスがあっても、標準エラーに理由を出して止まる"

# --- 確かめ方(check-red-commits.sh) ---

start_repo_on_main_with_red_pr c1 fail pass
report "exit=0 heading=通過(Red で落ち、PR の先端で通った) log=head,red" "$(check_summary_of main pr)" \
  "C1 Red で落ち、先端で通れば通す"

start_repo_on_main_with_red_pr c2 pass pass
report "exit=1 heading=失敗(Red のコミットで検査が落ちない log=head,red" "$(check_summary_of main pr)" \
  "C2 Red で通れば落とす"

start_repo_on_main_with_red_pr c3 pass fail
report "exit=1 heading=失敗(PR の先端で検査が通らない) log=head" "$(check_summary_of main pr)" \
  "C3 先端が落ちたら落とす(Red は通る偽物にして、先端と Red の順番の取り違えを落とす)"

start_repo_on_pr c4
commit_with_prepush plain fail plain
commit_with_prepush head pass head
git checkout -q main || exit 1
report "exit=0 heading=通過(Red の印のコミットが無い) log=" "$(check_summary_of main pr)" \
  "C4 Red の印が無ければ、先端を走らせずに通す"

start_repo_on_pr c5
commit_with_prepush red1 fail "$(message_of red1 'TDD: red')"
commit_with_prepush red2 fail "$(message_of red2 'TDD: red')"
commit_with_prepush head pass head
git checkout -q main || exit 1
report "exit=1 heading=失敗(Red が 2 つ以上ある log=" "$(check_summary_of main pr)" "C5 Red が 2 つ以上なら落とす"

start_repo_on_main_with_red_pr c6 fail pass
check_summary="$(check_summary_of main pr)"
report "exit=0 log=head=1,red=1" "${check_summary%% *} log=$(logged_require_all)" \
  "C6 検査には PRE_PUSH_REQUIRE_ALL=1 を渡す"

start_repo_on_main_with_red_pr c7 pass pass
check_summary="$(check_summary_of main pr)"
report "exit=1 worktrees=1" "${check_summary%% *} worktrees=$(git worktree list | grep -c '')" \
  "C7 Red が通って落としたときも、作業ツリーを残さない"

start_repo_on_main_with_red_pr c8 fail pass
head_before="$(git rev-parse HEAD)"
check_summary="$(check_summary_of main pr)"
head_moved=no
[ "$(git rev-parse HEAD)" = "$head_before" ] || head_moved=yes
report "exit=0 head_moved=no status=" \
  "${check_summary%% *} head_moved=$head_moved status=$(git status --porcelain)" \
  "C8 呼んだ側の HEAD と作業ツリーを変えない"

start_repo_on_main_with_red_pr c9 fail pass
report "exit=2 heading=確かめられない(Red の印のコミットを拾えない) log=" "$(check_summary_of no-such-revision pr)" \
  "C9 拾い方が失敗したら、Red 無しとして通さない"

start_repo_on_main_with_red_pr c10 fail pass
check_summary="$(check_summary_of main)"
report "exit=2 log=" "${check_summary%% *} log=$(logged_markers)" "C10 引数が 2 つでなければ使い方を出す"

start_repo_on_main_with_red_pr c11 none pass
report "exit=2 heading=確かめられない(Red のコミットの pre-push の結果を読めない) log=head" "$(check_summary_of main pr)" \
  "C11 Red の木に pre-push が無ければ通さない"

start_repo_on_main_with_red_pr c12 skip pass
report "exit=2 heading=確かめられない(Red のコミットの pre-push の結果を読めない) log=head,red" "$(check_summary_of main pr)" \
  "C12 Red の pre-push が飛ばしただけで落ちたなら通さない"

start_repo_on_main_with_red_pr c13 fail skip
report "exit=2 heading=確かめられない(PR の先端の pre-push の結果を読めない) log=head" "$(check_summary_of main pr)" \
  "C13 先端の pre-push が飛ばしただけで落ちたなら、先端の失敗ではなく「確かめられない」にする"

# GIT_DIR の向け先は main と pr を持ち Red の無いリポジトリにする。漏れを読むと「Red の印が無い」で通ってしまう。
start_repo_on_pr c14-other
commit_with_message head
start_repo_on_main_with_red_pr c14 fail pass
report "exit=0 heading=通過(Red で落ち、PR の先端で通った) log=head,red" \
  "$(GIT_DIR="$work/c14-other/.git" check_summary_of main pr)" \
  "C14 外から GIT_DIR が渡っても、カレントのリポジトリを確かめる"

start_repo_on_main_with_red_pr c15 fail silent
report "exit=2 heading=確かめられない(PR の先端の pre-push の結果を読めない) log=head" "$(check_summary_of main pr)" \
  "C15 先端の pre-push が結果行を出さずに exit 0 なら、通ったと数えない"

start_repo_on_main_with_red_pr c16 fail pass
: >"$FAKE_PREPUSH_LOG"
check_status=0
bash "$check_script" main pr extra >/dev/null 2>"$work/check-usage.err" || check_status=$?
usage_on_stderr=no
grep -q '^使い方:' "$work/check-usage.err" && usage_on_stderr=yes
report "exit=2 usage_on_stderr=yes log=" "exit=$check_status usage_on_stderr=$usage_on_stderr log=$(logged_markers)" \
  "C16 引数が 3 つなら、標準エラーに使い方を出して、pre-push を走らせずに止まる"

exit "$cases_failed"
