#!/usr/bin/env bash
#
# PR の範囲(`<base>..<head>`)で Cargo.lock に足した crates.io の版が、足したコミットの時点で公開から
# `.cargo/config.toml` の `global-min-publish-age` の期間を経ていたかを確かめる。git は呼んだ側のカレントの
# リポジトリへ打つ。判定表は `.github/scripts/lock-publish-age-cases.sh`、残る穴は
# `harness/deps/README.md`「lock の公開からの期間(PR での事後の検知)」。
#
# 使い方:
#   bash .github/scripts/lock-publish-age.sh <base> <head>
#
# 確かめる版と、その時点:
#   - 範囲の各コミットについて、そのコミットと 1 つ目の親の Cargo.lock を比べ、増えた (name, version, source) を
#     「そのコミットで足した版」とする。同じ版を足したコミットが複数あれば、committer の時刻がいちばん早いものを使う
#   - 確かめるのは、head の Cargo.lock にあり base の Cargo.lock に無く、範囲で足した版だけ
#   - source が crates.io の版を確かめ、git と path の版は飛ばす。それ以外の registry の版は止める
#   - 足したコミットの committer の時刻が、公開の時刻に期間を足した時刻より前なら、期間を経ていない
#
# 出力(標準出力):
#   - 期間を経ていない版ごとに `lock-publish-age: <name> <version> は <pubtime> の公開で、足したコミット <hash>（<時刻>）の時点で <日数> 日経っていない`
#   - 最後の行に `lock-publish-age: <base>..<head> の <N> コミットを見て、足した版 <M> 件を確かめた`(exit 0 / 1 のとき)
#
# 終了コード:
#   0 = 確かめた版がすべて期間を経ていた(確かめた版が 0 件でも 0)
#   1 = 期間を経ていない版がある
#   2 = 引数が 2 つでない・引数をコミットへ解決できない・浅いクローン・git から範囲やコミットを読めない・
#       ルート以外の Cargo.lock を変えた・Cargo.lock の [[package]] を読めない・crates.io 以外の registry の版を足した・
#       設定 / index / 版のどれかが読めない。
#       どれも理由を標準エラーに出す(経ていたかを決められないので、通さない側に倒す)
#   127 = 読み込む lib を読み込めない
#
# 環境変数(判定表が偽の index と設定へ差し替えるためのもの):
#   LOCK_PUBLISH_AGE_INDEX_URL  sparse index の根。既定は https://index.crates.io。curl が読める file:// も渡せる
#   LOCK_PUBLISH_AGE_CONFIG     期間を読む設定ファイル。既定はこのリポジトリの .cargo/config.toml
set -uo pipefail

scripts_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 127
. "$scripts_dir/lib/usage.sh" || exit 127
. "$scripts_dir/lib/commit-range.sh" || exit 127
. "$scripts_dir/../../harness/deps/lib/publish-age.sh" || exit 127

index_url="${LOCK_PUBLISH_AGE_INDEX_URL:-https://index.crates.io}"
config="${LOCK_PUBLISH_AGE_CONFIG:-$scripts_dir/../../.cargo/config.toml}"
crates_io_source='registry+https://github.com/rust-lang/crates.io-index'
# 記録の欄の区切り。タブは read が空の欄(path の版の source)を詰めてしまうので、空白でない文字を使う。
sep=$'\x1f'

# 経ていたかを決められない理由を出して、exit 2 で終わる。
#
# $1 理由
undecidable() {
  echo "lock-publish-age: $1" >&2
  exit 2
}

[ $# -eq 2 ] || usage
stop_if_shallow_clone 足した版
base="$(commit_of '<base>' "$1")" || exit 2
head="$(commit_of '<head>' "$2")" || exit 2

min_days="$(min_publish_days_of "$config")"
case "$?" in
  0) ;;
  1) undecidable "$config を読めない" ;;
  *) undecidable "$config の [registry] の global-min-publish-age を \"N days\" として 1 つ読めない" ;;
esac

