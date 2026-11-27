#!/usr/bin/env bash
#
# crate の依存の許可表の検査(`crate-deps.sh`)の判定表。
#
# ケースごとに使い捨ての workspace を組み直し(根は `$work/ws`)、根を引数に渡して、本物の cargo で検査を走らせる。
# P1・P2・D1〜D17・S1 は基準の workspace B(中身は `place_workspace_b`)に手を入れて組み、E1〜E3 は根の Cargo.toml
# だけを置く(E1 は置かない)。1 ケースの判定の綴りと、それをどう照らすかは `cases-allowlist.sh` の `decision_of`。
# 走らせ方の例外は 2 つ。D16 は根をカレントにして引数なしで呼ぶ。D17 は偽の cargo(`future_kind_cargo_path_prefix`)を
# PATH の先頭に置いて呼ぶ。
# R1・D18 も基準の workspace B に手を入れて組む。E4〜E6 は E1〜E3 と同じ根を置き、検査できなかった理由が
# 標準エラーに出るかまで照らす(`cases-allowlist.sh` の `run_unavailable_case`)。
#
# 使い方: bash harness/githooks/lib/crate-deps-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/crate-deps.sh"

source "$here/../../../.claude/hooks/lib/cases-report.sh"
source "$here/../../../.claude/hooks/lib/cases-fixtures.sh"
source "$here/cases-allowlist.sh"

work="$(make_crate_workdir)" || exit 1
trap 'rm -rf "$work"' EXIT

# CI は CARGO_TERM_COLOR=always を渡す。色が付くと cargo の標準エラーの行が `error:` で始まらず、照合が外れる。
export CARGO_TERM_COLOR=never

workspace="$work/ws"
outside="$work/outside"

# 検査が違反を報告するときの見出し。
heading='^crate の依存が許可表にありません'

# 前のケースの workspace と外の crate を消し、基準の workspace B を置く。
place_workspace_b() {
  rm -rf "$workspace" "$outside" || return 1
  mkdir -p "$workspace/crates" || return 1
  printf '[workspace]\nmembers = ["crates/*"]\nresolver = "3"\n' >"$workspace/Cargo.toml"
  place_member "$workspace/crates/domain" domain || return 1
  place_member "$workspace/crates/application" application \
    'domain = { path = "../domain" }' \
    'serde = "1"' || return 1
  place_member "$workspace/crates/infrastructure" infrastructure \
    'application = { path = "../application" }' \
    'toml = "1"' \
    'tree-sitter = "1"' \
    'tree-sitter-typescript = "1"' \
    'lsp-types = "1"' \
    'serde_json = "1"' || return 1
  place_member "$workspace/crates/presentation" presentation \
    'application = { path = "../application" }' \
    'clap = "1"' \
    'serde_json = "1"' || return 1
  place_member "$workspace/crates/tightrope" tightrope \
    'domain = { path = "../domain" }' \
    'application = { path = "../application" }' \
    'infrastructure = { path = "../infrastructure" }' \
    'presentation = { path = "../presentation" }' || return 1
}

# workspace の crate の Cargo.toml の末尾に行を足す。足した行は、その時点で最後にある節に入る。
#
# $1 crate の名前(`crates/` の下のディレクトリ名)
# $2 以降 足す行
append_to_member() {
  local name="$1"
  shift
  printf '%s\n' "$@" >>"$workspace/crates/$name/Cargo.toml"
}

# workspace の crate の Cargo.toml から、渡した綴りで始まる行を消す。
#
# $1 crate の名前
# $2 消す行の始まりの綴り
remove_from_member() {
  local manifest="$workspace/crates/$1/Cargo.toml"
  awk -v prefix="$2" 'index($0, prefix) != 1' "$manifest" >"$manifest.next"
  mv "$manifest.next" "$manifest"
}

