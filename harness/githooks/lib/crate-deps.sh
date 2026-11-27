#!/usr/bin/env bash
#
# workspace の crate が、許可表(下の `allowed_dependencies`)に無い依存を持っていないかの検査。
#
# 使い方: bash harness/githooks/lib/crate-deps.sh [<workspace の根>]   (<workspace の根> の既定は .)
# 違反が無ければ何も出さずに exit 0。
# 違反があれば、見出しの下に違反の行をすべて出して exit 1。違反の行は次の 2 つの形。
#   <crate>: [<節>] の <依存>(workspace の crate)   または   (外部 crate)
#   <crate>: 許可表に行が無い crate
# 検査できなかったとき(cargo metadata からメンバーを読めない(理由は隣の cargo-metadata.sh の冒頭と関数の doc) /
# jq の出力に知らない行の種類か分類がある / 隣の cargo-metadata.sh を読み込めない)は、理由を標準エラーへ出して
# exit 2。
#
# 読むのは `<workspace の根>/Cargo.toml` を渡した `cargo metadata --no-deps` の出力。
# - メンバーごとに、依存の種類(dependencies / dev-dependencies / build-dependencies、target 付きのもの)を
#   問わずすべての依存を照らす
# - 依存はパッケージ名で照らし、別名(`package = ...` で付けた名前)では照らさない
# - `path` がどれかのメンバーのディレクトリと一致する依存だけを workspace の crate とし、それ以外はすべて
#   外部 crate とする。外部 crate は名前だけで照らし、取得元は見ない
# - 許可表に行が無いメンバーは、その依存を照らさずに 1 行で落とす。許可表にあって workspace に無い crate では
#   落とさない
# - 節は依存の種類の綴り。cargo の知らない種類はその綴りのまま出す。target 付きなら頭に `target.'<cfg>'.` を付ける
# - crate・節・依存の名前にタブ・改行・バックスラッシュがあれば、jq の `@tsv` がエスケープした綴り
#   (`\t` / `\n` / `\\`)のまま出す(例: cfg にタブがある節は `target.'cfg(x = "a\tb")'.dependencies`)
#
# macOS の /bin/bash(3.2)でも走るよう、連想配列など bash 4 以降の機能は使わない。

set -uo pipefail

here="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$here/cargo-metadata.sh" || {
  echo 'crate-deps: 隣の cargo-metadata.sh を読み込めません' >&2
  exit 2
}

root="${1:-.}"

# 許可表の crate・workspace の crate の列・外部 crate の列(同じ添字が同じ行)。
table_crates=()
allowed_workspace_columns=()
allowed_external_columns=()

# 許可表。1 行 `<crate>|<依存してよい workspace の crate>|<依存してよい外部 crate>`。列は空白区切りの
# シェルのパターン(使うのは `*` だけ)で、空の列はその側の依存を 1 つも許さない。
while IFS='|' read -r crate workspace_column external_column; do
  table_crates+=("$crate")
  allowed_workspace_columns+=("$workspace_column")
  allowed_external_columns+=("$external_column")
done <<'allowed_dependencies'
domain||
application|domain|serde
infrastructure|application|toml tree-sitter tree-sitter-* lsp-types serde_json
presentation|application|clap serde_json
tightrope|*|
allowed_dependencies

heading='crate の依存が許可表にありません(許可表は harness/githooks/lib/crate-deps.sh の allowed_dependencies)'

# 許可表でその crate の行の添字を出す。行が無ければ何も出さずに 1 を返す。
#
# $1 crate の名前
row_of() {
  local index
  for index in "${!table_crates[@]}"; do
    if [ "${table_crates[$index]}" = "$1" ]; then
      echo "$index"
      return 0
    fi
  done
  return 1
}

# 名前が、列に並ぶパターンのどれかに当たるか。
#
# $1 依存の名前
# $2 許可表の列
matches_column() {
  local name="$1" pattern patterns=()
  read -r -a patterns <<<"$2"
  for pattern in ${patterns[@]+"${patterns[@]}"}; do
    case "$name" in
      $pattern) return 0 ;;
    esac
  done
  return 1
}

# jq の出力を読めなかったことを標準エラーへ出し、exit 2 で終える。
#
# $1 読めなかったものの説明
exit_unreadable_line() {
  printf 'crate-deps: %s/Cargo.toml の cargo metadata から作った行に%s\n' "$root" "$1" >&2
  exit 2
}

metadata="$(cargo_metadata_of "$root" crate-deps)" || exit 2

# 1 行 1 件で、`@tsv` でエスケープした TAB 区切りの行を出す。メンバーは `member<TAB><crate>`、依存は
# `dependency<TAB><crate><TAB><節><TAB><依存の名前><TAB>workspace|external`。依存の行は、その crate の
# メンバーの行の後に並ぶ。メンバーごとに 1 行出すので、メンバーが 0 件のときだけ出力が空になる。
metadata_lines="$(workspace_member_lines_of "$root" crate-deps '
  workspace_member_packages as $members
  | ($members | map(.manifest_path | sub("/[^/]*$"; ""))) as $member_dirs
  | $members[]
  | .name as $crate
  | (["member", $crate] | @tsv),
    (.dependencies[]
      | (if .kind == null then "dependencies"
         elif .kind == "dev" then "dev-dependencies"
         elif .kind == "build" then "build-dependencies"
         else "\(.kind)" end) as $kind
      | (if .target == null then $kind else "target.'"'"'\(.target)'"'"'.\($kind)" end) as $section
      | .path as $path
      | (if any($member_dirs[]; . == $path) then "workspace" else "external" end) as $class
      | (["dependency", $crate, $section, .name, $class] | @tsv))
' <<<"$metadata")" || exit 2

# 今読んでいるメンバーの許可表の行の添字。許可表に行が無いメンバーでは空。
current_row=''
violations=()
while IFS=$'\t' read -r line_kind crate section dependency class; do
  case "$line_kind" in
    member)
      current_row="$(row_of "$crate")" || violations+=("$crate: 許可表に行が無い crate")
      continue
      ;;
    dependency) ;;
    *) exit_unreadable_line "知らない行の種類 '$line_kind' があります" ;;
  esac

  # 分類から、照らす許可表の列と違反の行の語を決める。許可表に行が無いメンバーでは列を引かない。
  case "$class" in
    workspace)
      allowed_column="${current_row:+${allowed_workspace_columns[$current_row]}}"
      class_label='workspace の crate'
      ;;
    external)
      allowed_column="${current_row:+${allowed_external_columns[$current_row]}}"
      class_label='外部 crate'
      ;;
    *) exit_unreadable_line "知らない分類 '$class' があります" ;;
  esac
  [ -n "$current_row" ] || continue

  matches_column "$dependency" "$allowed_column" && continue
  violations+=("$crate: [$section] の $dependency($class_label)")
done <<<"$metadata_lines"

if [ "${#violations[@]}" -eq 0 ]; then
  exit 0
fi

echo "$heading"
printf '%s\n' "${violations[@]}"
exit 1
