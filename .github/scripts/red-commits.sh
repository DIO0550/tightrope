#!/usr/bin/env bash
#
# PR の範囲(`<base>..<head>`)の中で Red の印を持つコミットを、完全なハッシュで 1 行に 1 つ出す。
# git は呼んだ側のカレントのリポジトリへ打つ。
#
# 使い方:
#   bash .github/scripts/red-commits.sh <base> <head>
#
# Red の印は、コミットメッセージの最後の段落のトレーラ `TDD: red`。キーの大文字小文字は区別せず、
# 値は `red` と完全に一致するものだけを拾う(`Red` や `red extra` は拾わない)。
# 判定表は `.github/scripts/red-commits-cases.sh`。
#
# 終了コード:
#   0 = 拾い終えた(Red が 0 件でも 0)
#   2 = 引数が 2 つでない・`git log` が失敗した(範囲を解決できない等)・浅いクローン。どれも理由を標準エラーに出す
#   127 = 読み込む `lib/usage.sh` を読み込めない
set -uo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 127
. "$scripts_dir/lib/usage.sh" || exit 127

[ $# -eq 2 ] || usage

# Why: 浅いクローンでは `<base>..<head>` が途中で切れ、切れた先の Red を黙って取りこぼす。
# 理由を出すのは、出力が空なのを「Red が 0 件」と読み違えさせないため。
shallow="$(git rev-parse --is-shallow-repository)" || exit 2
if [ "$shallow" != false ]; then
  echo "red-commits.sh: 浅いクローンでは範囲を辿り切れず Red を取りこぼしうるので止める(全履歴を取ってから走らせる)" >&2
  exit 2
fi

# Why: `unfold` が無いと、折り返した `TDD: red` と継続行が別の値に割れ、`red` だけの値として拾ってしまう。
# Why not(`$2 == "red"` で 1 つ目の値だけ見る): TDD のトレーラを 2 つ持つコミットの 2 つ目の `red` を取りこぼす。
log="$(git log --reverse --format='%H%x09%(trailers:key=TDD,valueonly,unfold,separator=%x09)' "$1..$2")" || exit 2

awk -F '\t' '{ for (i = 2; i <= NF; i++) if ($i == "red") { print $1; next } }' <<<"$log"