# 本物の cargo の出力の `"kind":"build"` を `"kind":"future"` に置き換える偽の cargo を置き、PATH の先頭に足す値を出す。
# 終了コードは本物の cargo のもの(pipefail)。
#
# $1 置き場のディレクトリ(その下の `future-kind-bin/` に置く)
future_kind_cargo_path_prefix() {
  local dir="$1/future-kind-bin" real_cargo
  real_cargo="$(command -v cargo)" || return 1
  mkdir -p "$dir" || return 1
  printf '#!/usr/bin/env bash\nset -o pipefail\n%q "$@" | sed '\''s/"kind":"build"/"kind":"future"/g'\''\n' \
    "$real_cargo" >"$dir/cargo" || return 1
  chmod +x "$dir/cargo" || return 1
  printf '%s:' "$dir"
}

place_workspace_b || exit 1
run_case pass '' 'P1 許可表どおりの依存だけを持つ workspace は通る' run_with_root "$workspace"

place_workspace_b || exit 1
rm -rf "$workspace/crates/application" || exit 1
for member in infrastructure presentation tightrope; do
  remove_from_member "$member" 'application = ' || exit 1
done
run_case pass '' 'P2 表にあって workspace に無い crate があっても通る' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member infrastructure 'domain = { path = "../domain" }' || exit 1
run_case deny 'infrastructure: [dependencies] の domain(workspace の crate)' \
  'D1 infrastructure に domain を足すと落ちる' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member domain 'serde = "1"' || exit 1
run_case deny 'domain: [dependencies] の serde(外部 crate)' \
  'D2 domain に serde を足すと落ちる' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member tightrope 'clap = "1"' || exit 1
run_case deny 'tightrope: [dependencies] の clap(外部 crate)' \
  'D3 tightrope に clap を足すと落ちる(* は workspace の列だけ)' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member presentation 'domain = { path = "../domain" }' || exit 1
run_case deny 'presentation: [dependencies] の domain(workspace の crate)' \
  'D4 presentation は domain に依存できない' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member presentation 'toml = "1"' || exit 1
run_case deny 'presentation: [dependencies] の toml(外部 crate)' \
  'D5 presentation の外部の列は他の crate と混ざらない' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member domain '' '[dev-dependencies]' 'infrastructure = { path = "../infrastructure" }' || exit 1
run_case deny 'domain: [dev-dependencies] の infrastructure(workspace の crate)' \
  'D6 dev-dependencies も検査する' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member domain '' '[build-dependencies]' 'cc = "1"' || exit 1
run_case deny 'domain: [build-dependencies] の cc(外部 crate)' \
  'D7 build-dependencies も検査する' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member domain '' "[target.'cfg(unix)'.dependencies]" 'libc = "1"' || exit 1
run_case deny "domain: [target.'cfg(unix)'.dependencies] の libc(外部 crate)" \
  'D8 target 付きの依存も検査する' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member infrastructure 'tree-sitter-rust = { package = "serde", version = "1" }' || exit 1
run_case deny 'infrastructure: [dependencies] の serde(外部 crate)' \
  'D9 許可された名前の別名でも抜けられない' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member infrastructure 'tree-sitterx = "1"' || exit 1
run_case deny 'infrastructure: [dependencies] の tree-sitterx(外部 crate)' \
  'D10 tree-sitter-* は tree-sitterx を通さない' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member infrastructure 'toml_edit = "1"' || exit 1
run_case deny 'infrastructure: [dependencies] の toml_edit(外部 crate)' \
  'D11 toml は完全一致でしか通さない' run_with_root "$workspace"

place_workspace_b || exit 1
remove_from_member presentation 'application = ' || exit 1
append_to_member presentation 'application = "1"' || exit 1
run_case deny 'presentation: [dependencies] の application(外部 crate)' \
  'D12 crates.io の同名の crate は workspace の crate に数えない' run_with_root "$workspace"

place_workspace_b || exit 1
place_member "$outside" outside || exit 1
append_to_member tightrope 'outside = { path = "../../../outside" }' || exit 1
run_case deny 'tightrope: [dependencies] の outside(外部 crate)' \
  'D13 workspace の外を指す path 依存は外部 crate' run_with_root "$workspace"

place_workspace_b || exit 1
place_member "$workspace/crates/extra" extra || exit 1
append_to_member tightrope 'extra = { path = "../extra" }' || exit 1
run_case deny 'extra: 許可表に行が無い crate' \
  'D14 表に行が無いメンバーを落とす(tightrope → extra は * で通る)' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member domain 'serde = "1"' || exit 1
