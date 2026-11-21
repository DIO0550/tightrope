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
#   2 crate の名前が crates.io の文字種でない・設定・index・版のどれかが読めない（経っているかを決められないので、
#     通さない側に倒す）
#
# 環境変数（判定表が偽の index と設定へ差し替えるためのもの）:
#   TOOL_COOLDOWN_INDEX_URL  sparse index の根。既定は https://index.crates.io。curl が読める file:// も渡せる
#   TOOL_COOLDOWN_CONFIG     期間を読む設定ファイル。既定はこのリポジトリの .cargo/config.toml

set -uo pipefail

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

. "$here/lib/publish-age.sh" || undecidable "$here/lib/publish-age.sh を読み込めない"

[ "$#" -eq 2 ] || undecidable "使い方: tool-cooldown.sh <crate> <版>"
crate="$1"
version="$2"
[ -n "$crate" ] || undecidable "crate の名前が空"
[ -n "$version" ] || undecidable "版が空"

min_days="$(min_publish_days_of tool-cooldown "$config")" || exit 2
index_lines="$(index_lines_of tool-cooldown "$index_url" "$crate")" || exit 2
pubtime="$(pubtime_of tool-cooldown "$crate" "$version" "$index_lines")" || exit 2

if ! has_passed_min_publish_age_at "$(date -u +%s)" "$pubtime" "$min_days"; then
  echo "tool-cooldown: $crate $version は $pubtime の公開で、$min_days 日経っていない"
  exit 1
fi
echo "tool-cooldown: $crate $version は $pubtime の公開で、$min_days 日経っている"
