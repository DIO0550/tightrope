#!/usr/bin/env bash
#
# テストのファイルの行数の検査(`test-file-length.sh`)の判定表。
#
# ケースごとに使い捨ての根を作ってファイルを置き、検査の終了コードと見出しから pass / deny / broken を読む。
# deny のときは並んだ行の集合まで期待と完全一致で比べる(どのファイルを何行と数えたかまで見ないと、
# 測る場所や数え方を壊しても、対照の 1 件で落ちたまま ok に残る)。
# 検査できなかったケースは、終了コードを 2 と比べる(`decide` は見出しの無い exit 1 も broken と読むので、
# exit 2 が 1 に退行しても ok に残る)。
# 根を渡さない・空の根を渡す・根を 2 つ渡すケースは、検査できなかった理由が標準エラーに出るかまで照らす
# (`cases-allowlist.sh` の `run_unavailable_case`)。
#
# 使い方: bash harness/githooks/lib/test-file-length-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/test-file-length.sh"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT

source "$here/../../../.claude/hooks/lib/cases-report.sh"
source "$here/cases-allowlist.sh"
source "$here/../../../.claude/hooks/lib/cases-fixtures.sh"

# 上限の値は入れない(値を検査と判定表の 2 箇所に持たない)。
heading='^テストのファイルが [0-9]+ 行を超えています'

# ファイルに <行数> 行を書く。中身は `$(..)` を通さず直接書く(`$(..)` は末尾の改行を落とす)。
#
# $1 置くファイルのパス
# $2 `<行数>`(各行 `x`)/ `<行数>:no-eol`(最後の行に改行が無い)/ `<行数>:blank`(空行だけ)
write_lines() {
  local file="$1" spec="$2" count="${2%%:*}"
  case "$spec" in
    *:no-eol)
      yes x | head -n "$((count - 1))" >"$file"
      printf 'x' >>"$file"
      ;;
    *:blank) yes '' | head -n "$count" >"$file" ;;
    *) yes x | head -n "$count" >"$file" ;;
  esac
}

# 使い捨ての根にファイルを置いて検査を走らせ、判定を 1 語で出す。deny のときは続けて、見出しを除いた行から
# `<根>/` を落として `,` で繋いだものを出す(`deny a/tests.rs: 101 行`)。
#
# $1 ケースの名前(根のディレクトリ名)
# $2 以降 置くファイル。`<相対パス>` と `write_lines` の行数の指定を交互に並べる
verdict_of() {
  local root="$work/$1"
  shift
  mkdir -p "$root"
  while [ "$#" -ge 2 ]; do
    mkdir -p "$(dirname "$root/$1")"
    write_lines "$root/$1" "$2"
    shift 2
  done
  local output status verdict
  output="$(bash "$script" "$root")"
  status=$?
  verdict="$(decide "$output" "$status" "$heading")"
  if [ "$verdict" != deny ]; then
    echo "$verdict"
    return 0
  fi
  # Why not(sed で `<根>/` を消す): sed は根を正規表現として読み、一時ディレクトリに `[` などがあると除けない。
  local line listed=()
  while IFS= read -r line; do
    listed+=("${line#"$root/"}")
  done < <(printf '%s\n' "$output" | grep -vE "$heading")
  printf 'deny %s\n' "$(printf '%s\n' "${listed[@]}" | paste -sd ',' -)"
}

report "deny a/tests.rs: 101 行" "$(verdict_of tests-rs a/tests.rs 101)" \
  "上限を超えた tests.rs を、その 1 件だけ並べて落とす"
report "deny a/tests/ordering.rs: 101 行" "$(verdict_of tests-child a/tests/ordering.rs 101)" \
  "tests/ の下のテストの観点のファイルも測る"
report "deny a/b/tests.rs: 101 行" "$(verdict_of nested a/b/tests.rs 101)" \
  "下の階層の tests.rs も測る"
report "deny a/b/c/d/e/f/g/h/i/j/tests/x.rs: 101 行" "$(verdict_of deep a/b/c/d/e/f/g/h/i/j/tests/x.rs 101)" \
  "深い階層のテストのファイルも測る"
report "deny tests.rs: 101 行" "$(verdict_of crate-root tests.rs 101)" \
  "根の直下の tests.rs も測る"
report pass "$(verdict_of exact a/tests.rs 100)" \
  "ちょうど上限の行数は通す"
report "deny a/tests.rs: 101 行" "$(verdict_of no-eol a/tests.rs 101:no-eol)" \
  "末尾に改行の無い最後の行も 1 行に数える"
report "deny a/tests.rs: 101 行" "$(verdict_of blank a/tests.rs 101:blank)" \
  "空行も 1 行に数える"
report "deny a/tests.rs: 101 行" "$(verdict_of impl a.rs 300 a/tests.rs 101)" \
  "実装のファイルは上限を超えていても並べない"
