#!/usr/bin/env bash
#
# テストの置き場所の検査(`test-placement.sh`)の判定表。
#
# ケースごとに使い捨ての根を作ってファイルを置き、検査の終了コードと見出しから pass / deny を読む。
#
# 使い方: bash harness/githooks/lib/test-placement-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
detector="$here/test-placement.sh"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT

source "$here/../../../.claude/hooks/lib/cases-report.sh"

heading='^テストが実装と同じファイルにあります'
inline_tests=$'pub fn f() -> u8 { 1 }\n\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn f_is_one() {}\n}\n'
out_of_line=$'pub fn f() -> u8 { 1 }\n\n#[cfg(test)]\nmod tests;\n'
test_fn=$'#[test]\nfn f_is_one() {}\n'

# 使い捨ての根に `<相対パス>=<中身>` のファイルを置き、検査の判定を 1 語で出す。
#
# $1 ケースの名前(根のディレクトリ名)
# $2 以降 置くファイル。`<相対パス>` と `<中身>` を交互に並べる
verdict_of() {
  local root="$work/$1"
  shift
  mkdir -p "$root"
  while [ "$#" -ge 2 ]; do
    mkdir -p "$(dirname "$root/$1")"
    printf '%s' "$2" >"$root/$1"
    shift 2
  done
  local output status
  output="$(bash "$detector" "$root")"
  status=$?
  decide "$output" "$status" "$heading"
}

report deny "$(verdict_of inline a.rs "$inline_tests")" \
  "実装と同じファイルの mod tests { .. } を落とす"
report deny "$(verdict_of bare-test-fn a.rs "$test_fn")" \
  "mod tests を持たずに実装のファイルへ置いた #[test] を落とす"
report deny "$(verdict_of nested a/b.rs "$inline_tests")" \
  "下の階層の実装のファイルにあるテストも落とす"
report deny "$(verdict_of suffix-only a/contests.rs "$test_fn")" \
  "名前が tests.rs で終わるだけのファイルは置き場所に数えない"
report pass "$(verdict_of split a.rs "$out_of_line" a/tests.rs "$test_fn")" \
  "mod tests; と a/tests.rs に分けたテストは通す"
report pass "$(verdict_of crate-root lib.rs "$out_of_line" tests.rs "$test_fn")" \
  "クレートのルートが読む tests.rs は通す"
report pass "$(verdict_of tests-child a/tests.rs "$test_fn" a/tests/helpers.rs "$test_fn")" \
  "tests.rs を分けた tests/ の下のファイルは通す"
report pass "$(verdict_of no-tests a.rs 'pub fn f() -> u8 { 1 }')" \
  "テストが 1 つも無い根は通す"
# 根そのものが `.../tests` の形。絶対パスで見ると a.rs が許されてしまう。
report deny "$(verdict_of rooted-in-tests/tests a.rs "$inline_tests")" \
  "根が tests/ の下にあっても、根の中の実装のファイルにあるテストは落とす"

missing_output="$(bash "$detector" "$work/missing" 2>/dev/null)"
missing_status=$?
report broken "$(decide "$missing_output" "$missing_status" "$heading")" \
  "根が無ければ exit 2(pass と読まない)"

exit "$cases_failed"
