# shellcheck shell=bash
#
# 単体テストのファイルか(`rules/testing.md`「段をまたぐテストと単体のテストを分ける」)を、<根> からの
# 相対パスで決める awk の関数 `is_test_file_path(path)`。名前がちょうど `tests.rs` のファイルと、`tests/` の下。
#
# 使う側: test-placement.sh(テストを置いてよい場所)/ test-file-length.sh(行数を測る場所)。
# どちらも source したうえで、awk のプログラムの前に `"$test_file_path_awk"` を置いて呼ぶ。
#
# Why(2 つの検査で 1 つの一覧を共有する): 一覧から漏れた置き場所に `#[test]` を書くと test-placement.sh が
# 落とすので、2 つの検査を組で見ると、行数を測らない漏れは素通りではなく置き場所の違反として止まる。

test_file_path_awk='
function is_test_file_path(path) {
  return path ~ /(^|\/)tests\.rs$/ || path ~ /(^|\/)tests\//
}
'