report "deny a/tests.rs: 101 行" "$(verdict_of suffix-only a/contests.rs 101 a/tests.rs 101)" \
  "名前が tests.rs で終わるだけのファイルは測らない"
report "deny a/tests.rs: 101 行" "$(verdict_of suffix-only-dir a/contests/x.rs 101 a/tests.rs 101)" \
  "名前が tests で終わるだけのディレクトリの下は測らない"
report "deny a/tests.rs: 101 行" "$(verdict_of not-rs a/tests/data.txt 101 a/tests.rs 101)" \
  "tests/ の下でも .rs でないファイルは測らない"
report "deny a/tests.rs: 101 行" "$(verdict_of rooted-in-tests/tests a.rs 101 a/tests.rs 101)" \
  "根が tests/ の下にあっても、根の中の実装のファイルは測らない"
report pass "$(verdict_of empty a/tests.rs 0)" \
  "0 バイトの tests.rs は通す"
report pass "$(verdict_of no-tests a.rs 300)" \
  "テストのファイルが無い根は通す"
report "deny a/b/tests.rs: 120 行,a/tests.rs: 101 行" "$(verdict_of two a/tests.rs 101 a/b/tests.rs 120)" \
  "上限を超えたファイルが 2 つあれば 2 つとも並べる"

# CDPATH が設定された環境。pre-push と同じく、検査と <根> を相対パスで渡す。
mkdir -p "$work/cdpath/harness/githooks/lib" "$work/cdpath/src/a"
cp "$script" "$here/test-file-path.sh" "$work/cdpath/harness/githooks/lib/"
write_lines "$work/cdpath/src/a/tests.rs" 1
cdpath_output="$(cd "$work/cdpath" && CDPATH=. bash harness/githooks/lib/test-file-length.sh src)"
cdpath_status=$?
report pass "$(decide "$cdpath_output" "$cdpath_status" "$heading")" \
  "CDPATH が設定されていても、上限を超えたものが無い根は通す"

bash "$script" "$work/missing" >/dev/null 2>&1
missing_status=$?
report "exit 2" "exit $missing_status" \
  "根が無ければ exit 2(pass とも、違反を並べた exit 1 とも読まない)"

# 根の数と中身。根を渡さない呼び出しは、カレントディレクトリに src を置き、そこへ倒れないことを見る。
root_usage_pattern='根に crate の src のディレクトリ\(crates/<crate>/src\)を 1 つ渡してください'
no_root_usage_line="^test-file-length: ${root_usage_pattern}（受け取った根の数: 0）$"
empty_root_usage_line="^test-file-length: ${root_usage_pattern}（受け取った根: 空）$"
two_roots_usage_line="^test-file-length: ${root_usage_pattern}（受け取った根の数: 2）$"
mkdir -p "$work/no-root/src/a"
write_lines "$work/no-root/src/a/tests.rs" 1
run_unavailable_case "$no_root_usage_line" \
  "根を渡さなければ、カレントディレクトリに src があっても、何を渡すかを言って検査できない" \
  run_in_root "$work/no-root"
run_unavailable_case "$empty_root_usage_line" \
  "空の根を渡しても、何を渡すかを言って検査できない" \
  bash "$script" ""
mkdir -p "$work/two-roots/first/a" "$work/two-roots/second/a"
write_lines "$work/two-roots/first/a/tests.rs" 1
write_lines "$work/two-roots/second/a/tests.rs" 101
run_unavailable_case "$two_roots_usage_line" \
  "根を 2 つ渡すと、2 つ目に違反があっても、何を渡すかを言って検査できない" \
  bash "$script" "$work/two-roots/first" "$work/two-roots/second"

# 走査そのものの失敗。
mkdir -p "$work/scan-fails/a"
write_lines "$work/scan-fails/a/tests.rs" 1
PATH="$(failing_awk_path_prefix "$work")$PATH" bash "$script" "$work/scan-fails" >/dev/null 2>&1
scan_status=$?
report "exit 2" "exit $scan_status" \
  "走査に失敗したら exit 2(上限を超えたものが無い pass とも、exit 1 とも読まない)"

# 共有の一覧が読めないとき。検査だけを使い捨ての場所へ写すと、隣に test-file-path.sh が無い。
mkdir -p "$work/script-alone" "$work/unshared/a"
cp "$script" "$work/script-alone/"
write_lines "$work/unshared/a/tests.rs" 101
bash "$work/script-alone/test-file-length.sh" "$work/unshared" >/dev/null 2>&1
unshared_status=$?
report "exit 2" "exit $unshared_status" \
  "共有の test-file-path.sh が読めなければ exit 2(一覧が空の pass とも、exit 1 とも読まない)"

exit "$cases_failed"
