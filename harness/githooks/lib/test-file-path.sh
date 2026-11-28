# shellcheck shell=bash
#
# 単体テストのファイルか(`rules/testing.md`「段をまたぐテストと単体のテストを分ける」)を <根> からの相対パスで
# 決める awk の関数 `is_test_file_path(path)` と、<根> の下の `*.rs` を awk へ渡す走査 `awk_rs_files_under`。
# テストのファイルは、名前がちょうど `tests.rs` のファイルと、`tests/` の下。
#
# 使う側: test-placement.sh(テストを置いてよい場所)/ test-file-length.sh(行数を測る場所)/ folder-deps.sh と
# lint-level-attributes.sh と cargo-config-rustflags.sh(`test_file_path_awk` を丸ごと連結して渡し、呼ぶのは
# `relative_path_of` だけ)。どれも source する。cargo-config-rustflags.sh 以外は
# `awk_rs_files_under <根> <-v の引数> "$test_file_path_awk"'<プログラム>'` で走らせ、ファイルごとに何を見るかだけを書く。
# cargo-config-rustflags.sh は `*.rs` ではなく `.cargo/config*` を読むので、find を自前で持つ。
#
# Why(`is_test_file_path` の 1 つの一覧を test-placement.sh と test-file-length.sh の 2 つの検査で使い回す。
# `rules/coding.md`「同じ一覧を、安全な倒れ方が違う 2 箇所で使い回さない」から外れる): 一覧から漏れる向きは、
# 行数を測らない漏れでも置き場所の検査がその `#[test]` を落とすので止まる。
# 一覧を広げる向きは置き場所の検査を緩めるので、広げるときは置き場所の側で決める。

test_file_path_awk='
function relative_path_of(filename) {
  sub(/^\.\//, "", filename)
  return filename
}
function is_test_file_path(path) {
  return path ~ /(^|\/)tests\.rs$/ || path ~ /(^|\/)tests\//
}
'

# <根> の下の `*.rs` をすべて awk へ渡す。awk の FILENAME は `./` 始まりで、`relative_path_of(FILENAME)` が
# <根> からの相対パスにする。終了コードは走査(find と awk)のもの。
#
# Why(<根> へ移ってから相対パスで探す): 絶対パスで見ると、<根> の上に `tests/` があるだけで根の中の全部が
# テストのファイルになる。
# Why(`CDPATH=` で cd する): CDPATH が設定されていると、相対パスの cd が移動先を標準出力へ書き、走査の結果に混ざる。
#
# $1 <根>
# $2 以降 awk へ渡す引数(`-v` とプログラム)
awk_rs_files_under() {
  local root="$1"
  shift
  (CDPATH= cd -- "$root" && find . -type f -name '*.rs' -exec awk "$@" {} +)
}
