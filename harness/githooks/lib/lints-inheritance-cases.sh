#!/usr/bin/env bash
#
# workspace の lints の継承の検査(`lints-inheritance.sh`)の判定表。
#
# ケースごとに使い捨ての workspace を組み直し(根は `$work/ws`)、根を引数に渡して、本物の cargo で検査を走らせる。
# P1〜P4・D1〜D14・E1・E2・E5〜E7 は基準の workspace(中身は `place_inheriting_workspace`)に手を入れて組む。
# 多くは presentation の Cargo.toml を `replace_presentation` で置き直す。メンバーの manifest を直に書くのは P4・D8・D9・D14
# だけで、D12 は根の Cargo.toml を書き直して `crates/` の外にメンバーを足す。
# E3・E4 は根の Cargo.toml だけを置く(E3 は置かない)。1 ケースの判定の綴りと、それをどう照らすかは
# `cases-allowlist.sh` の `decision_of`。期待の違反の行(package の名前)は、このファイルに直に書く。
# 走らせ方の例外は 2 つ。D13 は根をカレントにして引数なしで呼ぶ(`run_in_root`)。E5 は presentation のディレクトリ名に
# タブを入れてから呼ぶ。E1〜E7 は、検査できなかった理由が標準エラーに出るかまで照らす
# (`cases-allowlist.sh` の `run_unavailable_case`)。
#
# 使い方: bash harness/githooks/lib/lints-inheritance-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
script="$here/lints-inheritance.sh"

source "$here/../../../.claude/hooks/lib/cases-report.sh"
source "$here/../../../.claude/hooks/lib/cases-fixtures.sh"
source "$here/cases-allowlist.sh"

work="$(make_crate_workdir)" || exit 1
trap 'rm -rf "$work"' EXIT

# CI は CARGO_TERM_COLOR=always を渡す。色が付くと cargo の標準エラーの行が `error:` で始まらず、照合が外れる。
export CARGO_TERM_COLOR=never

workspace="$work/ws"
presentation="$workspace/crates/presentation"

# 検査が違反を報告するときの見出し。
heading='^\[lints\] の下に workspace = true と書いていない crate があります'

# `[lints]` の下に `workspace = true` を持つメンバーの crate を置く。
#
# $1 crate のディレクトリ
# $2 パッケージ名
place_inheriting_member() {
  place_member "$1" "$2" || return 1
  printf '\n[lints]\nworkspace = true\n' >>"$1/Cargo.toml"
}

# 前のケースの workspace を消し、基準の workspace を置く。根は `members = ["crates/*"]` と `[workspace.lints.clippy]` を
# 持ち、メンバーの domain / infrastructure / presentation / tightrope はすべて `[lints]` の下に `workspace = true` を持つ。
place_inheriting_workspace() {
  local crate
  rm -rf "$workspace" || return 1
  mkdir -p "$workspace/crates" || return 1
  printf '[workspace]\nmembers = ["crates/*"]\nresolver = "3"\n\n[workspace.lints.clippy]\nunwrap_used = "deny"\n' \
    >"$workspace/Cargo.toml"
  for crate in domain infrastructure presentation tightrope; do
    place_inheriting_member "$workspace/crates/$crate" "$crate" || return 1
  done
}

# presentation を `[lints]` を持たない crate に置き直し、Cargo.toml の末尾に行を足す。足した行は `[dependencies]` の後に入る。
#
# $1 以降 足す行(省くと何も足さない)
replace_presentation() {
  place_member "$presentation" presentation || return 1
  [ "$#" -eq 0 ] && return 0
  printf '%s\n' "$@" >>"$presentation/Cargo.toml"
}

place_inheriting_workspace || exit 1
run_case pass '' 'P1 すべてのメンバーが [lints] の下に workspace = true を持てば通る' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '[ lints ]   # 継承する' $'workspace\t=  true  # 継承' || exit 1
run_case pass '' 'P2 見出しの括弧の内側・= の前後の空白とタブ、行末のコメントがあっても通る' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '[lints]' 'workspace = true' '' '[dev-dependencies]' || exit 1
run_case pass '' 'P3 [lints] の後に別の見出しが続いても通る' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation || exit 1
printf '\n[lints]\nworkspace = true' >>"$presentation/Cargo.toml"
run_case pass '' 'P4 manifest の末尾に改行が無くても通る' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation || exit 1
run_case deny 'presentation' 'D1 [lints] を持たないメンバーがあれば、その名前を出して落ちる' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation || exit 1
place_member "$workspace/crates/domain" domain || exit 1
run_case deny 'domain
presentation' 'D2 2 つのメンバーが持たなければ両方を出す' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '[lints]' || exit 1
run_case deny 'presentation' 'D3 空の [lints] は受けていない' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '[lints.clippy]' 'unwrap_used = "deny"' 'expect_used = "deny"' 'mod_module_files = "deny"' || exit 1
run_case deny 'presentation' \
  'D4 [lints.clippy] に workspace の lint を写しても、workspace = true が無ければ落ちる' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '[package.metadata.x]' 'workspace = true' || exit 1
