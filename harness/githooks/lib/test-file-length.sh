#!/usr/bin/env bash
#
# 単体テストのファイルが読めないほど大きくなっていないかの検査
# (`rules/testing.md`「段をまたぐテストと単体のテストを分ける」)。
#
# 使い方: bash harness/githooks/lib/test-file-length.sh [<根>]   (<根> の既定は src)
# 上限の行数を超えたテストのファイルを見出しの下に `<根>/<相対パス>: <行数> 行` で並べて exit 1。
# 無ければ何も出さずに exit 0。<根> がディレクトリでない・走査に失敗した・共有の一覧が読めないときは exit 2。
#
# 測るのは `test-file-path.sh` の一覧に当たる `*.rs`(test-placement.sh と共有)。行数は物理行で数え、
# 末尾に改行の無い最後の行も 1 行、0 バイトのファイルは 0 行とする。上限は引数・環境変数で変えさせない。

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$here/test-file-path.sh" || exit 2

# 1 つのテストの観点は収まり、観点を 2 つ以上抱えたファイルは超える行数。開いていた PR のテストは、
# 観点ごとに分けた見積もりが最大 83 行、分けていないものが 110・140 行だった。
max_lines=100

root="${1:-src}"
if [ ! -d "$root" ]; then
  printf 'test-file-length: %s はディレクトリではありません\n' "$root" >&2
  exit 2
fi

# <根> からの相対パスで見る。絶対パスのまま見ると、<根> の上に `tests/` があるだけで根の中の全部を測る。
over="$(cd "$root" && find . -type f -name '*.rs' -exec awk -v root="${root%/}" -v max="$max_lines" "$test_file_path_awk"'
  FNR == 1 {
    path = FILENAME
    sub(/^\.\//, "", path)
    measured = is_test_file_path(path)
  }
  measured { lines[path] = FNR }
  END {
    for (p in lines) {
      if (lines[p] > max) print root "/" p ": " lines[p] " 行"
    }
  }
' {} +)"
scan_status=$?

if [ "$scan_status" -ne 0 ]; then
  printf 'test-file-length: %s の走査に失敗しました(終了コード %s)\n' "$root" "$scan_status" >&2
  exit 2
fi

if [ -z "$over" ]; then
  exit 0
fi

printf 'テストのファイルが %s 行を超えています(%s の下)。`<名前>/tests.rs` には `mod <観点>;` だけを置いて、テストを `<名前>/tests/<観点>.rs` へテストの観点ごとに分けてください。1 つの観点だけで超えるなら、その観点をさらに細かい観点に分けます(共有するヘルパーは `tests/<名前>.rs` に `pub(super)` で置けます):\n' "$max_lines" "$root"
printf '%s\n' "$over" | LC_ALL=C sort
exit 1
