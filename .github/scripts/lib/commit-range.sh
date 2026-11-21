#!/usr/bin/env bash
#
# `<base> <head>` の範囲を辿るスクリプトが共有する、範囲を辿る前の確かめ方。source して使う。
# 止めるときは、source した側の `$0` のファイル名を前に付けた理由を標準エラーへ出して exit 2 で終わる。
#
# 使う側: `.github/scripts/red-commits.sh` / `.github/scripts/lock-publish-age.sh`

# 浅いクローンなら、理由を出して exit 2 で終わる。浅いクローンでは `<base>..<head>` が途中で切れ、
# 切れた先のコミットを黙って取りこぼす。
#
# $1 取りこぼしうるもの（理由の文に入れる。例: `Red`）
stop_if_shallow_clone() {
  local shallow
  shallow="$(git rev-parse --is-shallow-repository)" || exit 2
  [ "$shallow" = false ] && return 0
  echo "$(basename "$0"): 浅いクローンでは範囲を辿り切れず $1 を取りこぼしうるので止める(全履歴を取ってから走らせる)" >&2
  exit 2
}

# 引数の revision をコミットの完全なハッシュへ解決して出す。解決できなければ理由を標準エラーに出して exit 2。
# コマンド置換の中で呼ぶので、呼ぶ側は `|| exit 2` で受ける。
#
# Why: 解決せずに `<base>..<head>` を git へ渡すと、空の head は HEAD と読まれ、存在しない revision は
# 同じ名前のパスが作業ツリーにあればパスの指定と読まれる。どちらも成功で終わる。
#
# $1 引数の名前(`<base>` / `<head>`)
# $2 解決する revision
commit_of() {
  local sha
  if sha="$(git rev-parse --verify -q --end-of-options "$2^{commit}")"; then
    echo "$sha"
    return 0
  fi
  echo "$(basename "$0"): $1 の '$2' をコミットへ解決できない" >&2
  exit 2
}
