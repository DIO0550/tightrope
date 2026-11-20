#!/usr/bin/env bash
#
# テストのファイルの行数の検査(`test-file-length.sh`)の判定表。
#
# ケースごとに使い捨ての根を作ってファイルを置き、検査の終了コードと見出しから pass / deny / broken を読む。
# deny のときは並んだ行の集合まで期待と完全一致で比べる(どのファイルを何行と数えたかまで見ないと、
# 測る場所や数え方を壊しても、対照の 1 件で落ちたまま ok に残る)。
#
# 使い方: bash harness/githooks/lib/test-file-length-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
detector="$here/test-file-length.sh"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT

source "$here/../../../.claude/hooks/lib/cases-report.sh"

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
  output="$(bash "$detector" "$root")"
  status=$?
  verdict="$(decide "$output" "$status" "$heading")"
  if [ "$verdict" != deny ]; then
    echo "$verdict"
    return 0
  fi
  printf 'deny %s\n' "$(printf '%s\n' "$output" | grep -vE "$heading" | sed "s|^$root/||" | paste -sd ',' -)"
}

report "deny a/tests.rs: 101 行" "$(verdict_of tests-rs a/tests.rs 101)" \
  "上限を超えた tests.rs を、その 1 件だけ並べて落とす"
report "deny a/tests/ordering.rs: 101 行" "$(verdict_of tests-child a/tests/ordering.rs 101)" \
  "tests/ の下の観点のファイルも測る"
report "deny a/b/tests.rs: 101 行" "$(verdict_of nested a/b/tests.rs 101)" \
  "下の階層の tests.rs も測る"
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

missing_output="$(bash "$detector" "$work/missing" 2>/dev/null)"
missing_status=$?
report broken "$(decide "$missing_output" "$missing_status" "$heading")" \
  "根が無ければ exit 2(pass と読まない)"

# 走査そのものの失敗。root で走るとパーミッションで読めなくできないので、awk を失敗するものに差し替える。
mkdir -p "$work/failing-bin" "$work/scan-fails/a"
printf '#!/bin/sh\necho "awk: cannot open" >&2\nexit 2\n' >"$work/failing-bin/awk"
chmod +x "$work/failing-bin/awk"
write_lines "$work/scan-fails/a/tests.rs" 1
scan_output="$(PATH="$work/failing-bin:$PATH" bash "$detector" "$work/scan-fails" 2>/dev/null)"
scan_status=$?
report broken "$(decide "$scan_output" "$scan_status" "$heading")" \
  "走査に失敗したら exit 2(上限を超えたものが無い pass と読まない)"

# 共有の一覧が読めないとき。検査だけを使い捨ての場所へ写すと、隣に test-file-path.sh が無い。
mkdir -p "$work/detector-alone" "$work/unshared/a"
cp "$detector" "$work/detector-alone/"
write_lines "$work/unshared/a/tests.rs" 101
unshared_output="$(bash "$work/detector-alone/test-file-length.sh" "$work/unshared" 2>/dev/null)"
unshared_status=$?
report broken "$(decide "$unshared_output" "$unshared_status" "$heading")" \
  "共有の test-file-path.sh が読めなければ exit 2(一覧が空の pass と読まない)"

exit "$cases_failed"
