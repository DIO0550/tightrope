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
#   2 = 引数が 2 つでない・引数をコミットへ解決できない(空・存在しない revision)・浅いクローン・`git log` が失敗した。
#       どれも理由を標準エラーに出す
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

# 引数の revision をコミットの完全なハッシュへ解決して出す。解決できなければ理由を標準エラーに出して exit 2。
#
# Why: 解決せずに `<base>..<head>` を `git log` へ渡すと、空の head は HEAD と読まれ、存在しない revision は
# 同じ名前のパスが作業ツリーにあればパスの指定と読まれる。どちらも「Red が 0 件」などの成功で終わる。
#
# $1 引数の名前(`<base>` / `<head>`)
# $2 解決する revision
commit_of() {
  local sha
  if sha="$(git rev-parse --verify -q --end-of-options "$2^{commit}")"; then
    echo "$sha"
    return 0
  fi
  echo "red-commits.sh: $1 の '$2' をコミットへ解決できない" >&2
  exit 2
}

base="$(commit_of '<base>' "$1")" || exit 2
head="$(commit_of '<head>' "$2")" || exit 2

# 1 コミットにつき、ハッシュの行に続けて TDD のトレーラの値を 1 つずつ、行頭にタブを付けた行で出す。
# Why(値ごとに 1 行): 値はタブを含みうるので、タブで割ると `green<TAB>red` を `red` と取り違える。
# `unfold` した値は改行を含まないので、行で区切れば git が読んだ値の境界が保たれる。
# Why not(値を NUL で区切る): bash の変数に NUL は入らず、awk が NUL を区切りに使えるかも POSIX で決まっていない。
# Why(`unfold`): 無いと、折り返した `TDD: red` と継続行が別の値に割れ、`red` だけの値として拾ってしまう。
log="$(git log --reverse --format='%H%n%x09%(trailers:key=TDD,valueonly,unfold,separator=%x0a%x09)' \
  "$base..$head" --)" || exit 2

# Why not(1 つ目の値だけ見る): TDD のトレーラを 2 つ持つコミットの 2 つ目の `red` を取りこぼす。
awk '
  !/^\t/ { commit = $0; picked = 0; next }
  picked { next }
  substr($0, 2) == "red" { print commit; picked = 1 }
' <<<"$log"
