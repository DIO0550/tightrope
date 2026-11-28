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
# 例外は 6 つ。G2〜G6 は path 依存を持たないクレートで組む。G1 は置き場の根で(クレートを組まずに)走らせ、終了コードを照らす。
# G5 は終了コードと、src/lib.rs が検査の前と同じ中身のまま残ったか(`kept / changed`)を照らす。R8 は path 依存も
# Cargo.lock も持たないクレートで組む。R9 は手元の cargo の代わりに、cargo 1.85〜1.92 の文言で止まる偽の cargo で走らせる
# (判定表は手元の toolchain でしか走らないので、旧版の文言は偽の cargo でしか出せない)。F1〜F12 は本番コードの
# `unwrap()` を workspace の lints で deny にしたクレートで、呼び出し側の rustflags の環境変数を外し、ケースの
# 環境変数か設定ファイルを置いて clippy を走らせ、deny が効いたか(`pass / deny / broken`)を照らす。
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
  printf '%s' "$2" >"$root/app/src/lib.rs" || exit 1
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

host="$(rustc -vV | sed -n 's/^host: //p')"
if [ -z "$host" ]; then
  echo 'NG   rustc -vV から手元の host の triple を読めなかった(F のケースを走らせずに止める)'
  exit 1
fi
host_rustflags_variable="CARGO_TARGET_$(printf '%s' "$host" | tr 'a-z-' 'A-Z_')_RUSTFLAGS"

# 本番コードの `unwrap()` を workspace の lints で deny にし、src/lib.rs に渡したソースを置いたクレートを、lock を添えて
# 置き、そのディレクトリを出す。
#
# $1 ケースの名前(置き場のディレクトリ名)
# $2 src/lib.rs の中身
crate_with_denied_unwrap_of() {
  local crate
  crate="$(crate_with_source_of "$1" "$2")" || exit 1
  printf '\n[workspace.lints.clippy]\nunwrap_used = "deny"\n\n[lints]\nworkspace = true\n' >>"$crate/Cargo.toml" || exit 1
  echo "$crate"
}

# `unwrap_used` が `Option` の `unwrap()` に出す診断の見出しの行。行頭の `error:` はソースの抜粋(行番号の欄が付く)には出ない。
unwrap_diagnostic_pattern='^error: used `unwrap()` on an `Option` value$'

# 呼び出し側から受け継いだ rustflags の環境変数を外し、色の指定を `CARGO_TERM_COLOR=never` に固定し、
# 渡した環境変数を付けて(渡した値のほうが勝つ)、クレートのディレクトリをカレントにして clippy の検査を走らせ、
# 判定を出す。
#   pass    検査が exit 0
#   deny    検査が落ち、標準エラーに `unwrap_used` の診断の見出しの行(`unwrap_diagnostic_pattern`)がある
#   broken  それ以外(型エラーなど別の理由で落ちたとき・クレートのディレクトリが無いときを含む)
#
# $1 クレートのディレクトリ
# $2 以降 付ける環境変数(`<名前>=<値>`)
unwrap_decision_of() {
  local crate="$1" status=0 denied=no
  shift
  if [ ! -d "$crate" ]; then
    echo broken
    return 0
  fi
  (cd "$crate" && env -u RUSTFLAGS -u CARGO_ENCODED_RUSTFLAGS -u CARGO_BUILD_RUSTFLAGS -u "$host_rustflags_variable" \
    CARGO_TERM_COLOR=never "$@" bash "$script" clippy) >"$crate/../stdout" 2>"$crate/../stderr" || status=$?
  if [ "$status" -eq 0 ]; then
    echo pass
    return 0
  fi
  grep -q "$unwrap_diagnostic_pattern" "$crate/../stderr" && denied=yes
  if [ "$denied" = yes ]; then
    echo deny
    return 0
  fi
  echo broken
}

# 本番コードで `unwrap()` を使うソース。
unwrap_source='pub fn first(values: &[i32]) -> i32 {
    *values.first().unwrap()
}
'

# `unwrap()` を使わないソース。
unwrap_free_source='pub fn first(values: &[i32]) -> Option<&i32> {
    values.first()
}
'

f1="$(crate_with_denied_unwrap_of f1 "$unwrap_source")" || exit 1
report deny "$(unwrap_decision_of "$f1")" \
  "F1 環境変数も設定ファイルの rustflags も無ければ、deny にした本番コードの unwrap() で clippy が落ちる"
