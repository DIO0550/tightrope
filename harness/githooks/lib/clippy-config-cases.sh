#!/usr/bin/env bash
#
# clippy の設定(根と crate ごとの clippy.toml・workspace の lint)の判定表。
#
# 実物の設定ファイル(根の Cargo.toml / Cargo.lock、根と各 crate の clippy.toml / .clippy.toml、各 crate の
# Cargo.toml)だけを写した workspace を使い捨ての置き場に組み、crate のディレクトリをカレントにして
# `rust-checks.sh clippy` を crate ごとに 2 回走らせる。各 crate の src/lib.rs は空で、実物のソースは写さない。
#   probe の run  下の probe の表の項目を 1 つずつ使う src/probe_<nn>.rs と、src/inner/mod.rs と、テストの外で
#                 unwrap() / expect() を使う src/panics_outside_tests.rs を置く。
#                 1 回の run に禁止を同居させるので終了コードでは照らさず、clippy の出力の見出し(`-->` が指す
#                 ファイルと、その直前の error / warning の行の組)で照らす(T1・T2・T4・T5・T7・T11・T12)
#   例外の run    テストの中の unwrap() / expect() と、統合テストが `mod common;` で使う tests/common/mod.rs を
#                 置き、終了コードで照らす(T6)。食い違ったら、その run の error の行も出す
# T3 と T10 は実物の crate で clippy が読む設定ファイルを、T3 は根の clippy.toml の設定行と、T10 は
# disallowed-methods / disallowed-types に並ぶ項目を probe の表の項目と照らす。T1 が probe の表の項目の欠けを、
# T10 が余分と欠けの両方を落とす。T8 は実物の crates/ を照らす。T9 は probe の表のケースが走ったかを見る。
#
# crate の一覧は実物の crates/*/Cargo.toml から 1 回だけ作り、workspace を置くのにも、run とケースを crate ごとに
# 回すのにも使う。
# I/O を持ってよい crate は io_crates に列挙したものだけで、crates/ のそれ以外はすべて I/O を持たない側として
# 照らす。一覧に無い crate は落ちる側を期待されるので、漏れは安全側に倒れる。
#
# macOS の /bin/bash(3.2)でも走るよう、連想配列など bash 4 以降の機能は使わない。
#
# 使い方: bash harness/githooks/lib/clippy-config-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$here/../../.." && pwd -P)"
script="$here/rust-checks.sh"

source "$here/../../../.claude/hooks/lib/cases-report.sh"
source "$here/../../../.claude/hooks/lib/cases-fixtures.sh"

work="$(make_crate_workdir)" || exit 1
trap 'rm -rf "$work"' EXIT

# CI は CARGO_TERM_COLOR=always を渡す。色が付くと見出しの行が `error` / `warning` で始まらず、照合が外れる。
export CARGO_TERM_COLOR=never
export CARGO_TARGET_DIR="$work/target"

# I/O を持ってよい crate。
io_crates=(infrastructure tightrope)

