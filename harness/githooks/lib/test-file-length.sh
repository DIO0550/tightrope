#!/usr/bin/env bash
#
# 単体テストのファイルが読めないほど大きくなっていないかの検査
# (`rules/testing.md`「段をまたぐテストと単体のテストを分ける」)。
#
# 使い方: bash harness/githooks/lib/test-file-length.sh <根>   (<根> は crate の src のディレクトリ)
# 上限の行数を超えたテストのファイルを見出しの下に `<根>/<相対パス>: <行数> 行` で並べて exit 1。
# 無ければ何も出さずに exit 0。<根> を 1 つだけ渡していない(0 個・2 個以上・空)・<根> がディレクトリでない・走査に失敗した・共有の一覧が読めないときは exit 2。
#
# 測るのは `test-file-path.sh` の一覧に当たる `*.rs`(test-placement.sh と共有)。行数は物理行で数え、
# 末尾に改行の無い最後の行も 1 行、0 バイトのファイルは 0 行とする。上限は引数・環境変数で変えさせない。

set -uo pipefail

here="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/test-file-path.sh" || exit 2

# 1 つのテストの観点を読み切れる量。テストの観点の数そのものはレビューが見る。
max_lines=100

root_request='根に crate の src のディレクトリ(crates/<crate>/src)を 1 つ渡してください'
if [ "$#" -ne 1 ]; then
  printf 'test-file-length: %s（受け取った根の数: %s）\n' "$root_request" "$#" >&2
  exit 2
fi
root="$1"
if [ -z "$root" ]; then
  printf 'test-file-length: %s（受け取った根: 空）\n' "$root_request" >&2
  exit 2
fi
if [ ! -d "$root" ]; then
  printf 'test-file-length: %s はディレクトリではありません\n' "$root" >&2
  exit 2
fi

over="$(awk_rs_files_under "$root" -v root="${root%/}" -v max="$max_lines" "$test_file_path_awk"'
  FNR == 1 {
    path = relative_path_of(FILENAME)
    measured = is_test_file_path(path)
  }
  measured { lines[path] = FNR }
  END {
    for (p in lines) {
      if (lines[p] > max) print root "/" p ": " lines[p] " 行"
    }
  }
')"
scan_status=$?

if [ "$scan_status" -ne 0 ]; then
  printf 'test-file-length: %s の走査に失敗しました(終了コード %s)\n' "$root" "$scan_status" >&2
  exit 2
fi

if [ -z "$over" ]; then
  exit 0
fi

printf 'テストのファイルが %s 行を超えています(%s の下)。`<名前>/tests.rs` には `mod <観点>;` だけを置いて、テストを `<名前>/tests/<観点>.rs` へテストの観点ごとに分けてください。1 つのテストの観点だけで超えるなら、そのテストの観点をさらに細かく分けるか、長い入力をクレート直下の `tests/fixtures/` へ出して読みます(assert を含む、テストに依存するヘルパーを共有するなら `<名前>/tests/<ヘルパー>.rs` に `pub(super)` で置けます):\n' "$max_lines" "$root"
printf '%s\n' "$over" | LC_ALL=C sort
exit 1
