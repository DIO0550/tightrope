#!/usr/bin/env bash
#
# 版が公開から `.cargo/config.toml` の `global-min-publish-age` の期間を経ているかを決めるのに要る、期間の
# 読み方と sparse index の読み方。source して使う。どの関数も exit せず、読めなければ 0 以外を返す
# (理由の文と終了コードは使う側が決める)。
#
# 使う側: harness/deps/tool-cooldown.sh / .github/scripts/lock-publish-age.sh

seconds_per_day=86400
# index へつながるまでと、取得し終えるまでの上限。超えたら index を読めないとして扱う。
index_connect_timeout_seconds=10
index_max_time_seconds=60

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
# $1 設定ファイル
# 終了コード: 0 = 出した / 1 = 設定ファイルを読めない / 2 = `"N days"` の形で 1 つ読めない
# Why not（日数以外の単位も読む）: 読み方を増やすほど読み違いが増える。読めなければ通さないので、
# 書き方を変えたらここが落ちて気づく。
min_publish_days_of() {
  local line pattern
  line="$(registry_publish_age_line_of "$1" 2>/dev/null)" || return 1
  pattern='^[[:space:]]*global-min-publish-age[[:space:]]*=[[:space:]]*"([0-9]+) days?"[[:space:]]*(#.*)?$'
  [[ "$line" =~ $pattern ]] || return 2
  # 10 進数として読む。素の算術では 0 始まりの日数（"010 days"）が 8 進数になり、期間が縮む。
  echo "$((10#${BASH_REMATCH[1]}))"
}

# sparse index から、その crate の版の一覧（1 行に 1 版の JSON）を出す。
#
# $1 sparse index の根。curl が読める file:// も渡せる
# $2 crate の名前（空でないこと）
# 終了コード: 一覧を読めなければ 0 以外（curl の終了コード）
index_lines_of() {
  curl -fsS --connect-timeout "$index_connect_timeout_seconds" --max-time "$index_max_time_seconds" \
    "$1/$(index_path_of "$2")"
}

# 版の一覧から、その版を公開した時刻を `<エポック秒><TAB><index の pubtime>` の 1 行で出す。
#
# $1 版の一覧（`index_lines_of` の出力）
# $2 版
# 終了コード: 0 = 出した / 1 = 一覧を JSON として読めない / 2 = 一覧にその版が無い /
#   3 = その版の pubtime が無い・日時として読めない
published_at_of() {
  local entry pubtime published_at
  entry="$(jq -c --arg v "$2" 'select(.vers == $v)' <<<"$1")" || return 1
  [ -n "$entry" ] || return 2
  pubtime="$(jq -r '.pubtime // empty' <<<"$entry")"
  published_at="$(jq -r '.pubtime | fromdateiso8601' <<<"$entry" 2>/dev/null)" || return 3
  printf '%s\t%s\n' "$published_at" "$pubtime"
}
