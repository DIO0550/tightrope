#!/usr/bin/env bash
#
# cargo の検査(`rust-checks.sh`)の判定表。
#
# ケースごとに path 依存を持つ使い捨てのクレートを組み(ネットワークは使わない)、そのディレクトリを
# カレントにして検査を呼ぶ。1 ケースの結果は次の 4 つを `:` でつないだ要約にして照らす。
#   pass / fail       検査の終了コードが 0 か
#   kept / changed    Cargo.lock が検査の前と同じ中身のまま残ったか(検査の前に無ければ、無いまま残ったか)
#   locked / -        標準出力か標準エラーに `--locked was passed to prevent this` が出たか
#   hint / -          標準エラーに、そのクレートの Cargo.toml を名指しして `harness/deps/resolve.sh update --workspace`
#                     を案内する行があるか(置き場はリポジトリの根ではないので `--manifest-path` が付く)
# 例外は 5 つ。G2〜G6 は path 依存を持たないクレートで組む。G1 は置き場の根で(クレートを組まずに)走らせ、終了コードを照らす。
# G5 は終了コードと、src/lib.rs が検査の前と同じ中身のまま残ったか(`kept / changed`)を照らす。R8 は path 依存も
# Cargo.lock も持たないクレートで組む。R9 は手元の cargo の代わりに、cargo 1.85〜1.92 の文言で止まる偽の cargo で走らせる
# (判定表は手元の toolchain でしか走らないので、旧版の文言は偽の cargo でしか出せない)。
#
# 使い方: bash harness/githooks/lib/rust-checks-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/rust-checks.sh"

source "$here/../../../.claude/hooks/lib/cases-report.sh"
source "$here/../../../.claude/hooks/lib/cases-fixtures.sh"

work="$(make_crate_workdir)" || exit 1
trap 'rm -rf "$work"' EXIT

# lock を作ってから、lock に無い path 依存を Cargo.toml に足したクレートを置き、そのディレクトリを出す。
#
# $1 ケースの名前(置き場のディレクトリ名)
crate_with_unlocked_dep_of() {
  local root="$work/$1"
  place_locked_crate "$root/app" app || exit 1
  add_path_dep "$root/app" "$root/dep" || exit 1
  echo "$root/app"
}

# クレートのディレクトリをカレントにして検査を走らせ、冒頭の要約を出す。
#
# $1 クレートのディレクトリ
# $2 検査の名前(`rust-checks.sh` の第 1 引数)
outcome_of() {
  local crate="$1" check="$2" status=0 result lock_state=changed locked=- hint=- had_lock=no
  [ -e "$crate/Cargo.lock" ] && had_lock=yes
  if [ "$had_lock" = yes ]; then
    cp "$crate/Cargo.lock" "$crate/../Cargo.lock.before" || exit 1
  fi
  (cd "$crate" && bash "$script" "$check") >"$crate/../stdout" 2>"$crate/../stderr" || status=$?
  result=pass
  [ "$status" -eq 0 ] || result=fail
  if [ "$had_lock" = yes ]; then
    cmp -s "$crate/../Cargo.lock.before" "$crate/Cargo.lock" && lock_state=kept
  else
    [ -e "$crate/Cargo.lock" ] || lock_state=kept
  fi
  cat "$crate/../stdout" "$crate/../stderr" | grep -qF -e '--locked was passed to prevent this' && locked=locked
  grep -qF "harness/deps/resolve.sh update --workspace --manifest-path $crate/Cargo.toml " "$crate/../stderr" && hint=hint
  printf '%s:%s:%s:%s' "$result" "$lock_state" "$locked" "$hint"
}

# path 依存を Cargo.toml に足してから lock を作り直した(lock が依存と合っている)クレートを置き、そのディレクトリを出す。
#
# $1 ケースの名前(置き場のディレクトリ名)
crate_with_locked_dep_of() {
  local root="$work/$1"
  place_locked_crate "$root/app" app || exit 1
  add_path_dep "$root/app" "$root/dep" || exit 1
  place_lockfile "$root/app" || exit 1
  echo "$root/app"
}

# 依存も Cargo.lock も持たないクレートを置き、そのディレクトリを出す。
#
# $1 ケースの名前(置き場のディレクトリ名)
crate_without_lock_of() {
  local root="$work/$1"
  place_locked_crate "$root/app" app || exit 1
  rm "$root/app/Cargo.lock" || exit 1
  echo "$root/app"
}

# clippy / doc / test では cargo 1.85〜1.92 の文言(`the lock file <path>/Cargo.lock needs to be updated but --locked
# was passed to prevent this`)を標準エラーに出して 101 で終わり、それ以外(案内を組むときの `locate-project`)は
# 手元の cargo へ渡す偽の cargo を置き、PATH の先頭に足す値を出す。
#
# $1 置き場のディレクトリ(その下の `old-cargo-bin/` に置く)
old_cargo_path_prefix() {
  local real_cargo
  real_cargo="$(command -v cargo)" || exit 1
  mkdir -p "$1/old-cargo-bin" || exit 1
  cat >"$1/old-cargo-bin/cargo" <<EOF || exit 1
#!/usr/bin/env bash
case "\$1" in
  clippy | doc | test)
    printf 'error: the lock file %s/Cargo.lock needs to be updated but --locked was passed to prevent this\n' "\$PWD" >&2
    exit 101
    ;;
esac
exec "$real_cargo" "\$@"
EOF
  chmod +x "$1/old-cargo-bin/cargo" || exit 1
  printf '%s:' "$1/old-cargo-bin"
}