f2="$(crate_with_denied_unwrap_of f2 "$unwrap_source")" || exit 1
report deny "$(unwrap_decision_of "$f2" RUSTFLAGS='-A clippy::unwrap_used')" \
  "F2 RUSTFLAGS='-A clippy::unwrap_used' でも、deny にした unwrap() で clippy が落ちる"
f3="$(crate_with_denied_unwrap_of f3 "$unwrap_source")" || exit 1
report deny "$(unwrap_decision_of "$f3" RUSTFLAGS='--cap-lints=warn')" \
  "F3 RUSTFLAGS='--cap-lints=warn' でも、deny にした unwrap() で clippy が落ちる"
f4="$(crate_with_denied_unwrap_of f4 "$unwrap_source")" || exit 1
report deny "$(unwrap_decision_of "$f4" CARGO_ENCODED_RUSTFLAGS='-Aclippy::unwrap_used')" \
  "F4 CARGO_ENCODED_RUSTFLAGS=-Aclippy::unwrap_used でも、deny にした unwrap() で clippy が落ちる"
f5="$(crate_with_denied_unwrap_of f5 "$unwrap_source")" || exit 1
report deny "$(unwrap_decision_of "$f5" CARGO_BUILD_RUSTFLAGS='-A clippy::unwrap_used')" \
  "F5 CARGO_BUILD_RUSTFLAGS='-A clippy::unwrap_used' でも、deny にした unwrap() で clippy が落ちる"
f6="$(crate_with_denied_unwrap_of f6 "$unwrap_source")" || exit 1
report deny "$(unwrap_decision_of "$f6" "$host_rustflags_variable=-A clippy::unwrap_used")" \
  "F6 CARGO_TARGET_<手元の triple>_RUSTFLAGS='-A clippy::unwrap_used' でも、deny にした unwrap() で clippy が落ちる"
f7="$(crate_with_denied_unwrap_of f7 "$unwrap_source")" || exit 1
mkdir -p "$f7/.cargo" || exit 1
printf '[build]\nrustflags = ["-A", "clippy::unwrap_used"]\n' >"$f7/.cargo/config.toml" || exit 1
report deny "$(unwrap_decision_of "$f7")" \
  "F7 .cargo/config.toml の [build] rustflags に -A を書いても、deny にした unwrap() で clippy が落ちる"
f8="$(crate_with_denied_unwrap_of f8 "$unwrap_source")" || exit 1
mkdir -p "$f8/.cargo" || exit 1
printf "[target.'cfg(all())']\nrustflags = [\"--cap-lints\", \"allow\"]\n" >"$f8/.cargo/config.toml" || exit 1
report deny "$(unwrap_decision_of "$f8")" \
  "F8 .cargo/config.toml の [target.'cfg(all())'] rustflags に --cap-lints allow を書いても、deny にした unwrap() で clippy が落ちる"
f9="$(crate_with_denied_unwrap_of f9 "$unwrap_free_source")" || exit 1
report pass "$(unwrap_decision_of "$f9" RUSTFLAGS='-A clippy::unwrap_used')" \
  "F9 unwrap() を使わなければ、RUSTFLAGS に -A を渡しても clippy は通る"
f10="$(crate_with_denied_unwrap_of f10 "$unwrap_source")" || exit 1
mkdir -p "$f10/.cargo" || exit 1
printf 'include = ["../extra.toml"]\n' >"$f10/.cargo/config.toml" || exit 1
printf '[build]\nrustflags = ["-A", "clippy::unwrap_used"]\n' >"$f10/extra.toml" || exit 1
report deny "$(unwrap_decision_of "$f10")" \
  "F10 .cargo/config.toml の include が読む先の rustflags に -A を書いても、deny にした unwrap() で clippy が落ちる"
f11="$(crate_with_denied_unwrap_of f11 "$unwrap_source")" || exit 1
mkdir -p "$work/f11/.cargo" || exit 1
printf '[build]\nrustflags = ["-A", "clippy::unwrap_used"]\n' >"$work/f11/.cargo/config.toml" || exit 1
report deny "$(unwrap_decision_of "$f11")" \
  "F11 クレートより上の階層の .cargo/config.toml の rustflags に -A を書いても、deny にした unwrap() で clippy が落ちる"
# 型が合わず、エラーの抜粋に語 `unwrap_used` が出るソース。
mistyped_source='pub fn lint_name() -> i32 {
    "unwrap_used"
}
'
f12="$(crate_with_denied_unwrap_of f12 "$mistyped_source")" || exit 1
report broken "$(unwrap_decision_of "$f12")" \
  "F12 型エラーで落ちれば、エラーの抜粋に unwrap_used の語があっても deny と数えない"

exit "$cases_failed"
