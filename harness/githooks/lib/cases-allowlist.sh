#!/usr/bin/env bash
#
# 検査の判定表(`crate-deps-cases.sh` / `folder-deps-cases.sh` / `lints-inheritance-cases.sh` / `lint-level-attributes-cases.sh` /
# `test-placement-cases.sh` / `test-file-length-cases.sh` / `comment-style-cases.sh` / `cargo-config-rustflags-cases.sh` /
# `io-outside-driver-cases.sh`)が共有する、
# 1 ケースの判定の綴りと、ケースの走らせ方。
#
# 使い方: 判定表が `cases-report.sh` を source した後に source する。次の大域変数を前提にする。
#   script   検査のスクリプトのパス
#   work     標準出力・標準エラーを書く置き場のディレクトリ
#   heading  検査が違反を報告するときの見出しの正規表現(`grep -E` に渡す)

# 検査を走らせた後の標準出力・標準エラー・終了コードから、ケースの判定を出す。
#   unavailable  exit 2 で、標準出力が空
#   pass         exit 0 で、標準出力・標準エラーとも空。どちらかに何か出ていれば `pass(出力あり)`
#   deny         exit 1 で見出しを出し、見出しを除いた違反の行の集合が期待と完全一致する。違えば `deny(違反の行が違う)`
#   broken       それ以外(`decide` が broken を返したもの)
#
# $1 標準出力を書いたファイル
# $2 標準エラーを書いたファイル
# $3 終了コード
# $4 期待する違反の行(1 行 1 件。deny 以外では空)
decision_of() {
  local stdout_file="$1" stderr_file="$2" status="$3" expected_lines="$4" output decision
  local reported_unavailable=no printed_nothing=no
  output="$(cat "$stdout_file")"
  [ "$status" -eq 2 ] && [ -z "$output" ] && reported_unavailable=yes
  if [ "$reported_unavailable" = yes ]; then
    echo unavailable
    return 0
  fi
  decision="$(decide "$output" "$status" "$heading")"
  case "$decision" in
    pass)
      [ -z "$output" ] && [ ! -s "$stderr_file" ] && printed_nothing=yes
      [ "$printed_nothing" = yes ] && { echo pass; return 0; }
      echo 'pass(出力あり)'
      ;;
    deny)
      [ "$(violations_of "$stdout_file")" = "$(sorted_lines_of "$expected_lines")" ] && { echo deny; return 0; }
      echo 'deny(違反の行が違う)'
      ;;
    *) echo "$decision" ;;
  esac
}

# 検査の標準出力から見出しを除いた行を、並べ替えて出す。
#
# $1 標準出力を書いたファイル
violations_of() {
  grep -vE "$heading" "$1" | LC_ALL=C sort
}

# 1 行 1 件の行を、空行を除いて並べ替えて出す。
#
# $1 行
sorted_lines_of() {
  printf '%s\n' "$1" | grep -v '^$' | LC_ALL=C sort
}

# 食い違ったケースの、期待した違反の行と実際の違反の行を字下げして出す。実際の行が無ければ `なし`。
#
# $1 標準出力を書いたファイル
# $2 期待する違反の行
show_violation_lines() {
  local actual
  sorted_lines_of "$2" | sed 's/^/       期待: /'
  actual="$(violations_of "$1")"
  if [ -z "$actual" ]; then
    echo '       実際: なし'
    return 0
  fi
  printf '%s\n' "$actual" | sed 's/^/       実際: /'
}

# 検査を走らせて、判定を表の期待と照らす。食い違ったら、期待した違反の行と実際の違反の行も出す。
# 期待が `miss`(意図した取りこぼし)なら、判定 pass を `miss` と読む(`normalize_miss`)。
#
# $1 期待する判定(pass / deny / unavailable / miss)
# $2 期待する違反の行(1 行 1 件。deny 以外では空)
# $3 ケース名
# $4 以降 検査を走らせるコマンド
run_case() {
  local expected="$1" expected_lines="$2" label="$3" status=0 decision
  shift 3
  "$@" >"$work/stdout" 2>"$work/stderr" || status=$?
  decision="$(normalize_miss "$expected" "$(decision_of "$work/stdout" "$work/stderr" "$status" "$expected_lines")")"
  report "$expected" "$decision" "$label"
  [ "$decision" = "$expected" ] && return 0
  printf '       終了コード: %s\n' "$status"
  [ "$expected" = deny ] && show_violation_lines "$work/stdout" "$expected_lines"
  return 0
}

# 標準エラーに当たる行が無かった綴りを、1 行 1 件で出す。すべて当たれば何も出さない。
#
# $1 標準エラーを書いたファイル
# $2 当たるはずの行の拡張正規表現(1 行 1 件)
missing_reasons_of() {
  local stderr_file="$1" reason
  while IFS= read -r reason; do
    [ -n "$reason" ] || continue
    grep -qE -- "$reason" "$stderr_file" || printf '%s\n' "$reason"
  done <<<"$2"
}

# 検査を走らせて、検査できなかったこと(判定 unavailable)と、その理由が標準エラーに出たことを照らす。
# 当たる行が無い綴りがあれば、判定の後ろに `(理由が無い)` を付けて食い違いにし、その綴りと標準エラーを出す。
#
# $1 標準エラーに当たるはずの行の拡張正規表現(1 行 1 件)
# $2 ケース名
# $3 以降 検査を走らせるコマンド
run_unavailable_case() {
  local expected_reasons="$1" label="$2" status=0 decision missing_reasons
  shift 2
  "$@" >"$work/stdout" 2>"$work/stderr" || status=$?
  decision="$(decision_of "$work/stdout" "$work/stderr" "$status" '')"
  missing_reasons="$(missing_reasons_of "$work/stderr" "$expected_reasons")"
  [ -z "$missing_reasons" ] || decision="$decision(理由が無い)"
  report unavailable "$decision" "$label"
  [ "$decision" = unavailable ] && return 0
  printf '       終了コード: %s\n' "$status"
  printf '%s\n' "$missing_reasons" | grep -v '^$' | sed 's/^/       無い理由: /'
  sed 's/^/       標準エラー: /' "$work/stderr"
  return 0
}

# 根を引数に渡して検査を走らせる。
#
# $1 workspace の根
run_with_root() {
  bash "$script" "$1"
}

# 根をカレントにして、引数なしで検査を走らせる。
#
# $1 workspace の根
run_in_root() {
  (cd "$1" && bash "$script")
}
