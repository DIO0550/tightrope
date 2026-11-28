#!/usr/bin/env bash
#
# 単体テストが実装と同じファイルに書かれていないかの検査
# (`rules/testing.md`「段をまたぐテストと単体のテストを分ける」)。
#
# 使い方: bash harness/githooks/lib/test-placement.sh <根>   (<根> は crate の src のディレクトリ)
# 置き場所を外れたテストを見出しの下に `<ファイル>:<行>: <行の中身>` で並べて exit 1。
# 無ければ何も出さずに exit 0。<根> を 1 つ渡していない(0 個・2 個以上)・<根> が空・<根> がディレクトリでない・
# 走査に失敗した・共有のファイル(test-file-path.sh・crate-src-root.sh)が読めないときは、理由を
# `test-placement: <理由>` で標準エラーへ出して exit 2。
#
# テストを置いてよい場所の許可リストは `test-file-path.sh` が持ち、`test-file-length.sh` と共有する。
# 一覧に無い置き場所は「外れた」側へ倒れる。
#
# 拾うのは、行頭(字下げは除く)のテストの属性(`#[test]` / `#[tokio::test]` のような道のついたもの /
# `#[cfg_attr(test, test)]`)と、`#[cfg(test)]` の直後に中身ごと書いたモジュール(`mod x {`)。
# 行頭に限るのは、doc コメントの例や文字列の中の `#[test]` を拾わないため。

set -uo pipefail

check_name=test-placement

# 検査できなかった理由を標準エラーへ出し、exit 2 で終える。
#
# $1 理由
exit_unavailable() {
  printf '%s: %s\n' "$check_name" "$1" >&2
  exit 2
}

here="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/test-file-path.sh" || exit_unavailable "$here/test-file-path.sh を読み込めません"
. "$here/crate-src-root.sh" || exit_unavailable "$here/crate-src-root.sh を読み込めません"

root="$(crate_src_root_of "$check_name" "$@")" || exit 2
if [ ! -d "$root" ]; then
  exit_unavailable "$root はディレクトリではありません"
fi

# `#[cfg(test)]` の後の空行・コメント・他の属性は読み飛ばし、それ以外の行が来たら直前の `#[cfg(test)]` を忘れる。
misplaced="$(awk_rs_files_under "$root" -v root="${root%/}" "$test_file_path_awk"'
  FNR == 1 {
    cfg_test = 0
    path = relative_path_of(FILENAME)
    allowed = is_test_file_path(path)
  }
  allowed { next }
  /^[[:space:]]*#\[(cfg_attr\(test,[[:space:]]*)?([[:alnum:]_]+::)*test\)?\]/ {
    print root "/" path ":" FNR ": " $0
    cfg_test = 0
    next
  }
  /^[[:space:]]*#\[cfg\(test\)\][[:space:]]*$/ { cfg_test = 1; next }
  cfg_test && /^[[:space:]]*(pub(\([^)]*\))?[[:space:]]+)?mod[[:space:]]+[[:alnum:]_]+[[:space:]]*\{/ {
    print root "/" path ":" FNR ": " $0
    cfg_test = 0
    next
  }
  /^[[:space:]]*(#\[|\/\/|$)/ { next }
  { cfg_test = 0 }
')"
scan_status=$?

if [ "$scan_status" -ne 0 ]; then
  exit_unavailable "$root の走査に失敗しました(終了コード $scan_status)"
fi

if [ -z "$misplaced" ]; then
  exit 0
fi

printf 'テストが実装と同じファイルにあります(%s の下)。`<名前>.rs` には `#[cfg(test)] mod tests;` だけを置き、テストは `tests.rs` へ移してください:\n' "$root"
printf '%s\n' "$misplaced"
exit 1
