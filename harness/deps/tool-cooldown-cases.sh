#!/usr/bin/env bash
#
# 道具の cooldown（`tool-cooldown.sh`）の判定表。
#
# 一時ディレクトリに偽の sparse index と設定を置き、file:// で読ませて、終了コードと見出しから
# pass（期間が経っている）/ deny（経っていない）/ broken（読めないので通さない）を読む。
#
# 使い方: bash harness/deps/tool-cooldown-cases.sh
# 食い違ったケースがあれば exit 1（`ok` だけなら期待どおり）。

set -uo pipefail

here="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
detector="$here/tool-cooldown.sh"
work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT

source "$here/../../.claude/hooks/lib/cases-report.sh"

heading='^tool-cooldown: .* 日経っていない$'
index="$work/index"
long_ago='2000-01-01T00:00:00Z'

# 今から $1 日前の pubtime を、index と同じ書き方で出す。
#
# $1 日数
days_ago() {
  jq -rn --argjson days "$1" 'now - $days * 86400 | floor | todate'
}

# 偽の index の、そのパスに版を 1 行置く。
#
# $1 index の根からのパス
# $2 版の一覧の 1 行（JSON）
put_index_line() {
  mkdir -p "$(dirname "$index/$1")"
  printf '%s\n' "$2" >>"$index/$1"
}

# 設定ファイルを置き、そのパスを出す。
#
# $1 ファイル名
# $2 中身
config_of() {
  printf '%s' "$2" >"$work/$1"
  echo "$work/$1"
}

# 偽の index と渡した設定で検出器を走らせ、判定を 1 語で出す。
#
# $1 設定ファイル（`-` なら既定の、このリポジトリの .cargo/config.toml）
# $2 以降 検出器へ渡す引数
verdict_of() {
  local config="$1" output status
  shift
  if [ "$config" = "-" ]; then
    output="$(TOOL_COOLDOWN_INDEX_URL="file://$index" bash "$detector" "$@" 2>/dev/null)"
  else
    output="$(TOOL_COOLDOWN_INDEX_URL="file://$index" TOOL_COOLDOWN_CONFIG="$config" bash "$detector" "$@" 2>/dev/null)"
  fi
  status=$?
  decide "$output" "$status" "$heading"
}

fourteen_days="$(config_of fourteen.toml $'[registry]\nglobal-min-publish-age = "14 days"\n')"
three_days="$(config_of three.toml $'[registry]\nglobal-min-publish-age = "3 days"\n')"
one_day="$(config_of one.toml $'[registry]\nglobal-min-publish-age = "1 day"\n')"
no_age="$(config_of no-age.toml $'[registry]\n')"
weeks="$(config_of weeks.toml $'[registry]\nglobal-min-publish-age = "2 weeks"\n')"
other_table_only="$(config_of other-table-only.toml $'[registry]\n\n[other]\nglobal-min-publish-age = "0 days"\n')"
other_table_first="$(config_of other-table-first.toml $'[other]\nglobal-min-publish-age = "0 days"\n\n[registry]\nglobal-min-publish-age = "3 days"\n')"
trailing_comment="$(config_of trailing-comment.toml $'[registry]\nglobal-min-publish-age = "3 days" # 検知ラグを覆う\n')"
no_spaces="$(config_of no-spaces.toml $'[registry]\nglobal-min-publish-age="3 days"\n')"
leading_zero="$(config_of leading-zero.toml $'[registry]\nglobal-min-publish-age = "010 days"\n')"

put_index_line ca/rg/cargo-mutants "{\"name\":\"cargo-mutants\",\"vers\":\"1.0.0\",\"pubtime\":\"$long_ago\"}"
put_index_line ca/rg/cargo-mutants "{\"name\":\"cargo-mutants\",\"vers\":\"1.1.0\",\"pubtime\":\"$(days_ago 0)\"}"
put_index_line ca/rg/cargo-mutants "{\"name\":\"cargo-mutants\",\"vers\":\"1.2.0\",\"pubtime\":\"$(days_ago 2)\"}"
put_index_line ca/rg/cargo-mutants "{\"name\":\"cargo-mutants\",\"vers\":\"1.3.0\",\"pubtime\":\"$(days_ago 4)\"}"
put_index_line ca/rg/cargo-mutants '{"name":"cargo-mutants","vers":"1.4.0"}'
put_index_line ca/rg/cargo-mutants '{"name":"cargo-mutants","vers":"1.5.0","pubtime":"昨日"}'
put_index_line ca/rg/cargo-mutants "{\"name\":\"cargo-mutants\",\"vers\":\"1.6.0\",\"pubtime\":\"$(days_ago 9)\"}"

