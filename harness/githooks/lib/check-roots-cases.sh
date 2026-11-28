#!/usr/bin/env bash
#
# pre-push が行数・置き場所・コメント・フォルダの依存・lint の水準の属性・infrastructure の driver の外の I/O の検査に渡す根の判定表。
#
# 本物の `pre-push` と `harness/githooks/lib/*.sh` を使い捨てのリポジトリへ写し、集計の `check-tally.sh`
# だけを、検査を走らせずに名前とコマンドをタブ区切りで 1 行に書き出す偽物に差し替えて流す。根を決める
# 処理は `check-tally.sh` 以外に置く前提(ここに置くと偽物に差し替わって見えなくなる)。
# crate の名前は、このリポジトリの `crates/*/Cargo.toml` から読んだものに a・b・c を足して決める。
# 使い捨ての workspace にはその名前ごとに `Cargo.toml` と `src/` を置き、期待も同じ名前から組む。
#
# 使い方: bash harness/githooks/lib/check-roots-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。このリポジトリの `crates/*/Cargo.toml` から
# crate の名前を 1 つも読めなければ、ケースを走らせずに NG の行を出して exit 1。

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../../.." && pwd)"

source "$repo_root/.claude/hooks/lib/cases-report.sh"
source "$repo_root/.claude/hooks/lib/cases-fixtures.sh"

isolate_git_env

real_crate_names="$(
  for manifest in "$repo_root"/crates/*/Cargo.toml; do
    [ -f "$manifest" ] && basename "$(dirname "$manifest")"
  done
)"
if [ -z "$real_crate_names" ]; then
  echo 'NG   このリポジトリの crates/*/Cargo.toml から crate の名前を 1 つも読めなかった'
  exit 1
fi
crate_names="$(printf '%s\n' "$real_crate_names" a b c | LC_ALL=C sort -u)"

work="$(mktemp -d)" || exit 1
trap 'cd / && rm -rf "$work"' EXIT
repo="$work/repo"

mkdir -p "$repo/harness/githooks/lib" || exit 1
git -C "$repo" init -q || exit 1
cp "$here"/*.sh "$repo/harness/githooks/lib/" || exit 1
cp "$here/../pre-push" "$repo/harness/githooks/pre-push" || exit 1
cat >"$repo/harness/githooks/lib/check-tally.sh" <<'TALLY'
run_check() {
  printf '%s' "$1"
  shift
  printf '\t%s' "$@"
  printf '\n'
}
skip_following_checks() { :; }
resume_checks() { :; }
finish_checks() { return 0; }
TALLY

while IFS= read -r name; do
  mkdir -p "$repo/crates/$name/src" || exit 1
  printf '[package]\nname = "%s"\n' "$name" >"$repo/crates/$name/Cargo.toml" || exit 1
done <<<"$crate_names"
mkdir -p "$repo/crates/a/src/m" "$repo/crates/c/tests/fixtures" || exit 1
printf '// x\n#[allow(dead_code)]\n' >"$repo/crates/a/src/m/x.rs"
printf '// y\n#[allow(dead_code)]\n' >"$repo/crates/c/tests/cli.rs"
printf '// sample\n#[allow(dead_code)]\n' >"$repo/crates/c/tests/fixtures/sample.rs"

enter_repo "$repo"
written="$(bash harness/githooks/pre-push)"

# 書き出した行のうち、走らせるスクリプト(3 つ目の欄)が $1 のものを、書き出したままの形で 1 行ずつ出す。
#
# $1 走らせるスクリプト(リポジトリのルートからのパス)
checks_of() {
  local line fields
  while IFS= read -r line; do
    IFS=$'\t' read -r -a fields <<<"$line"
    [ "${fields[2]:-}" = "$1" ] || continue
    printf '%s\n' "$line"
  done <<<"$written"
}

# 標準入力の書き出した行を、1 つ目のタブを `|`、残りのタブを空白にした `<名前>|<コマンド>` の形で出す。
to_report_form() {
  local tab=$'\t'
  sed "s/$tab/|/; s/$tab/ /g"
}

# 1 行 1 つの並びを、並べ替えて `,` でつなぐ。
#
# $1 並び
joined_sorted() {
  printf '%s\n' "$1" | grep -v '^$' | LC_ALL=C sort | paste -sd ',' -
}

# crate ごとに、$2 の検査を `<見出し>(crates/<名前>/src)` の名前で根を 1 つ渡して走らせる行を
# `<名前>|<コマンド>` の形で出す。
#
# $1 見出し
# $2 走らせるスクリプト
per_crate_checks_of() {
  local name
  while IFS= read -r name; do
    printf '%s(crates/%s/src)|bash %s crates/%s/src\n' "$1" "$name" "$2" "$name"
  done <<<"$crate_names"
}

# 書き出した行のうち、走らせるスクリプトが $1 のものを走らせ、検査が報告した行の `<ファイル>:<行>` だけを 1 行ずつ出す。
#
# $1 走らせるスクリプト(リポジトリのルートからのパス)
reported_locations_of() {
  local fields
  while IFS=$'\t' read -r -a fields; do
    "${fields[@]:1}"
  done < <(checks_of "$1") | sed -nE 's/^([^:]+:[0-9]+): .*$/\1/p'
}

# 書き出した行のうち、走らせるスクリプトが $1 のものを走らせ、終了コードを 1 行ずつ出す。
#
# $1 走らせるスクリプト(リポジトリのルートからのパス)
exit_statuses_of() {
  local fields
  while IFS=$'\t' read -r -a fields; do
    "${fields[@]:1}" >/dev/null
    echo "$?"
  done < <(checks_of "$1")
}

length_script=harness/githooks/lib/test-file-length.sh
placement_script=harness/githooks/lib/test-placement.sh
comment_script=harness/githooks/lib/comment-style.sh
folder_script=harness/githooks/lib/folder-deps.sh
lint_level_script=harness/githooks/lib/lint-level-attributes.sh
io_outside_driver_script=harness/githooks/lib/io-outside-driver.sh

report "$(joined_sorted "$(per_crate_checks_of テストのファイルの行数 "$length_script")")" \
  "$(joined_sorted "$(checks_of "$length_script" | to_report_form)")" \
  "行数の検査は workspace のすべての crate の src を 1 つずつ受け取り、crates/*/tests は受け取らない"
