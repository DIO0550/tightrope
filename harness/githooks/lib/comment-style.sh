#!/usr/bin/env bash
#
# Rust のコメントが doc だけになっているかの検査(`rules/coding.md`「コメントは doc だけにする」)。
#
# 使い方: bash harness/githooks/lib/comment-style.sh <根>...
# 外れた行を見出しの下に `<ファイル>:<行>: <行の中身>` で並べて exit 1。
# 無ければ何も出さずに exit 0。<根> を 1 つも渡さない・<根> がディレクトリでない・走査に失敗したときは、理由を
# `comment-style: <理由>` で標準エラーへ出して exit 2。
#
# 拾うのは 2 つ。行頭(字下げは除く)の通常のコメント `//`(`///` と `//!` は除く)と、
# `Why:` / `Why not:` / `Why not（..）:` で始まる doc の行。
# `<根>` の下の `fixtures/` は解析対象のサンプルなので見ない。

set -uo pipefail

if [ "$#" -eq 0 ]; then
  printf 'comment-style: 根に検査するディレクトリ(crates など)を 1 つ以上渡してください（受け取った根の数: 0）\n' >&2
  exit 2
fi

for root in "$@"; do
  if [ ! -d "$root" ]; then
    printf 'comment-style: %s はディレクトリではありません\n' "$root" >&2
    exit 2
  fi
done

found=""
for root in "$@"; do
  lines="$(find "${root%/}" -path '*/fixtures' -prune -o -type f -name '*.rs' -exec awk '
    /^[[:space:]]*\/\/([^\/!]|$)/ ||
    /^[[:space:]]*\/\/[\/!][[:space:]]*Why( not)?([[:space:]]*[（(][^）)]*[）)])?[[:space:]]*[:：]/ {
      print FILENAME ":" FNR ": " $0
    }
  ' {} +)"
  scan_status=$?
  if [ "$scan_status" -ne 0 ]; then
    printf 'comment-style: %s の走査に失敗しました(終了コード %s)\n' "$root" "$scan_status" >&2
    exit 2
  fi
  if [ -n "$lines" ]; then
    found="${found}${lines}"$'\n'
  fi
done

if [ -z "$found" ]; then
  exit 0
fi

printf 'doc 以外のコメントがあります。コメントは doc(`///` / `//!`)だけにし、Why / Why not は Issue かコミットメッセージに書いてください:\n'
printf '%s' "$found"
exit 1
