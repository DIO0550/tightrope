# shellcheck shell=bash
#
# crate の src のディレクトリを根に 1 つだけ受け取る検査が、受け取った引数から根を決める関数 `crate_src_root_of`。
#
# 使う側: test-placement.sh / test-file-length.sh。どれも source したうえで
# `root="$(crate_src_root_of <検査の名前> "$@")" || exit 2` で根を受け取り、<根> がディレクトリかは自分で見る。

# 引数がちょうど 1 つで空でなければ、それを根として標準出力へ出して 0 を返す。
# 0 個・2 個以上なら受け取った根の数を、空なら空だったことを、何を渡すかと合わせて
# `<検査の名前>: ` から始めて標準エラーへ出し、2 を返す。
#
# $1   検査の名前(標準エラーの行の接頭辞)
# $2.. 検査が受け取った引数
crate_src_root_of() {
  local check_name="$1"
  shift
  local root_usage='根に crate の src のディレクトリ(crates/<crate>/src)を 1 つ渡してください'
  if [ "$#" -ne 1 ]; then
    printf '%s: %s（受け取った根の数: %s）\n' "$check_name" "$root_usage" "$#" >&2
    return 2
  fi
  if [ -z "$1" ]; then
    printf '%s: %s（受け取った根: 空）\n' "$check_name" "$root_usage" >&2
    return 2
  fi
  printf '%s' "$1"
}