report "$(joined_sorted "$(per_crate_checks_of テストの置き場所 "$placement_script")")" \
  "$(joined_sorted "$(checks_of "$placement_script" | to_report_form)")" \
  "置き場所の検査は workspace のすべての crate の src を 1 つずつ受け取り、crates/*/tests は受け取らない"
report "コメントの形|bash $comment_script crates" \
  "$(joined_sorted "$(checks_of "$comment_script" | to_report_form)")" \
  "コメントの検査は 1 回だけ走り、crates を根に受け取る"

report "crates/a/src/m/x.rs:1,crates/c/tests/cli.rs:1" \
  "$(joined_sorted "$(reported_locations_of "$comment_script")")" \
  "コメントの検査に渡した根では crates/*/tests の // は報告され、crate の tests/fixtures/ の // は報告されない"

report "フォルダの依存の許可表|bash $folder_script" \
  "$(checks_of "$folder_script" | to_report_form)" \
  "フォルダの依存の検査は根を渡さずに 1 回だけ走る"

report "lint の水準の属性|bash $lint_level_script" \
  "$(checks_of "$lint_level_script" | to_report_form)" \
  "lint の水準の属性の検査は根を渡さずに 1 回だけ走る"
report "infrastructure の driver の外の I/O|bash $io_outside_driver_script" \
  "$(checks_of "$io_outside_driver_script" | to_report_form)" \
  "infrastructure の driver の外の I/O の検査は根を渡さずに 1 回だけ走る"
report "crates/a/src/m/x.rs:2,crates/c/tests/cli.rs:2,crates/c/tests/fixtures/sample.rs:2" \
  "$(joined_sorted "$(reported_locations_of "$lint_level_script")")" \
  "pre-push の呼び方で、crates/*/src・crates/*/tests・crate の tests/fixtures/ の lint の水準の属性が報告される"

report 1 "$(joined_sorted "$(exit_statuses_of "$comment_script")")" \
  "pre-push の呼び方で、違反のある木ではコメントの検査が exit 1 で終わる"
report 1 "$(joined_sorted "$(exit_statuses_of "$lint_level_script")")" \
  "pre-push の呼び方で、違反のある木では lint の水準の属性の検査が exit 1 で終わる"

mkdir -p "$repo/crates/c/tests/support" || exit 1
printf '// helper\n' >"$repo/crates/c/tests/support/helper.rs"
report "crates/a/src/m/x.rs:1,crates/c/tests/cli.rs:1,crates/c/tests/support/helper.rs:1" \
  "$(joined_sorted "$(reported_locations_of "$comment_script")")" \
  "コメントの検査に渡した根では、crate の tests/ の下の fixtures/ と同じ深さにある support/ の // も報告される"
rm -r "$repo/crates/c/tests/support" || exit 1

exit "$cases_failed"
