#!/usr/bin/env bash
#
# workspace を cargo metadata で読む検査(`crate-deps.sh` / `lints-inheritance.sh`)が共有する、cargo metadata の
# 出力の取り方と、そこから workspace のメンバーを jq で読む手順。source して使う。
#
# どちらの関数も、検査できなかったとき(理由は関数ごとの doc)は `<理由の頭>: <理由>` を標準エラーへ出し、
# 標準出力へは何も出さずに 2 を返す。呼ぶ検査は、これを受けて exit 2 で終える。
#
# macOS の /bin/bash(3.2)でも走るよう、連想配列など bash 4 以降の機能は使わない。

# jq の定義 `workspace_member_packages`。cargo metadata の出力から、workspace のメンバーの package を配列で返す。
# `workspace_member_lines_of` が、渡されたフィルタの頭に付ける。
workspace_member_packages_def='def workspace_member_packages:
  .workspace_members as $ids
  | [.packages[] | select(.id as $id | any($ids[]; . == $id))];'

# `<workspace の根>/Cargo.toml` を渡した `cargo metadata --no-deps` の出力を、標準出力へ出す。
# cargo の標準エラーは、cargo が落ちたときだけ出す。
# 検査できなかったとき: jq が無い / cargo の標準エラーを受ける一時ファイルを作れない / cargo metadata が落ちた。
#
# $1 workspace の根
# $2 理由の頭(呼ぶ検査の名前)
cargo_metadata_of() {
  local root="$1" prefix="$2" cargo_errors metadata cargo_status
  if ! command -v jq >/dev/null 2>&1; then
    echo "$prefix: jq が無いので検査できません" >&2
    return 2
  fi

  cargo_errors="$(mktemp)" || {
    echo "$prefix: cargo の標準エラーを受ける一時ファイルを作れません" >&2
    return 2
  }

  metadata="$(cargo metadata --no-deps --format-version 1 --locked --offline \
    --manifest-path "$root/Cargo.toml" 2>"$cargo_errors")"
  cargo_status=$?
  if [ "$cargo_status" -ne 0 ]; then
    printf '%s: %s/Cargo.toml の cargo metadata が落ちました(終了コード %s)\n' "$prefix" "$root" "$cargo_status" >&2
    cat "$cargo_errors" >&2
    rm -f "$cargo_errors"
    return 2
  fi

  rm -f "$cargo_errors"
  printf '%s\n' "$metadata"
}

# 標準入力の cargo metadata の出力に、頭に `workspace_member_packages` の定義を付けたフィルタを `jq -r` で掛け、
# その出力を標準出力へ出す。出力が空ならメンバーが 0 件と読むので、フィルタはメンバーごとに 1 行以上出すものを渡す。
# 検査できなかったとき: jq が cargo metadata の出力を読めない / workspace のメンバーが 0 件(jq の出力が空)。
#
# $1 workspace の根(理由に出す)
# $2 理由の頭(呼ぶ検査の名前)
# $3 jq のフィルタ(`workspace_member_packages` を使ってよい)
workspace_member_lines_of() {
  local root="$1" prefix="$2" filter="$3" lines jq_status
  lines="$(jq -r "$workspace_member_packages_def$filter")"
  jq_status=$?
  if [ "$jq_status" -ne 0 ]; then
    printf '%s: jq が %s/Cargo.toml の cargo metadata の出力を読めません(終了コード %s)\n' "$prefix" "$root" "$jq_status" >&2
    return 2
  fi

  if [ -z "$lines" ]; then
    printf '%s: %s/Cargo.toml の workspace にメンバーが 1 つもありません\n' "$prefix" "$root" >&2
    return 2
  fi

  printf '%s\n' "$lines"
}
