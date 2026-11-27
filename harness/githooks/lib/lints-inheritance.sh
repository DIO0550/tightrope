#!/usr/bin/env bash
#
# workspace のメンバーの crate が、根の `[workspace.lints]` を `[lints]` の下の `workspace = true` で受けているかの検査。
#
# 使い方: bash harness/githooks/lib/lints-inheritance.sh [<workspace の根>]   (<workspace の根> の既定は .)
# 受けていない crate が無ければ何も出さずに exit 0。
# あれば、見出しの下に受けていない crate の package の名前を 1 行ずつ出して exit 1。
#
# メンバーは `<workspace の根>/Cargo.toml` を渡した `cargo metadata --no-deps` で数え(`crates/` の外のメンバーも
# 照らす)、各メンバーの Cargo.toml を 1 行ずつ読む。
#
# 「受けている」と読む書き方は 1 つだけ。見出しの行 `[lints]` の後、次の見出しの行(行頭の空白の後が `[` の行)までに
# `workspace = true` の行があること。見出しの行は行頭・括弧の内側・`]` の後に、`workspace = true` の行は行頭・
# `=` の前後・行末に空白かタブがあってよく、どちらの行も行末に `#` からのコメントがあってよい。
#
# それ以外の書き方は、cargo が受けても「受けていない」と読んで落とす(読み方の漏れを落とす側に倒す)。
# - 点つきキー(`lints.workspace = true`)・インラインの表(`lints = { workspace = true }`)
# - 引用符つきの見出し(`["lints"]`)・引用符つきのキー(`"workspace" = true`)
# - 改行が CRLF の行
#
# 検査できなかったとき(jq が無い / cargo の標準エラーを受ける一時ファイルを作れない / cargo metadata が落ちた /
# jq が cargo metadata の出力を読めない / workspace のメンバーが 0 件 / メンバーの Cargo.toml を読めない /
# メンバーの Cargo.toml に 3 重引用符(`"""` / `'''`)がある / 隣の workspace-metadata.sh を読み込めない)は、
# 理由を標準エラーへ出して exit 2。3 重引用符の文字列は複数の行にまたがり、中の行を見出しやキーと
# 区別して読めないので、受けているとも受けていないとも言わない。
# 複数行のインラインの表の中の `workspace = true` は「受けている」と読んでしまうが、cargo が
# `invalid type: boolean` で落とすので、cargo metadata が落ちたとして exit 2 になる。
#
# cargo の標準エラーは、cargo が落ちたときだけ出す。
#
# macOS の /bin/bash(3.2)でも走るよう、連想配列など bash 4 以降の機能は使わない。

set -uo pipefail

here="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$here/workspace-metadata.sh" || {
  echo 'lints-inheritance: 隣の workspace-metadata.sh を読み込めません' >&2
  exit 2
}

root="${1:-.}"

heading='[lints] の下に workspace = true と書いていない crate があります(読む書き方は harness/githooks/lib/lints-inheritance.sh の冒頭)'

# 空白とタブ。`[[:space:]]` は CR にも当たり CRLF の行を通すので使わない。
blank=$'[ \t]*'
# 行末のコメント。CR を含む行には当たらない。
comment=$'(#[^\r]*)?'
header_pattern="^${blank}\\["
lints_header_pattern="^${blank}\\[${blank}lints${blank}\\]${blank}${comment}\$"
inheriting_line_pattern="^${blank}workspace${blank}=${blank}true${blank}${comment}\$"
multiline_string_pattern="(\"\"\"|''')"

# Cargo.toml が `[lints]` の下の `workspace = true` で受けているかを、`inherits`(受けている)/ `missing`(受けていない)/
# `multiline`(3 重引用符があり読めない)で出す。
#
# $1 Cargo.toml のパス
inheritance_of() {
  local line table=other inherited=no
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ $multiline_string_pattern ]]; then
      echo multiline
      return 0
    fi
    if [[ "$line" =~ $lints_header_pattern ]]; then
      table=lints
      continue
    fi
    if [[ "$line" =~ $header_pattern ]]; then
      table=other
      continue
    fi
    [ "$table" = lints ] || continue
    [[ "$line" =~ $inheriting_line_pattern ]] && inherited=yes
  done <"$1"

  if [ "$inherited" = yes ]; then
    echo inherits
    return 0
  fi
  echo missing
}

metadata="$(workspace_metadata_of "$root" lints-inheritance)" || exit 2

# 1 行 1 件で、`@tsv` でエスケープした `<package の名前><TAB><Cargo.toml のパス>` の行を出す。
member_lines="$(jq -r "$workspace_member_packages_def"'
  workspace_member_packages[] | [.name, .manifest_path] | @tsv
' <<<"$metadata")"
jq_status=$?
if [ "$jq_status" -ne 0 ]; then
  printf 'lints-inheritance: jq が %s/Cargo.toml の cargo metadata の出力を読めません(終了コード %s)\n' "$root" "$jq_status" >&2
  exit 2
fi

if [ -z "$member_lines" ]; then
  printf 'lints-inheritance: %s/Cargo.toml の workspace にメンバーが 1 つもありません\n' "$root" >&2
  exit 2
fi

missing=()
while IFS=$'\t' read -r name manifest; do
  manifest_readable=no
  [ -f "$manifest" ] && [ -r "$manifest" ] && manifest_readable=yes
  if [ "$manifest_readable" = no ]; then
    printf 'lints-inheritance: %s の Cargo.toml(%s)を読めません\n' "$name" "$manifest" >&2
    exit 2
  fi

  # 知らない答えは「受けていない」へ倒す。
  case "$(inheritance_of "$manifest")" in
    inherits) continue ;;
    multiline)
      printf 'lints-inheritance: %s の Cargo.toml(%s)に 3 重引用符の文字列があり、行で読めません\n' "$name" "$manifest" >&2
      exit 2
      ;;
  esac
  missing+=("$name")
done <<<"$member_lines"

if [ "${#missing[@]}" -eq 0 ]; then
  exit 0
fi

echo "$heading"
printf '%s\n' "${missing[@]}"
exit 1