run_case deny 'presentation' 'D5 workspace = true が別の表にあるだけなら落ちる' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '[lints]' '[package.metadata.x]' 'workspace = true' || exit 1
run_case deny 'presentation' 'D6 [lints] の後に別の見出しが来ると、その下の workspace = true は数えない' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '[lints]' '# workspace = true' || exit 1
run_case deny 'presentation' 'D7 コメントの # workspace = true は数えない' run_with_root "$workspace"

place_inheriting_workspace || exit 1
printf 'lints.workspace = true\n\n[package]\nname = "presentation"\nversion = "0.1.0"\nedition = "2024"\n' \
  >"$presentation/Cargo.toml"
run_case deny 'presentation' 'D8 点つきキー lints.workspace = true は読まない書き方として落とす' run_with_root "$workspace"

place_inheriting_workspace || exit 1
printf 'lints = { workspace = true }\n\n[package]\nname = "presentation"\nversion = "0.1.0"\nedition = "2024"\n' \
  >"$presentation/Cargo.toml"
run_case deny 'presentation' 'D9 インラインの表 lints = { workspace = true } も落とす' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '["lints"]' 'workspace = true' || exit 1
run_case deny 'presentation' 'D10 引用符つきの見出し ["lints"] も落とす' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '[lints]' '"workspace" = true' || exit 1
run_case deny 'presentation' 'D11 引用符つきのキー "workspace" = true も落とす' run_with_root "$workspace"

place_inheriting_workspace || exit 1
printf '[workspace]\nmembers = ["crates/*", "tools/x"]\nresolver = "3"\n\n[workspace.lints.clippy]\nunwrap_used = "deny"\n' \
  >"$workspace/Cargo.toml"
place_member "$workspace/tools/x" x || exit 1
run_case deny 'x' 'D12 crates/ の外のメンバー(tools/x)も照らす' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation || exit 1
run_case deny 'presentation' 'D13 引数なしで呼ぶとカレントディレクトリを根にする' run_in_root "$workspace"

place_inheriting_workspace || exit 1
printf '%s\r\n' '[package]' 'name = "presentation"' 'version = "0.1.0"' 'edition = "2024"' '' '[lints]' 'workspace = true' \
  >"$presentation/Cargo.toml"
run_case deny 'presentation' 'D14 改行が CRLF の manifest は、cargo が受けても落とす' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '[package.metadata.x]' 's = """' '[lints]' 'workspace = true' '"""' || exit 1
run_unavailable_case '3 重引用符
presentation' \
  'E1 """ の文字列があれば、中に [lints] と workspace = true があっても検査できない' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '[package.metadata.x]' "s = '''" '[lints]' 'workspace = true' "'''" || exit 1
run_unavailable_case '3 重引用符
presentation' "E2 ''' も同じ" run_with_root "$workspace"

rm -rf "$workspace" || exit 1
mkdir -p "$workspace" || exit 1
run_unavailable_case 'cargo metadata が落ちました
^error:' 'E3 根に Cargo.toml が無ければ検査できない' run_with_root "$workspace"

printf '[workspace]\nmembers = []\nresolver = "3"\n' >"$workspace/Cargo.toml"
run_unavailable_case 'メンバーが 1 つもありません' 'E4 メンバーが 0 件なら検査できない' run_with_root "$workspace"

place_inheriting_workspace || exit 1
mv "$presentation" "$workspace/crates/pre	sentation" || exit 1
run_unavailable_case 'presentation の Cargo\.toml.*を読めません' \
  'E5 メンバーのディレクトリ名にタブがあり Cargo.toml を読めなければ検査できない' run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '[lints]' 'workspace = true' '' '[lints.clippy]' 'unwrap_used = "allow"' || exit 1
run_unavailable_case 'cargo metadata が落ちました
cannot override' 'E6 workspace = true と [lints.clippy] の上書きを並べると、cargo metadata が落ちて検査できない' \
  run_with_root "$workspace"

place_inheriting_workspace || exit 1
replace_presentation '' '[lints]' 'clippy = {' '  workspace = true' '}' || exit 1
run_unavailable_case 'cargo metadata が落ちました
invalid type: boolean' 'E7 複数行のインラインの表の中の workspace = true は、cargo metadata が落ちて検査できない' \
  run_with_root "$workspace"

exit "$cases_failed"
