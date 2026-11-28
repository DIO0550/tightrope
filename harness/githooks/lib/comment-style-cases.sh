#!/usr/bin/env bash
#
# コメントの形の検査(`comment-style.sh`)の判定表。
#
# ケースごとに使い捨ての根を作ってファイルを置き、検査の終了コードと見出しから pass / deny を読む。
# 根を渡さないケースは、検査できなかった理由が標準エラーに出るかまで照らす(`cases-allowlist.sh` の
# `run_unavailable_case`)。
#
# 使い方: bash harness/githooks/lib/comment-style-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/comment-style.sh"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT

source "$here/../../../.claude/hooks/lib/cases-report.sh"
source "$here/cases-allowlist.sh"

heading='^doc 以外のコメントがあります'

# 使い捨ての根に `<相対パス>` と `<中身>` を交互に並べたファイルを置き、検査の判定を 1 語で出す。
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
  output="$(bash "$script" "$root")"
  status=$?
  decide "$output" "$status" "$heading"
}

report deny "$(verdict_of line-comment a.rs $'// 理由\nfn f() {}\n')" \
  "行頭の通常のコメントを落とす"
report deny "$(verdict_of indented a.rs $'fn f() {\n    // 理由\n}\n')" \
  "字下げした通常のコメントも落とす"
report deny "$(verdict_of empty-comment a.rs $'//\nfn f() {}\n')" \
  "中身の無い // も落とす"
report deny "$(verdict_of why-in-doc a.rs $'/// 距離。\n///\n/// Why: 並べ替えると比較が変わる。\nfn f() {}\n')" \
  "doc の中の Why: を落とす"
report deny "$(verdict_of why-not-in-module-doc a.rs $'//! 語彙。\n//! Why not（手書き）: 2 箇所になる。\n')" \
  "モジュールの doc の中の Why not（..）: も落とす"
report deny "$(verdict_of nested a/b.rs $'fn f() {\n    // 理由\n}\n')" \
  "下の階層のファイルも見る"
report deny "$(verdict_of deep a/b/c/d/e/f/g/h/i/j/k/l.rs $'fn f() {\n    // 理由\n}\n')" \
  "深い階層のファイルも見る"
report pass "$(verdict_of doc-only a.rs $'//! 語彙。\n\n/// 距離。\n///\n/// # Errors\n///\n/// 読めないとき。\nfn f() {}\n')" \
  "doc だけのファイルは通す"
report pass "$(verdict_of url-in-string a.rs $'pub const U: &str = "https://example.com";\n')" \
  "行頭でない // (文字列の URL)は拾わない"
report pass "$(verdict_of why-word-in-doc a.rs $'/// Why という語を含む説明。\nfn f() {}\n')" \
  "doc の中で Why: の形でない語は拾わない"
report pass "$(verdict_of fixtures fixtures/x.rs $'// 解析対象のサンプル\n' a.rs $'fn f() {}\n')" \
  "fixtures/ の下は見ない"
report pass "$(verdict_of nested-fixtures crate/tests/fixtures/x.rs $'// 解析対象のサンプル\n' crate/tests/a.rs $'fn f() {}\n')" \
  "根より深い階層の fixtures/ の下も見ない"
report pass "$(verdict_of not-rust a.sh $'# 理由\n// これは Rust ではない\n')" \
  ".rs 以外のファイルは見ない"
report deny "$(verdict_of support-beside-fixtures crate/tests/fixtures/x.rs $'// 解析対象のサンプル\n' crate/tests/support/h.rs $'// 補助\n')" \
  "根より深い階層の fixtures/ と同じ深さの、fixtures/ でないディレクトリは見る"

mkdir -p "$work/failing-bin" "$work/scan-fails"
printf '#!/bin/sh\necho "awk: cannot open" >&2\nexit 2\n' >"$work/failing-bin/awk"
chmod +x "$work/failing-bin/awk"
printf 'fn f() {}\n' >"$work/scan-fails/a.rs"
scan_output="$(PATH="$work/failing-bin:$PATH" bash "$script" "$work/scan-fails" 2>/dev/null)"
scan_status=$?
report broken "$(decide "$scan_output" "$scan_status" "$heading")" \
  "走査に失敗したら exit 2(違反なしの pass と読まない)"

missing_output="$(bash "$script" "$work/missing" 2>/dev/null)"
missing_status=$?
report broken "$(decide "$missing_output" "$missing_status" "$heading")" \
  "根が無ければ exit 2(pass と読まない)"

# 根を渡さない呼び出し。カレントディレクトリに src と tests を置き、そこへ倒れないことを見る。
mkdir -p "$work/no-root/src" "$work/no-root/tests"
printf 'fn f() {}\n' >"$work/no-root/src/a.rs"
printf 'fn g() {}\n' >"$work/no-root/tests/b.rs"
no_root_usage_line='^comment-style: 根に検査するディレクトリ\(crates など\)を 1 つ以上渡してください（受け取った根の数: 0）$'
run_unavailable_case "$no_root_usage_line" \
  "根を渡さなければ、カレントディレクトリに src と tests があっても、何を渡すかを言って検査できない" \
  run_in_root "$work/no-root"

exit "$cases_failed"