append_to_member presentation 'toml = "1"' || exit 1
run_case deny 'domain: [dependencies] の serde(外部 crate)
presentation: [dependencies] の toml(外部 crate)' \
  'D15 違反が 2 crate にあれば両方出す' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member domain 'serde = "1"' || exit 1
run_case deny 'domain: [dependencies] の serde(外部 crate)' \
  'D16 引数なしで呼ぶとカレントディレクトリを根として検査する' run_in_root "$workspace"

place_workspace_b || exit 1
append_to_member domain '' '[build-dependencies]' 'cc = "1"' || exit 1
future_kind_path_prefix="$(future_kind_cargo_path_prefix "$work")" || exit 1
run_case deny 'domain: [future] の cc(外部 crate)' \
  'D17 知らない kind は綴りをそのまま節にして出す' env PATH="$future_kind_path_prefix$PATH" bash "$script" "$workspace"

place_workspace_b || exit 1
append_to_member presentation '' '[target."cfg(x = \"a\tclap\nb\")".dependencies]' 'evil = "1"' || exit 1
run_case deny "presentation: [target.'cfg(x = \"a\\tclap\\nb\")'.dependencies] の evil(外部 crate)" \
  'S1 cfg の文字列にタブ・改行があっても、その依存を違反として出す' run_with_root "$workspace"

place_workspace_b || exit 1
append_to_member domain 'application = { path = "../application" }' || exit 1
append_to_member application 'infrastructure = { path = "../infrastructure" }' \
  'presentation = { path = "../presentation" }' || exit 1
append_to_member infrastructure 'presentation = { path = "../presentation" }' || exit 1
append_to_member presentation 'infrastructure = { path = "../infrastructure" }' || exit 1
run_case deny 'domain: [dependencies] の application(workspace の crate)
application: [dependencies] の infrastructure(workspace の crate)
application: [dependencies] の presentation(workspace の crate)
infrastructure: [dependencies] の presentation(workspace の crate)
presentation: [dependencies] の infrastructure(workspace の crate)' \
  'R1 層を逆に向く・横に向く workspace の依存をすべて出す' run_with_root "$workspace"

place_workspace_b || exit 1
place_member "$workspace/crates/extra" extra 'serde = "1"' || exit 1
run_case deny 'extra: 許可表に行が無い crate' \
  'D18 表に行が無いメンバーの依存は照らさず、行が無いことの 1 行だけ出す' run_with_root "$workspace"

rm -rf "$workspace" "$outside" || exit 1
mkdir -p "$workspace" || exit 1
run_case unavailable '' 'E1 根に Cargo.toml が無ければ検査できない' run_with_root "$workspace"

printf '[workspace\n' >"$workspace/Cargo.toml"
run_case unavailable '' 'E2 根の Cargo.toml が TOML として壊れていれば検査できない' run_with_root "$workspace"

printf '[workspace]\nmembers = []\nresolver = "3"\n' >"$workspace/Cargo.toml"
run_case unavailable '' 'E3 メンバー 0 件なら検査できない' run_with_root "$workspace"

rm -f "$workspace/Cargo.toml" || exit 1
run_unavailable_case 'cargo metadata が落ちました
^error:' 'E4 根に Cargo.toml が無ければ、cargo metadata が落ちたことと cargo の error: を標準エラーに出す' \
  run_with_root "$workspace"

printf '[workspace\n' >"$workspace/Cargo.toml"
run_unavailable_case 'cargo metadata が落ちました
^error:' 'E5 根の Cargo.toml が壊れていれば、cargo metadata が落ちたことと cargo の error: を標準エラーに出す' \
  run_with_root "$workspace"

printf '[workspace]\nmembers = []\nresolver = "3"\n' >"$workspace/Cargo.toml"
run_unavailable_case 'メンバーが 1 つもありません' \
  'E6 メンバー 0 件なら、メンバーが 1 つも無いことを標準エラーに出す' run_with_root "$workspace"

exit "$cases_failed"