report pass "$(verdict_of "$fourteen_days" cargo-mutants 1.0.0)" \
  "公開から期間が経った版は通す"
report deny "$(verdict_of "$fourteen_days" cargo-mutants 1.1.0)" \
  "公開から期間が経っていない版は落とす"
report pass "$(verdict_of "$three_days" cargo-mutants 1.3.0)" \
  "期間は設定の日数で決まる（3 days なら 4 日前の版を通す）"
report deny "$(verdict_of "$three_days" cargo-mutants 1.2.0)" \
  "期間は設定の日数で決まる（3 days なら 2 日前の版を落とす）"
report pass "$(verdict_of "$one_day" cargo-mutants 1.2.0)" \
  "単数の 1 day も読む（2 日前の版を通す）"
report pass "$(verdict_of - cargo-mutants 1.0.0)" \
  "設定を差し替えなければ、このリポジトリの .cargo/config.toml を読む（古い版は通す）"
report deny "$(verdict_of - cargo-mutants 1.1.0)" \
  "設定を差し替えなければ、このリポジトリの .cargo/config.toml を読む（公開直後の版は落とす）"
report deny "$(verdict_of "$other_table_first" cargo-mutants 1.2.0)" \
  "[registry] の前に別のテーブルの同じキーがあっても [registry] の値を使う（3 days なら 2 日前の版を落とす）"
report deny "$(verdict_of "$trailing_comment" cargo-mutants 1.2.0)" \
  "値の後ろのコメントを読み飛ばす（3 days なら 2 日前の版を落とす）"
report deny "$(verdict_of "$no_spaces" cargo-mutants 1.2.0)" \
  "= の前後に空白が無くても読む（3 days なら 2 日前の版を落とす）"
report deny "$(verdict_of "$leading_zero" cargo-mutants 1.6.0)" \
  "0 始まりの日数を 10 進数で読む（010 days なら 9 日前の版を落とす）"

report broken "$(verdict_of "$fourteen_days" cargo-mutants 9.9.9)" \
  "index に無い版は exit 2（通さない）"
report broken "$(verdict_of "$fourteen_days" cargo-mutants 1.4.0)" \
  "pubtime を持たない版は exit 2（通さない）"
report broken "$(verdict_of "$fourteen_days" cargo-mutants 1.5.0)" \
  "pubtime が日時として読めない版は exit 2（通さない）"
report broken "$(verdict_of "$no_age" cargo-mutants 1.0.0)" \
  "設定に global-min-publish-age が無ければ exit 2（通さない）"
report broken "$(verdict_of "$other_table_only" cargo-mutants 1.0.0)" \
  "global-min-publish-age が [registry] に無く別のテーブルにだけあれば exit 2（通さない）"
report broken "$(verdict_of "$weeks" cargo-mutants 1.0.0)" \
  "日数でない書き方（2 weeks）は exit 2（通さない）"
report broken "$(verdict_of "$work/missing.toml" cargo-mutants 1.0.0)" \
  "設定ファイルが無ければ exit 2（通さない）"
report broken "$(verdict_of "$fourteen_days" no-such-crate 1.0.0)" \
  "index にその crate のファイルが無ければ exit 2（通さない）"
report broken "$(verdict_of "$fourteen_days" cargo-mutants)" \
  "版を渡さなければ exit 2（通さない）"

# 名前の長さごとの、sparse index のパスの組み方。パスを読み違えると index が読めず broken になる。
cases_before=$cases_reported
while IFS='|' read -r crate path label; do
  put_index_line "$path" "{\"name\":\"$crate\",\"vers\":\"1.0.0\",\"pubtime\":\"$long_ago\"}"
  report pass "$(verdict_of "$fourteen_days" "$crate" 1.0.0)" "$label"
done <<'PATHS'
a|1/a|名前が 1 文字なら 1/<名前> を読む
cc|2/cc|名前が 2 文字なら 2/<名前> を読む
syn|3/s/syn|名前が 3 文字なら 3/<先頭 1 文字>/<名前> を読む
serde|se/rd/serde|名前が 4 文字以上なら <先頭 2 文字>/<3〜4 文字目>/<名前> を読む
Inflector|in/fl/inflector|大文字を含む名前は小文字にしたパスを読む
PATHS
report_cases_ran PATHS "$cases_before"

exit "$cases_failed"
