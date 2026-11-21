#!/usr/bin/env bash
#
# cargo の検査(`rust-checks.sh`)の判定表。
#
# ケースごとに path 依存を持つ使い捨てのクレートを組み(ネットワークは使わない)、そのディレクトリを
# カレントにして検査を呼ぶ。1 ケースの結果は次の 4 つを `:` でつないだ要約にして照らす。
#   pass / fail       検査の終了コードが 0 か
#   kept / changed    Cargo.lock が検査の前と同じ中身のまま残ったか
#   locked / -        標準出力か標準エラーに `because --locked was passed` が出たか
#   hint / -          標準エラーに `harness/deps/resolve.sh` を含む行があるか
#
# 使い方: bash harness/githooks/lib/rust-checks-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
detector="$here/rust-checks.sh"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT

source "$here/../../../.claude/hooks/lib/cases-report.sh"

# 依存を持たないクレートを置く。`[workspace]` を置くのは、置き場より上の階層の Cargo.toml を cargo が
# ワークスペースの根と取り違えないため。
#
# $1 クレートのディレクトリ
# $2 パッケージ名
place_crate() {
  mkdir -p "$1/src"
  printf '[package]\nname = "%s"\nversion = "0.1.0"\nedition = "2024"\n\n[workspace]\n' "$2" >"$1/Cargo.toml"
  : >"$1/src/lib.rs"
}

# lock を作ってから、lock に無い path 依存を Cargo.toml に足したクレートを置き、そのディレクトリを出す。
#
# $1 ケースの名前(置き場のディレクトリ名)
crate_missing_from_lock_of() {
  local root="$work/$1"
  place_crate "$root/dep" dep
  place_crate "$root/app" app
  (cd "$root/app" && cargo generate-lockfile --offline --quiet) || exit 1
  printf '\n[dependencies]\ndep = { path = "../dep" }\n' >>"$root/app/Cargo.toml"
  echo "$root/app"
}

# クレートのディレクトリをカレントにして検査を走らせ、冒頭の要約を出す。
#
# $1 クレートのディレクトリ
# $2 検査の名前(`rust-checks.sh` の第 1 引数)
outcome_of() {
  local crate="$1" check="$2" status=0 result lock_state=changed locked=- hint=-
  cp "$crate/Cargo.lock" "$crate/../Cargo.lock.before" || exit 1
  (cd "$crate" && bash "$detector" "$check") >"$crate/../stdout" 2>"$crate/../stderr" || status=$?
  result=pass
  [ "$status" -eq 0 ] || result=fail
  cmp -s "$crate/../Cargo.lock.before" "$crate/Cargo.lock" && lock_state=kept
  cat "$crate/../stdout" "$crate/../stderr" | grep -qF 'because --locked was passed' && locked=locked
  grep -qF 'harness/deps/resolve.sh' "$crate/../stderr" && hint=hint
  printf '%s:%s:%s:%s' "$result" "$lock_state" "$locked" "$hint"
}

report fail:kept:locked:hint "$(outcome_of "$(crate_missing_from_lock_of r1)" clippy)" \
  "R1 lock に無い依存があると、clippy は lock を書き換えず --locked で止まり、resolve.sh を案内して落ちる"
report fail:kept:locked:hint "$(outcome_of "$(crate_missing_from_lock_of r2)" doc)" \
  "R2 lock に無い依存があると、doc は lock を書き換えず --locked で止まり、resolve.sh を案内して落ちる"
report fail:kept:locked:hint "$(outcome_of "$(crate_missing_from_lock_of r3)" test)" \
  "R3 lock に無い依存があると、test は lock を書き換えず --locked で止まり、resolve.sh を案内して落ちる"

exit "$cases_failed"
