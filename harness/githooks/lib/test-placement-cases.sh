#!/usr/bin/env bash
#
# テストの置き場所の検査(`test-placement.sh`)の判定表。
#
# ケースごとに使い捨ての根を作ってファイルを置き、検査の終了コードと見出しから pass / deny を読む。
# 検査できなかったケースは、終了コードを 2 と比べる(`decide` は見出しの無い exit 1 も broken と読むので、
# exit 2 が 1 に退行しても ok に残る)。
#
# 使い方: bash harness/githooks/lib/test-placement-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
detector="$here/test-placement.sh"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT

source "$here/../../../.claude/hooks/lib/cases-report.sh"
source "$here/../../../.claude/hooks/lib/cases-fixtures.sh"

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
report deny "$(verdict_of suffix-only-dir a/contests/x.rs "$test_fn")" \
  "名前が tests で終わるだけのディレクトリは置き場所に数えない"
report pass "$(verdict_of split a.rs "$out_of_line" a/tests.rs "$test_fn")" \
  "mod tests; と a/tests.rs に分けたテストは通す"
report pass "$(verdict_of crate-root lib.rs "$out_of_line" tests.rs "$test_fn")" \
  "クレートのルートが読む tests.rs は通す"
report pass "$(verdict_of tests-child a/tests.rs "$test_fn" a/tests/helpers.rs "$test_fn")" \
  "tests.rs を分けた tests/ の下のファイルは通す"
report pass "$(verdict_of no-tests a.rs 'pub fn f() -> u8 { 1 }')" \
  "テストが 1 つも無い根は通す"
report deny "$(verdict_of path-attr a.rs $'#[tokio::test]\nasync fn f_is_one() {}\n')" \
  "道のついたテストの属性(#[tokio::test])も落とす"
report deny "$(verdict_of cfg-attr-test a.rs $'#[cfg_attr(test, test)]\nfn f_is_one() {}\n')" \
  "#[cfg_attr(test, test)] も落とす"
report deny "$(verdict_of cfg-test-other-name a.rs $'#[cfg(test)]\n// 補助\n#[allow(unused)]\npub(crate) mod helpers {\n    fn h() {}\n}\n')" \
  "#[cfg(test)] の直後に中身ごと書いたモジュールは、名前が tests でなくても落とす"
report pass "$(verdict_of doc-example a.rs $'/// ```\n/// #[test]\n/// fn f() {}\n/// ```\npub fn f() {}\n')" \
  "doc コメントの例の中の #[test] は拾わない"
report pass "$(verdict_of in-string a.rs $'pub const S: &str = "#[test] mod tests {";\n')" \
  "文字列の中の #[test] / mod tests { は拾わない"
report pass "$(verdict_of cfg-test-then-code a.rs $'#[cfg(test)]\nuse std::fmt;\n\nmod real {\n    pub fn f() {}\n}\n')" \
  "#[cfg(test)] が別の項目に掛かった後のモジュールは拾わない"

# CDPATH が設定された環境。pre-push と同じく、検査と <根> を相対パスで渡す。
mkdir -p "$work/cdpath/harness/githooks/lib" "$work/cdpath/src/a"
cp "$detector" "$here/test-file-path.sh" "$work/cdpath/harness/githooks/lib/"
printf '%s' "$out_of_line" >"$work/cdpath/src/a.rs"
printf '%s' "$test_fn" >"$work/cdpath/src/a/tests.rs"
cdpath_output="$(cd "$work/cdpath" && CDPATH=. bash harness/githooks/lib/test-placement.sh src)"
cdpath_status=$?
report pass "$(decide "$cdpath_output" "$cdpath_status" "$heading")" \
  "CDPATH が設定されていても、置き場所を外れたテストが無い根は通す"

# 走査そのものの失敗。
mkdir -p "$work/scan-fails"
printf 'pub fn f() {}\n' >"$work/scan-fails/a.rs"
PATH="$(failing_awk_path_prefix "$work")$PATH" bash "$detector" "$work/scan-fails" >/dev/null 2>&1
scan_status=$?
report "exit 2" "exit $scan_status" \
  "走査に失敗したら exit 2(違反なしの pass とも、exit 1 とも読まない)"

# 根そのものが `.../tests` の形。絶対パスで見ると a.rs が許されてしまう。
report deny "$(verdict_of rooted-in-tests/tests a.rs "$inline_tests")" \
  "根が tests/ の下にあっても、根の中の実装のファイルにあるテストは落とす"

bash "$detector" "$work/missing" >/dev/null 2>&1
missing_status=$?
report "exit 2" "exit $missing_status" \
  "根が無ければ exit 2(pass とも、違反を並べた exit 1 とも読まない)"

# 共有の一覧が読めないとき。検査だけを使い捨ての場所へ写すと、隣に test-file-path.sh が無い。
mkdir -p "$work/detector-alone" "$work/unshared"
cp "$detector" "$work/detector-alone/"
printf '%s' "$inline_tests" >"$work/unshared/a.rs"
bash "$work/detector-alone/test-placement.sh" "$work/unshared" >/dev/null 2>&1
unshared_status=$?
report "exit 2" "exit $unshared_status" \
  "共有の test-file-path.sh が読めなければ exit 2(違反なしの pass とも、exit 1 とも読まない)"

exit "$cases_failed"
