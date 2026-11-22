#!/usr/bin/env bash
#
# 版が公開から `.cargo/config.toml` の `global-min-publish-age` の期間を経ているかを決めるのに要る、期間の
# 読み方・sparse index の読み方・期間を経たかの比べ方。source して使う。どの関数も exit しない。読めなければ、
# 使う側が渡した接頭辞を付けた理由を標準エラーに出して 0 以外を返す(終了コードは使う側が決める)。
#
# 使う側: harness/deps/tool-cooldown.sh / .github/scripts/lock-publish-age.sh

seconds_per_day=86400
# index へつながるまでと、取得し終えるまでの上限。超えたら index を読めないとして扱う。
index_connect_timeout_seconds=10
index_max_time_seconds=60
# crates.io が crate の名前に許す文字。外れた名前は index のパスにも curl の URL にも入れない。
crate_name_pattern='^[A-Za-z0-9_-]+$'

# 接頭辞を付けた理由を標準エラーに出し、1 を返す。
#
# $1 接頭辞
# $2 理由
undecidable_reason() {
  echo "$1: $2" >&2
  return 1
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

# 設定ファイルの `[registry]` テーブルにある `global-min-publish-age` の行を出す。他のテーブルの
# 同じキーは見ない。テーブルの見出しは前後の空白だけを許し、それ以外の書き方の見出しは
# `[registry]` の外として読む（読めなければ通さない側に倒れる）。
#
# $1 設定ファイル
# 出力: その行。無い・2 行以上あるときは何も出さない
# Why: 呼ぶ側の `=~` では `.` も `[[:space:]]` も改行に当たり、2 行を 1 行として読みうるので、ここで 1 行に絞る。
registry_publish_age_line_of() {
  awk '
    /^[[:space:]]*\[/ { in_registry = /^[[:space:]]*\[registry\][[:space:]]*$/; next }
    in_registry && /^[[:space:]]*global-min-publish-age[[:space:]]*=/ { found++; line = $0 }
    END { if (found == 1) print line }
  ' "$1"
}

# 設定ファイルの `[registry]` の `global-min-publish-age` を日数として出す。
#
# $1 理由の接頭辞
# $2 設定ファイル
# 終了コード: 設定ファイルを読めない・`"N days"` の形で 1 つ読めないなら、理由を出して 1
# Why not（日数以外の単位も読む）: 読み方を増やすほど読み違いが増える。読めなければ通さないので、
# 書き方を変えたらここが落ちて気づく。
min_publish_days_of() {
  local line pattern
  line="$(registry_publish_age_line_of "$2" 2>/dev/null)" || undecidable_reason "$1" "$2 を読めない" || return
  pattern='^[[:space:]]*global-min-publish-age[[:space:]]*=[[:space:]]*"([0-9]+) days?"[[:space:]]*(#.*)?$'
  [[ "$line" =~ $pattern ]] ||
    undecidable_reason "$1" "$2 の [registry] の global-min-publish-age を \"N days\" として 1 つ読めない" || return
  # 10 進数として読む。素の算術では 0 始まりの日数（"010 days"）が 8 進数になり、期間が縮む。
  echo "$((10#${BASH_REMATCH[1]}))"
}

# sparse index から、その crate の版の一覧（1 行に 1 版の JSON）を出す。
#
# $1 理由の接頭辞
# $2 sparse index の根。curl が読める file:// も渡せる
# $3 crate の名前
# 終了コード: 名前が crates.io の文字種（英数字・`_`・`-`）でない・一覧を読めないなら、理由を出して 1
index_lines_of() {
  [[ "$3" =~ $crate_name_pattern ]] ||
    undecidable_reason "$1" "crate の名前 '$3' が crates.io の文字種(英数字・_・-)でない" || return
  curl -fsS --connect-timeout "$index_connect_timeout_seconds" --max-time "$index_max_time_seconds" \
    "$2/$(index_path_of "$3")" || undecidable_reason "$1" "$3 の版の一覧を $2 から読めない"
}

# 版の一覧から、その版の index の pubtime を出す。出すのは日時として読めると確かめた値だけ。
#
# $1 理由の接頭辞
# $2 crate の名前（理由の文に入れる）
# $3 版
# $4 版の一覧（`index_lines_of` の出力）
# 終了コード: 一覧を JSON として読めない・一覧にその版が無い・その版の pubtime が無い・日時として読めないなら、
#   理由を出して 1
pubtime_of() {
  local entry pubtime
  entry="$(jq -c --arg v "$3" 'select(.vers == $v)' <<<"$4")" ||
    undecidable_reason "$1" "$2 の版の一覧を JSON として読めない" || return
  [ -n "$entry" ] || undecidable_reason "$1" "$2 $3 が index に無い" || return
  pubtime="$(jq -r '.pubtime // empty' <<<"$entry")"
  jq -n --arg at "$pubtime" '$at | fromdateiso8601' >/dev/null 2>&1 ||
    undecidable_reason "$1" "$2 $3 の pubtime が無い・読めない" || return
  echo "$pubtime"
}

# 見る時刻に、公開から期間を経ていたかを決める。経ていれば 0、経ていなければ 1。
#
# $1 見る時刻（エポック秒）
# $2 公開の時刻（`pubtime_of` の出力）
# $3 期間の日数（`min_publish_days_of` の出力）
# 終了コード: 公開の時刻を日時として読めなければ、経ていない側の 1
has_passed_min_publish_age_at() {
  local published_at
  published_at="$(jq -rn --arg at "$2" '$at | fromdateiso8601')" || return 1
  [ "$1" -ge $((published_at + $3 * seconds_per_day)) ]
}
