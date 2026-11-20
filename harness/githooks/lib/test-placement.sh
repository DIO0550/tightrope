#!/usr/bin/env bash
#
# 単体テストが実装と同じファイルに書かれていないかの検査
# (`rules/testing.md`「段をまたぐテストと単体のテストを分ける」)。
#
# 使い方: bash harness/githooks/lib/test-placement.sh [<根>]   (<根> の既定は src)
# 置き場所を外れたテストを見出しの下に `<ファイル>:<行>: <行の中身>` で並べて exit 1。
# 無ければ何も出さずに exit 0。<根> がディレクトリでなければ exit 2。
#
# テストを置いてよい場所を許可リスト(名前がちょうど `tests.rs` のファイルと、`tests/` の下)で書く。
# 一覧に無い置き場所は「外れた」側へ倒れるので、漏れは見落としではなく誤検知になる。
# 拾う印は `#[test]` と `mod tests {`。テストの関数を 1 つでも持つ同じファイルのテストは `#[test]` で拾える。

set -uo pipefail

root="${1:-src}"
if [ ! -d "$root" ]; then
  printf 'test-placement: %s はディレクトリではありません\n' "$root" >&2
  exit 2
fi

# <根> からの相対パスで見る。絶対パスのまま見ると、<根> の上に `tests/` があるだけで全部が許される。
misplaced="$(cd "$root" && grep -rnE --include='*.rs' '#\[test\]|mod tests[[:space:]]*\{' . |
  awk -F: -v root="${root%/}" '{ path = $1; sub(/^\.\//, "", path) }
    path ~ /(^|\/)tests\.rs$/ || path ~ /(^|\/)tests\// { next }
    { print root "/" path ":" substr($0, length($1) + 2) }')"

if [ -z "$misplaced" ]; then
  exit 0
fi

printf 'テストが実装と同じファイルにあります(%s の下)。`<名前>.rs` には `#[cfg(test)] mod tests;` だけを置き、テストは `tests.rs` へ移してください:\n' "$root"
printf '%s\n' "$misplaced"
exit 1