# 依存を持たず、src/lib.rs に渡したソースを置いたクレートを、lock を添えて置き、そのディレクトリを出す。
#
# $1 ケースの名前(置き場のディレクトリ名)
# $2 src/lib.rs の中身
crate_with_source_of() {
  local root="$work/$1"
  place_locked_crate "$root/app" app || exit 1
  printf '%s' "$2" >"$root/app/src/lib.rs"
  echo "$root/app"
}

# クレートのディレクトリをカレントにして検査を走らせ、`pass / fail` と、src/lib.rs が検査の前と同じ中身のまま
# 残ったか(`kept / changed`)を `:` でつないで出す。
#
# $1 クレートのディレクトリ
# $2 検査の名前(`rust-checks.sh` の第 1 引数)
source_outcome_of() {
  local crate="$1" check="$2" result=pass source_state=changed
  cp "$crate/src/lib.rs" "$crate/../lib.rs.before" || exit 1
  (cd "$crate" && bash "$script" "$check") >/dev/null 2>&1 || result=fail
  cmp -s "$crate/../lib.rs.before" "$crate/src/lib.rs" && source_state=kept
  printf '%s:%s' "$result" "$source_state"
}

# 置き場の根をカレントにして検査を引数のまま走らせ、終了コードを出す。
#
# $@ `rust-checks.sh` に渡す引数
exit_status_of() {
  local status=0
  (cd "$work" && bash "$script" "$@") >/dev/null 2>&1 || status=$?
  echo "$status"
}

# 整形済みのソース。
formatted_source='pub fn one() -> i32 {
    1
}
'

report fail:kept:locked:hint "$(outcome_of "$(crate_with_unlocked_dep_of r1)" clippy)" \
  "R1 lock に無い依存があると、clippy は lock を書き換えず --locked で止まり、resolve.sh を案内して落ちる"
report fail:kept:locked:hint "$(outcome_of "$(crate_with_unlocked_dep_of r2)" doc)" \
  "R2 lock に無い依存があると、doc は lock を書き換えず --locked で止まり、resolve.sh を案内して落ちる"
report fail:kept:locked:hint "$(outcome_of "$(crate_with_unlocked_dep_of r3)" test)" \
  "R3 lock に無い依存があると、test は lock を書き換えず --locked で止まり、resolve.sh を案内して落ちる"
report pass:kept:-:- "$(outcome_of "$(crate_with_locked_dep_of r4)" clippy)" \
  "R4 lock が依存と合っていれば、clippy は lock を書き換えず通る"
report pass:kept:-:- "$(outcome_of "$(crate_with_locked_dep_of r5)" doc)" \
  "R5 lock が依存と合っていれば、doc は lock を書き換えず通る"
report pass:kept:-:- "$(outcome_of "$(crate_with_locked_dep_of r6)" test)" \
  "R6 lock が依存と合っていれば、test は lock を書き換えず通る"
r7="$(crate_with_unlocked_dep_of r7)"
printf '%s' "$formatted_source" >"$r7/src/lib.rs"
report pass:kept:-:- "$(outcome_of "$r7" fmt)" \
  "R7 lock に無い依存があっても、fmt は lock を書き換えず通る"
report fail:kept:locked:hint "$(outcome_of "$(crate_without_lock_of r8)" clippy)" \
  "R8 lock が無ければ、clippy は lock を作らず --locked で止まり、resolve.sh を案内して落ちる"
r9="$(crate_with_unlocked_dep_of r9)"
r9_path_prefix="$(old_cargo_path_prefix "$work/r9")"
report fail:kept:locked:hint "$(PATH="$r9_path_prefix$PATH" outcome_of "$r9" clippy)" \
  "R9 cargo 1.85〜1.92 の文言で --locked に止められても、resolve.sh を案内して落ちる"

report 2 "$(exit_status_of)" "G1 検査の名前が無ければ exit 2"
report 2 "$(exit_status_of lint)" "G1 知らない検査の名前なら exit 2"
report fail:kept:-:- "$(outcome_of "$(crate_with_source_of g2 '/// [`hidden`] を呼ぶ。
pub fn shown() {
    hidden();
}

fn hidden() {}
')" doc)" \
  "G2 公開項目の doc から非公開項目へ intra-doc link を張ると、doc は落ちる"
report fail:kept:-:- "$(outcome_of "$(crate_with_source_of g3 'pub fn one() -> i32 {
    return 1;
}
')" clippy)" \
  "G3 lib に clippy の警告があれば clippy は落ち、resolve.sh を案内しない"
report fail:kept:-:- "$(outcome_of "$(crate_with_source_of g4 'pub fn one() -> i32 {
    1
}

#[cfg(test)]
mod tests {
    #[test]
    fn one_is_one() {
        assert_eq!(super::one(), 1);
        return;
    }
}
')" clippy)" \
  "G4 テストにだけ clippy の警告があっても clippy は落ちる"
report fail:kept "$(source_outcome_of "$(crate_with_source_of g5 'pub fn one()->i32{1}
')" fmt)" \
  "G5 整形されていなければ fmt は落ち、ファイルを書き換えない"
report fail:kept:-:- "$(outcome_of "$(crate_with_source_of g6 '#[cfg(test)]
mod tests {
    #[test]
    fn one_is_two() {
        assert_eq!(1, 2);
    }
}
')" test)" \
  "G6 落ちるテストがあれば test は落ちる"

exit "$cases_failed"
