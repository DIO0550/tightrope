#!/usr/bin/env bash
#
# `cargo install` で入れる道具の版が、公開から `.cargo/config.toml` の `global-min-publish-age` の
# 期間を経ているかを確かめる。入れる前にこれを通す（harness/deps/README.md「道具の cooldown」）。
#
# Why: `cargo install` は `global-min-publish-age` を見ないので、resolve.sh の外で入る道具は
# 入れる前のここでしか止められない。
#
# 使い方: bash harness/deps/tool-cooldown.sh <crate> <版>
#
# 終了コード:
#   0 期間が経っている
#   1 期間が経っていない
#   2 設定・index・版のどれかが読めない（経っているかを決められないので、通さない側に倒す）
#
# 環境変数（判定表が偽の index と設定へ差し替えるためのもの）:
#   TOOL_COOLDOWN_INDEX_URL  sparse index の根。既定は https://index.crates.io。curl が読める file:// も渡せる
#   TOOL_COOLDOWN_CONFIG     期間を読む設定ファイル。既定はこのリポジトリの .cargo/config.toml

set -uo pipefail

seconds_per_day=86400
here="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
index_url="${TOOL_COOLDOWN_INDEX_URL:-https://index.crates.io}"
config="${TOOL_COOLDOWN_CONFIG:-$here/../../.cargo/config.toml}"

# 経っているかを決められない理由を出して、exit 2 で終わる。
#
# $1 理由
undecidable() {
  echo "tool-cooldown: $1" >&2
  exit 2
}

# sparse index の中で、その crate の版の一覧が置かれたパスを出す。名前は小文字にし、長さで
# 1/<名前>・2/<名前>・3/<先頭 1 文字>/<名前>・<先頭 2 文字>/<3〜4 文字目>/<名前> に振り分ける。
#
# $1 crate の名前（空でないこと）
index_path_of() {
  local name
  name="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "${#name}" in
    1) echo "1/$name" ;;
    2) echo "2/$name" ;;
    3) echo "3/${name:0:1}/$name" ;;
    *) echo "${name:0:2}/${name:2:2}/$name" ;;
  esac
}

[ "$#" -eq 2 ] || undecidable "使い方: tool-cooldown.sh <crate> <版>"
crate="$1"
version="$2"
[ -n "$crate" ] || undecidable "crate の名前が空"
[ -n "$version" ] || undecidable "版が空"

# Why not（日数以外の単位も読む）: 読み方を増やすほど読み違いが増える。読めなければ通さないので、
# 書き方を変えたらここが落ちて気づく。
min_days="$(sed -nE 's/^global-min-publish-age = "([0-9]+) days?"$/\1/p' "$config" 2>/dev/null)"
[[ "$min_days" =~ ^[0-9]+$ ]] || undecidable "$config の global-min-publish-age を \"N days\" として 1 つ読めない"

index_lines="$(curl -fsS "$index_url/$(index_path_of "$crate")")" || undecidable "$crate の版の一覧を $index_url から読めない"
entry="$(jq -c --arg v "$version" 'select(.vers == $v)' <<<"$index_lines")" || undecidable "$crate の版の一覧を JSON として読めない"
[ -n "$entry" ] || undecidable "$crate $version が index に無い"
pubtime="$(jq -r '.pubtime // empty' <<<"$entry")"
published_at="$(jq -r '.pubtime | fromdateiso8601' <<<"$entry" 2>/dev/null)" || undecidable "$crate $version の pubtime が無い・読めない"

usable_from=$((published_at + min_days * seconds_per_day))
if [ "$(date -u +%s)" -lt "$usable_from" ]; then
  echo "tool-cooldown: $crate $version は $pubtime の公開で、$min_days 日経っていない"
  exit 1
fi
echo "tool-cooldown: $crate $version は $pubtime の公開で、$min_days 日経っている"
