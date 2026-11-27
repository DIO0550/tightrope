#!/usr/bin/env bash
#
# workspace を cargo metadata で読む検査(`crate-deps.sh` / `lints-inheritance.sh`)が共有する、cargo metadata の
# 出力の取り方と、そこから workspace のメンバーの package を取り出す jq の定義。source して使う。
#
# macOS の /bin/bash(3.2)でも走るよう、連想配列など bash 4 以降の機能は使わない。

# jq の定義 `workspace_member_packages`。cargo metadata の出力から、workspace のメンバーの package を配列で返す。
# jq のフィルタの頭に付けて使う(例: `jq -r "$workspace_member_packages_def"' workspace_member_packages[] | .name'`)。
workspace_member_packages_def='def workspace_member_packages:
  .workspace_members as $ids
  | [.packages[] | select(.id as $id | any($ids[]; . == $id))];'

# `<workspace の根>/Cargo.toml` を渡した `cargo metadata --no-deps` の出力を、標準出力へ出す。
# cargo の標準エラーは、cargo が落ちたときだけ出す。
# 検査できなかったとき(jq が無い / cargo の標準エラーを受ける一時ファイルを作れない / cargo metadata が落ちた)は、
# `<理由の頭>: <理由>` を標準エラーへ出し、標準出力へは何も出さずに 2 を返す。
#
# $1 workspace の根
# $2 理由の頭(呼ぶ検査の名前)
workspace_metadata_of() {
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