# 実物の crates/ にある crate の名前。
crate_names=()
for manifest in "$repository_root"/crates/*/Cargo.toml; do
  crate_names+=("$(basename "$(dirname "$manifest")")")
done

# clippy が読む設定ファイルの名前。両方あれば clippy は先の名前を読む。
config_names=(.clippy.toml clippy.toml)

# probe の表。1 行 1 項目で `<禁止する項目>|<それを使う関数 1 行>`。
probe_items=()
probe_bodies=()
while IFS='|' read -r item body; do
  probe_items+=("$item")
  probe_bodies+=("$body")
done <<'PROBES'
std::fs::read|pub fn probe() -> std::io::Result<Vec<u8>> { std::fs::read("probe") }
std::fs::read_to_string|pub fn probe() -> std::io::Result<String> { std::fs::read_to_string("probe") }
std::fs::write|pub fn probe() -> std::io::Result<()> { std::fs::write("probe", "x") }
std::fs::remove_file|pub fn probe() -> std::io::Result<()> { std::fs::remove_file("probe") }
std::fs::metadata|pub fn probe() -> bool { std::fs::metadata("probe").is_ok() }
std::fs::symlink_metadata|pub fn probe() -> bool { std::fs::symlink_metadata("probe").is_ok() }
std::fs::rename|pub fn probe() -> std::io::Result<()> { std::fs::rename("a", "b") }
std::fs::copy|pub fn probe() -> std::io::Result<u64> { std::fs::copy("a", "b") }
std::fs::hard_link|pub fn probe() -> std::io::Result<()> { std::fs::hard_link("a", "b") }
std::fs::soft_link|pub fn probe() -> std::io::Result<()> { std::fs::soft_link("a", "b") }
std::fs::read_link|pub fn probe() -> bool { std::fs::read_link("probe").is_ok() }
std::fs::canonicalize|pub fn probe() -> bool { std::fs::canonicalize("probe").is_ok() }
std::fs::create_dir|pub fn probe() -> std::io::Result<()> { std::fs::create_dir("probe") }
std::fs::create_dir_all|pub fn probe() -> std::io::Result<()> { std::fs::create_dir_all("probe") }
std::fs::remove_dir|pub fn probe() -> std::io::Result<()> { std::fs::remove_dir("probe") }
std::fs::remove_dir_all|pub fn probe() -> std::io::Result<()> { std::fs::remove_dir_all("probe") }
std::fs::read_dir|pub fn probe() -> bool { std::fs::read_dir("probe").is_ok() }
std::fs::set_permissions|pub fn probe(p: std::fs::Permissions) -> std::io::Result<()> { std::fs::set_permissions("probe", p) }
std::fs::exists|pub fn probe() -> std::io::Result<bool> { std::fs::exists("probe") }
std::path::Path::metadata|pub fn probe(p: &std::path::Path) -> bool { p.metadata().is_ok() }
std::path::Path::symlink_metadata|pub fn probe(p: &std::path::Path) -> bool { p.symlink_metadata().is_ok() }
std::path::Path::canonicalize|pub fn probe(p: &std::path::Path) -> bool { p.canonicalize().is_ok() }
std::path::Path::read_link|pub fn probe(p: &std::path::Path) -> bool { p.read_link().is_ok() }
std::path::Path::read_dir|pub fn probe(p: &std::path::Path) -> bool { p.read_dir().is_ok() }
std::path::Path::exists|pub fn probe(p: &std::path::Path) -> bool { p.exists() }
std::path::Path::try_exists|pub fn probe(p: &std::path::Path) -> bool { p.try_exists().is_ok() }
std::path::Path::is_file|pub fn probe(p: &std::path::Path) -> bool { p.is_file() }
std::path::Path::is_dir|pub fn probe(p: &std::path::Path) -> bool { p.is_dir() }
std::path::Path::is_symlink|pub fn probe(p: &std::path::Path) -> bool { p.is_symlink() }
std::os::unix::fs::symlink|pub fn probe() -> std::io::Result<()> { std::os::unix::fs::symlink("a", "b") }
std::os::unix::fs::chown|pub fn probe() -> std::io::Result<()> { std::os::unix::fs::chown("a", None, None) }
std::os::unix::fs::fchown|pub fn probe(fd: std::os::fd::BorrowedFd<'_>) -> std::io::Result<()> { std::os::unix::fs::fchown(fd, None, None) }
std::os::unix::fs::lchown|pub fn probe() -> std::io::Result<()> { std::os::unix::fs::lchown("a", None, None) }
std::os::unix::fs::chroot|pub fn probe() -> std::io::Result<()> { std::os::unix::fs::chroot("a") }
std::fs::File|pub fn probe() -> bool { std::fs::File::open("probe").is_ok() }
std::fs::OpenOptions|pub fn probe() -> bool { std::fs::OpenOptions::new().read(true).open("probe").is_ok() }
std::fs::DirBuilder|pub fn probe() -> std::io::Result<()> { std::fs::DirBuilder::new().create("probe") }
std::fs::ReadDir|pub fn probe(_: std::fs::ReadDir) {}
std::fs::DirEntry|pub fn probe(_: std::fs::DirEntry) {}
std::fs::Metadata|pub fn probe(_: std::fs::Metadata) {}
std::fs::FileType|pub fn probe(_: std::fs::FileType) {}
std::fs::Permissions|pub fn probe(_: std::fs::Permissions) {}
std::fs::FileTimes|pub fn probe() -> std::fs::FileTimes { std::fs::FileTimes::new() }
std::fs::TryLockError|pub fn probe(_: std::fs::TryLockError) {}
std::process::Command|pub fn probe() -> bool { std::process::Command::new("git").status().is_ok() }
PROBES

# crate が I/O を持ってよい側(io_crates)に入っているか。
#
# $1 crate の名前
allows_io() {
  local io_crate
  for io_crate in "${io_crates[@]}"; do
    [ "$io_crate" = "$1" ] && return 0
  done
  return 1
}

# ディレクトリにある clippy の設定ファイルを、別のディレクトリへ写す。無い名前は飛ばす。
#
# $1 写す元のディレクトリ
# $2 写す先のディレクトリ
copy_configs() {
  local name
  for name in "${config_names[@]}"; do
    [ -f "$1/$name" ] || continue
    cp "$1/$name" "$2/" || return 1
  done
}

# 実物の設定ファイルだけを写した workspace を、crate_names の crate ごとに置く。各 crate の src/lib.rs は空。
# manifest と lock は実物のままなので `--locked` で通る。
#
# $1 置き場のディレクトリ
place_workspace() {
  local workspace="$1" crate
  mkdir -p "$workspace" || return 1
  cp "$repository_root/Cargo.toml" "$repository_root/Cargo.lock" "$workspace/" || return 1
  copy_configs "$repository_root" "$workspace" || return 1
  for crate in "${crate_names[@]}"; do
    mkdir -p "$workspace/crates/$crate/src" || return 1
    cp "$repository_root/crates/$crate/Cargo.toml" "$workspace/crates/$crate/" || return 1
    copy_configs "$repository_root/crates/$crate" "$workspace/crates/$crate" || return 1
    : >"$workspace/crates/$crate/src/lib.rs"
  done
}

# probe の表の項目を置くモジュールの名前を出す。
#
# $1 probe の表の添字
probe_module_of() {
  printf 'probe_%02d' "$1"
}

# probe の run のソースを置く。probe の表の項目を 1 つずつ src/probe_<nn>.rs に置き、src/inner/mod.rs と
# src/panics_outside_tests.rs(`#[cfg(test)]` の外の関数で unwrap() / expect() を使う)と合わせて src/lib.rs から読む。
#
# $1 crate のディレクトリ
place_probe_sources() {
  local crate_dir="$1" index module
  : >"$crate_dir/src/lib.rs"
  for index in "${!probe_items[@]}"; do
    module="$(probe_module_of "$index")"
    printf 'pub mod %s;\n' "$module" >>"$crate_dir/src/lib.rs"
    printf '%s\n' "${probe_bodies[$index]}" >"$crate_dir/src/$module.rs"
  done
  mkdir -p "$crate_dir/src/inner" || return 1
  printf 'pub fn inner() {}\n' >"$crate_dir/src/inner/mod.rs"
  printf 'pub mod inner;\n' >>"$crate_dir/src/lib.rs"
  cat >"$crate_dir/src/panics_outside_tests.rs" <<'EOF'
pub fn unwrapped() -> i32 {
    "1".parse::<i32>().unwrap()
}

pub fn expected() -> i32 {
    "1".parse::<i32>().expect("1 は数")
}
EOF
  printf 'pub mod panics_outside_tests;\n' >>"$crate_dir/src/lib.rs"
}

# 例外の run のソースを置く。src/lib.rs のテストの中で unwrap() / expect() を使い、統合テスト tests/probe.rs が
# `mod common;` で tests/common/mod.rs を読む。
#
# $1 crate のディレクトリ
place_exception_sources() {
  local crate_dir="$1"
  cat >"$crate_dir/src/lib.rs" <<'EOF'
#[cfg(test)]
mod tests {
    fn parsed() -> Result<i32, std::num::ParseIntError> {
        "1".parse()
    }

    #[test]
    fn unwrap_and_expect() {
        assert_eq!(parsed().unwrap(), parsed().expect("1 は数"));
    }
}
EOF
  mkdir -p "$crate_dir/tests/common" || return 1
  cat >"$crate_dir/tests/common/mod.rs" <<'EOF'
pub fn one() -> i32 {
    1
}
EOF
  cat >"$crate_dir/tests/probe.rs" <<'EOF'
mod common;

#[test]
fn one() {
    assert_eq!(common::one(), 1);
}
EOF
}

# crate のソースとテストを消し、空の src/lib.rs だけに戻す。後の run(依存先として lint される crate を含む)へ残さない。
#
# $1 crate のディレクトリ
clear_sources() {
  rm -rf "$1/src" "$1/tests" || return 1
  mkdir -p "$1/src" || return 1
  : >"$1/src/lib.rs"
}

# crate のディレクトリをカレントにして clippy を走らせ、標準出力と標準エラーをまとめてファイルに書く。
# 終了コードは検査のもの。
#
# $1 crate のディレクトリ
# $2 出力を書くファイル
clippy_in() {
  (cd "$1" && bash "$script" clippy) >"$2" 2>&1
}

# clippy の出力から、`-->` の行ごとに、それが指すファイル(`:行:列` を除く)と直前の error / warning の見出しを
# `<ファイル><タブ><見出し>` の 1 行にして出す。1 つのファイルの別の箇所が同じ見出しで報告されるので、重複は除く。
#
# $1 clippy の出力を書いたファイル
headings_of() {
  awk '
    /^(error|warning)/ { heading = $0; next }
    /^ *--> / && heading != "" {
      file = $2
      sub(/:[0-9]+:[0-9]+$/, "", file)
      print file "\t" heading
      heading = ""
    }
  ' "$1" | sort -u
}

# 見出しの一覧に、そのファイルを指し、渡した綴りで始まる見出しがあるか。
#
# $1 見出しの一覧(`headings_of` の出力)を書いたファイル
# $2 見出しが指すファイル
# $3 見出しの始まりの綴り
has_heading() {
  awk -F '\t' -v file="$2" -v start="$3" '
    {
      is_wanted_heading = ($1 == file && index($2, start) == 1)
      if (is_wanted_heading) found = 1
    }
    END { exit !found }
  ' "$1"
}

# probe のファイルを指す見出しに、その項目の名前で禁止を報告するもの(``use of a disallowed (method|type) `<項目>` ``)が
# あれば `deny`、無ければ `pass` を判定として出す。1 つの probe のファイルに別の項目の見出しが混ざることがあるので、
# 件数ではなく項目の名前で照らす。
#
# $1 見出しの一覧を書いたファイル
# $2 probe のファイル(workspace の根からの相対パス)
# $3 禁止する項目
probe_decision_of() {
  local kind
  for kind in method type; do
    has_heading "$1" "$2" "error: use of a disallowed $kind \`$3\`" || continue
    echo deny
    return 0
  done
  echo pass
}

# 見出しの一覧に、そのファイルを指し、渡した綴りで始まる見出しがあれば `deny`、無ければ `pass` を判定として出す。
#
# $1 見出しの一覧を書いたファイル
# $2 見出しが指すファイル(workspace の根からの相対パス)
# $3 見出しの始まりの綴り
heading_decision_of() {
  if has_heading "$1" "$2" "$3"; then
    echo deny
    return 0
  fi
  echo pass
}

# 件数を、0 なら `なし`、それ以外なら `<件数>件` にして出す。
#
# $1 件数
count_label_of() {
  if [ "$1" -eq 0 ]; then
    echo なし
    return 0
  fi
  echo "$1件"
}

# 見出しの一覧のうち、clippy.toml / .clippy.toml を指すものの件数を出す。
#
# $1 見出しの一覧を書いたファイル
config_heading_count_of() {
  awk -F '\t' '$1 ~ /clippy\.toml$/' "$1" | wc -l
}

# 見出しの一覧のうち、禁止した項目の使用を報告するもの(`use of a disallowed`)の件数を出す。
#
# $1 見出しの一覧を書いたファイル
disallowed_heading_count_of() {
  awk -F '\t' 'index($2, "use of a disallowed ") > 0' "$1" | wc -l
}

# clippy の出力にあるコンパイルエラー(`error[E`)の件数を出す。
#
# $1 clippy の出力を書いたファイル
compile_error_count_of() {
  grep -c '^error\[E' "$1"
}

# crate の clippy の設定ファイル(config_names)のうち、clippy が読むもののパスを出す。無ければ何も出さない。
#
# $1 crate のディレクトリ
read_config_of() {
  local name
  for name in "${config_names[@]}"; do
    [ -f "$1/$name" ] || continue
    echo "$1/$name"
    return 0
  done
}

# crate で clippy が読む設定ファイルが、根の clippy.toml の設定行(コメントと空行を除く)をすべて同じ綴りで含むかを、
# `写してある` / `写し漏れ` で出す。設定ファイルが無ければ `写し漏れ`。
#
# $1 crate のディレクトリ
root_settings_state_of() {
  local config line
  config="$(read_config_of "$1")"
  if [ -z "$config" ]; then
    echo 写し漏れ
    return 0
  fi
  while IFS= read -r line; do
    grep -qxF -- "$line" "$config" && continue
    echo 写し漏れ
    return 0
  done < <(grep -vE '^[[:space:]]*(#|$)' "$repository_root/clippy.toml")
  echo 写してある
}

# 設定ファイルの disallowed-methods / disallowed-types の配列に並ぶ項目を、1 行 1 つ、並べ替えて重複を除いて出す。
# 項目は文字列のままの path と、`{ path = "<path>", .. }` の path。行を前から、`<キー> = "<文字列>"`・`"<文字列>"`・
# `]`・`#` の順に読み、`path` 以外のキーの文字列(reason など)は飛ばし、文字列の外の `]` で配列の終わり、`#` で行の
# 終わりと読む。
#
# $1 設定ファイル
disallowed_items_of() {
  awk '
    /^[[:space:]]*disallowed[-_](methods|types)[[:space:]]*=[[:space:]]*\[/ { inside = 1; sub(/^[^[]*\[/, "") }
    !inside { next }
    {
      line = $0
      while (match(line, /[A-Za-z_-]+[[:space:]]*=[[:space:]]*"([^"\\]|\\.)*"|"([^"\\]|\\.)*"|[]]|#/)) {
        token = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        if (token == "]") {
          inside = 0
          break
        }
        if (token == "#") break
        if (token ~ /^"/) {
          print substr(token, 2, length(token) - 2)
          continue
        }
        if (token !~ /^path[[:space:]]*=/) continue
        sub(/^[^"]*"/, "", token)
        print substr(token, 1, length(token) - 1)
      }
    }
  ' "$1" | LC_ALL=C sort -u
}

# probe の表の項目を、1 行 1 つ、並べ替えて重複を除いて出す。
probe_item_set() {
  printf '%s\n' "${probe_items[@]}" | LC_ALL=C sort -u
}

# 設定ファイルの disallowed-methods / disallowed-types に並ぶ項目と probe の表の項目との食い違いを、probe の表に無い
# 項目は `余分 <項目>`、設定ファイルに無い項目は `欠け <項目>` の 1 行ずつで出す。食い違いが無ければ何も出さない。
#
# $1 設定ファイル
listing_differences_of() {
  LC_ALL=C comm -23 <(disallowed_items_of "$1") <(probe_item_set) | sed 's/^/余分 /'
  LC_ALL=C comm -13 <(disallowed_items_of "$1") <(probe_item_set) | sed 's/^/欠け /'
}

# crate で clippy が読む設定ファイルの disallowed-methods / disallowed-types に並ぶ項目が、probe の表の項目と
# 過不足なく同じかを、`一致` / `食い違う` / `設定ファイルが無い` で出す。
#
# $1 crate のディレクトリ
listing_state_of() {
  local config
  config="$(read_config_of "$1")"
  if [ -z "$config" ]; then
    echo 設定ファイルが無い
    return 0
  fi
  if [ -n "$(listing_differences_of "$config")" ]; then
    echo 食い違う
    return 0
  fi
  echo 一致
}

workspace="$work/workspace"
place_workspace "$workspace" || exit 1

# 例外の run の終了コード(crate_names と同じ添字)。
exception_run_statuses=()
for crate in "${crate_names[@]}"; do
  crate_dir="$workspace/crates/$crate"
  place_probe_sources "$crate_dir" || exit 1
  clippy_in "$crate_dir" "$work/probe.$crate.out"
  headings_of "$work/probe.$crate.out" >"$work/probe.$crate.headings"
  clear_sources "$crate_dir" || exit 1

  place_exception_sources "$crate_dir" || exit 1
  status=0
  clippy_in "$crate_dir" "$work/exception.$crate.out" || status=$?
  exception_run_statuses+=("$status")
  clear_sources "$crate_dir" || exit 1
done

cases_before=$cases_reported
for crate in "${crate_names[@]}"; do
  allows_io "$crate" && continue
  for index in "${!probe_items[@]}"; do
    probe_file="crates/$crate/src/$(probe_module_of "$index").rs"
    report deny "$(probe_decision_of "$work/probe.$crate.headings" "$probe_file" "${probe_items[$index]}")" \
      "T1 I/O を持たない $crate で ${probe_items[$index]} を使うと clippy が落ち、その項目の名前で報告する"
  done
done
report_cases_ran PROBES "$cases_before"

for index in "${!crate_names[@]}"; do
  crate="${crate_names[$index]}"
  headings="$work/probe.$crate.headings"
  report deny "$(heading_decision_of "$headings" "crates/$crate/src/inner/mod.rs" 'error: `mod.rs` files are not allowed')" \
    "T2 $crate で src/inner/mod.rs を置くと clippy が落ちる"
  report deny "$(heading_decision_of "$headings" "crates/$crate/src/panics_outside_tests.rs" 'error: used `unwrap()`')" \
    "T11 $crate の本番コード(#[cfg(test)] の外)で unwrap() を使うと clippy が落ちる"
  report deny "$(heading_decision_of "$headings" "crates/$crate/src/panics_outside_tests.rs" 'error: used `expect()`')" \
    "T12 $crate の本番コード(#[cfg(test)] の外)で expect() を使うと clippy が落ちる"
  report なし "$(count_label_of "$(config_heading_count_of "$headings")")" \
    "T4 $crate の probe の run で、clippy.toml を指す警告が出ない"
  report なし "$(count_label_of "$(compile_error_count_of "$work/probe.$crate.out")")" \
    "T5 $crate の probe の run で、probe のコンパイルエラーが出ない"
  if allows_io "$crate"; then
    report なし "$(count_label_of "$(disallowed_heading_count_of "$headings")")" \
      "T7 I/O を持ってよい $crate では、probe の表の項目をすべて使っても禁止の見出しが出ない"
  fi

  exception_result=pass
  [ "${exception_run_statuses[$index]}" -eq 0 ] || exception_result=fail
  report pass "$exception_result" \
    "T6 $crate で、テストの中の unwrap() / expect() と、統合テストの tests/common/mod.rs では clippy が落ちない"
  [ "$exception_result" = pass ] && continue
  grep '^error' "$work/exception.$crate.out" | sort -u | sed 's/^/       /'
done

for crate in "${crate_names[@]}"; do
  allows_io "$crate" && continue
  crate_dir="$repository_root/crates/$crate"
  report 写してある "$(root_settings_state_of "$crate_dir")" \
    "T3 I/O を持たない $crate の clippy.toml(または .clippy.toml)が、根の clippy.toml の設定行をすべて含む"

  listing_state="$(listing_state_of "$crate_dir")"
  report 一致 "$listing_state" \
    "T10 I/O を持たない $crate の clippy.toml(または .clippy.toml)の disallowed-methods / disallowed-types が、probe の表の項目と過不足なく同じ"
  [ "$listing_state" = 食い違う ] || continue
  listing_differences_of "$(read_config_of "$crate_dir")" | sed 's/^/       /'
done

for crate in "${io_crates[@]}"; do
  crate_presence=ない
  [ -f "$repository_root/crates/$crate/Cargo.toml" ] && crate_presence=ある
  report ある "$crate_presence" "T8 列挙した $crate が crates/ にある"
done

exit "$cases_failed"