# そのコミットのルートの Cargo.lock の [[package]] を、`<name><区切り><version><区切り><source>` の行でバイト順に
# 重複なく出す。path の版は source が空になる。Cargo.lock が無ければ何も出さない。
#
# $1 コミット
# 終了コード: name か version を読めない [[package]] がある・`[[package]]` 以外で package を含む見出しがある・
#   Cargo.lock を取り出せないなら 0 以外
packages_of() {
  local lock
  git cat-file -e "$1:Cargo.lock" 2>/dev/null || return 0
  lock="$(git show "$1:Cargo.lock")" || return 1
  awk -v sep="$sep" '
    function flush() {
      if (!in_package) return
      if (name == "" || version == "") { broken = 1; return }
      print name sep version sep source
    }
    /^[[:space:]]*\[/ {
      flush()
      in_package = ($0 == "[[package]]")
      if (!in_package && $0 ~ /package/) broken = 1
      name = ""; version = ""; source = ""
      next
    }
    in_package && /^[[:space:]]*(name|version|source)[[:space:]]*=/ {
      if ($0 !~ /^(name|version|source) = "[^"]*"$/) { broken = 1; next }
      key = $0; sub(/ = .*$/, "", key)
      value = $0; sub(/^[a-z]+ = "/, "", value); sub(/"$/, "", value)
      if (key == "name") name = value
      else if (key == "version") version = value
      else source = value
    }
    END { flush(); exit (broken ? 3 : 0) }
  ' <<<"$lock" | LC_ALL=C sort -u
}

# 2 つの版の一覧(`packages_of` の出力)を比べ、後の一覧にだけある行を出す。
#
# $1 前の一覧
# $2 後の一覧
packages_only_in_latter_of() {
  LC_ALL=C comm -13 <(printf '%s\n' "$1") <(printf '%s\n' "$2") | awk 'NF'
}

# エポック秒を UTC の `YYYY-MM-DDTHH:MM:SSZ` で出す。
#
# $1 エポック秒
utc_time_of() {
  jq -rn --argjson at "$1" '$at | todate'
}

commits="$(git rev-list --reverse "$base..$head" --)" || undecidable "$base..$head のコミットを辿れない"
commit_count=0
# 範囲で足した版の、足したコミットごとの記録。1 行に `<name>`・`<version>`・`<source>`・`<committer の時刻>`・`<コミット>` を区切りでつなぐ。
additions=""
for commit in $commits; do
  commit_count=$((commit_count + 1))

  changed_paths="$(git diff-tree -r --root -m --no-commit-id --name-only "$commit")" ||
    undecidable "$commit で変えたファイルを読めない"
  if grep -q '/Cargo\.lock$' <<<"$changed_paths"; then
    undecidable "$commit がルート以外の Cargo.lock を変えている(ルートの Cargo.lock だけを確かめるので止める)"
  fi

  # Why not(`git rev-list -- Cargo.lock` で lock を変えたコミットだけを拾う): 既定の履歴の簡略化で、マージの lock が
  # 2 つ目の親と同じときに 1 つ目の親の側を辿らず、先に足したコミットを取りこぼして遅い時刻で見る。
  parent="$(git rev-parse -q --verify "$commit^1")" || parent=""
  lock_blob="$(git rev-parse -q --verify "$commit:Cargo.lock")" || lock_blob=""
  parent_lock_blob=""
  if [ -n "$parent" ]; then
    parent_lock_blob="$(git rev-parse -q --verify "$parent:Cargo.lock")" || parent_lock_blob=""
  fi
  [ "$lock_blob" = "$parent_lock_blob" ] && continue

  packages="$(packages_of "$commit")" || undecidable "$commit の Cargo.lock の [[package]] を読めない"
  parent_packages=""
  if [ -n "$parent" ]; then
    parent_packages="$(packages_of "$parent")" || undecidable "$parent の Cargo.lock の [[package]] を読めない"
  fi
  # Why(committer の時刻): author の時刻は `--amend` や squash で古い値が残り、後から正しく足した版を落とす。
  committed_at="$(git show -s --format=%ct "$commit")" || undecidable "$commit の committer の時刻を読めない"
  while IFS= read -r package; do
    [ -n "$package" ] || continue
    additions+="$package$sep$committed_at$sep$commit"$'\n'
  done <<<"$(packages_only_in_latter_of "$parent_packages" "$packages")"
done

to_check=""
if [ -n "$additions" ]; then
  earliest_additions="$(printf '%s' "$additions" | LC_ALL=C sort -t "$sep" -k1,1 -k2,2 -k3,3 -k4,4n |
    awk -F "$sep" '!seen[$1 FS $2 FS $3]++')"
  head_packages="$(packages_of "$head")" || undecidable "$head の Cargo.lock の [[package]] を読めない"
  base_packages="$(packages_of "$base")" || undecidable "$base の Cargo.lock の [[package]] を読めない"
  to_check="$(awk -F "$sep" 'NR == FNR { wanted[$0]; next } ($1 FS $2 FS $3) in wanted' \
    <(packages_only_in_latter_of "$base_packages" "$head_packages"; echo) <(printf '%s\n' "$earliest_additions"))"
fi

# crates.io の版だけを残す。git と path の版は公開の時刻を持たないので飛ばす。
crates_io_additions=""
while IFS="$sep" read -r name version source added_at commit; do
  [ -n "$name" ] || continue
  case "$source" in
    "$crates_io_source") crates_io_additions+="$name$sep$version$sep$added_at$sep$commit"$'\n' ;;
    git+* | "") ;;
    *) undecidable "$name $version の source '$source' は crates.io 以外の registry で、公開の時刻を読む先が無い" ;;
  esac
done <<<"$to_check"

checked=0
young=0
index_crate=""
index_lines=""
while IFS="$sep" read -r name version added_at commit; do
  [ -n "$name" ] || continue
  if [ "$name" != "$index_crate" ]; then
    index_lines="$(index_lines_of "$index_url" "$name")" || undecidable "$name の版の一覧を $index_url から読めない"
    index_crate="$name"
  fi
  published="$(published_at_of "$index_lines" "$version")"
  case "$?" in
    0) ;;
    1) undecidable "$name の版の一覧を JSON として読めない" ;;
    2) undecidable "$name $version が index に無い" ;;
    *) undecidable "$name $version の pubtime が無い・読めない" ;;
  esac
  IFS=$'\t' read -r published_at pubtime <<<"$published"
  checked=$((checked + 1))
  usable_from=$((published_at + min_days * seconds_per_day))
  [ "$added_at" -lt "$usable_from" ] || continue
  echo "lock-publish-age: $name $version は $pubtime の公開で、足したコミット $commit（$(utc_time_of "$added_at")）の時点で $min_days 日経っていない"
  young=$((young + 1))
done <<<"$crates_io_additions"

echo "lock-publish-age: ${base:0:12}..${head:0:12} の $commit_count コミットを見て、足した版 $checked 件を確かめた"
[ "$young" -eq 0 ] || exit 1
