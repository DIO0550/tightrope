#!/usr/bin/env bash
#
# infrastructure の driver の外の I/O の検査(`io-outside-driver.sh`)の判定表。
#
# ケースごとに使い捨ての workspace を `$work/<ケース名>` に組み、根を引数に渡して、本物の cargo で検査を走らせる
# (`run_with_case_root`)。target もケースごとに `$work/<ケース名>/target` に分ける(`with_case_target`)。基準の
# workspace(`place_case_tree`)は `place_member` で置いた domain と infrastructure の 2 つの crate を持ち、domain には
# 実物の `crates/domain/clippy.toml` を写す。infrastructure は driver.rs に I/O の呼び出しを 1 つ、translation.rs に
# I/O でないメソッドの呼び出しを 1 つ持つ。Cargo.lock は `place_lockfile` で置き、Cargo.toml を書き換えたケースは
# 置き直す。多くのケースは translation.rs の 5 行目に I/O の呼び出しを 1 つ足し(`place_control`)、その 1 行だけが
# 報告される(`control_line`)かで照らす。I/O を呼ぶ関数とテストは `append_io_function` / `append_io_test` で足す。
# 1 ケースの判定の綴りと照らし方は `cases-allowlist.sh` の `decision_of`。U1〜U8 は、検査できなかった理由が
# 標準エラーに出るかまで照らす(`cases-allowlist.sh` の `run_unavailable_case`)。M1〜M4 は見ない形で、M1〜M3 は
# 何も報告されない(`miss`)こと、M4 は対照の 1 行だけが報告されることを照らす。
# 走らせ方の例外は 4 つ。E6 は別のディレクトリから相対の根を渡し、U4 は根を 2 つ、U5 は空の根、U7 は無い根を渡す。
# 上の 4 つのほかに、E10 も別のディレクトリから相対の根を渡すが、`./` を付けず、根の親を `CDPATH` に入れて渡す。
# U8 は `run_with_case_root` に渡す PATH で、検査を走らせるコマンドにだけ失敗する awk(`failing_awk_path_prefix`)を先に置く。
# C1 は検査を走らせず、`io-outside-driver.sh` と `folder-deps.sh` の本文のヒアドキュメントを読んで照らす。
#
# 使い方: bash harness/githooks/lib/io-outside-driver-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$here/../../.." && pwd)"
script="$here/io-outside-driver.sh"

source "$repo_root/.claude/hooks/lib/cases-report.sh"
source "$repo_root/.claude/hooks/lib/cases-fixtures.sh"
source "$here/cases-allowlist.sh"

work="$(make_crate_workdir)" || exit 1
trap 'rm -rf "$work"' EXIT

# 検査が違反を報告するときの見出し。
heading='^infrastructure の driver の外で I/O を使っています'

# `place_control` が足す I/O の呼び出しを報告する行。
control_line='crates/infrastructure/src/translation.rs:5: use of a disallowed method `std::path::Path::is_dir`'

# ケースの workspace の infrastructure の crate のディレクトリを出す。
#
# $1 ケース名
infrastructure_dir_of() {
  printf '%s/%s/crates/infrastructure' "$work" "$1"
}

# ファイルの末尾に、`&Path` にメソッドを呼ぶ関数 `here` を足す(ファイルが無ければ作る)。呼び出しは足した 2 行目。
#
# $1 ファイルのパス
# $2 呼ぶメソッド
append_io_function() {
  printf 'pub fn here(p: &std::path::Path) -> bool {\n    p.%s()\n}\n' "$2" >>"$1"
}

# ファイルの末尾に、`Path` にメソッドを呼ぶテスト `here` を足す(ファイルが無ければ作る)。呼び出しは足した 3 行目。
#
# $1 ファイルのパス
# $2 呼ぶメソッド
append_io_test() {
  printf '#[test]\nfn here() {\n    assert!(!std::path::Path::new("x").%s());\n}\n' "$2" >>"$1"
}

# ケースの workspace に基準の木を置く。根は `members = ["crates/*"]`、domain は `place_member` の crate に実物の
# `crates/domain/clippy.toml` を足したもの、infrastructure は `place_member` の crate の src を、`pub mod driver;` /
# `pub mod translation;` だけの lib.rs、`Path::exists` を呼ぶ driver.rs、`Path::extension` を呼ぶ 3 行の translation.rs
# で上書きしたもの。最後に Cargo.lock を置く。
#
# $1 ケース名
place_case_tree() {
  local tree="$work/$1" infrastructure
  infrastructure="$(infrastructure_dir_of "$1")"
  place_member "$tree/crates/domain" domain && place_member "$infrastructure" infrastructure || return 1
  printf '[workspace]\nmembers = ["crates/*"]\nresolver = "3"\n' >"$tree/Cargo.toml"
  cp "$repo_root/crates/domain/clippy.toml" "$tree/crates/domain/clippy.toml" || return 1
  printf 'pub mod driver;\npub mod translation;\n' >"$infrastructure/src/lib.rs"
  : >"$infrastructure/src/driver.rs"
  append_io_function "$infrastructure/src/driver.rs" exists
  printf 'pub fn extension(p: &std::path::Path) -> Option<&std::ffi::OsStr> {\n    p.extension()\n}\n' \
    >"$infrastructure/src/translation.rs"
  place_lockfile "$tree"
}

# ケースの workspace の translation.rs の末尾に行を足す。
#
# $1 ケース名
# $2 足す行
append_translation() {
  printf '%s\n' "$2" >>"$(infrastructure_dir_of "$1")/src/translation.rs"
}

# 基準の translation.rs の末尾に、5 行目で `Path::is_dir` を呼ぶ関数を足す(報告は `control_line`)。
#
# $1 ケース名
place_control() {
  append_translation "$1" $'pub fn control(p: &std::path::Path) -> bool {\n    p.is_dir()\n}'
}

# 基準の木に対照(`place_control`)と、`Path::exists` を呼ぶ別の crate `other`(crates/other)を置く。Cargo.lock は
# 置き直さないので、呼び出し側が依存を足してから `place_lockfile` で置き直す。
#
# $1 ケース名
place_case_tree_with_other() {
  place_case_tree "$1" && place_control "$1" && place_member "$work/$1/crates/other" other || return 1
  append_io_function "$work/$1/crates/other/src/lib.rs" exists
}

# target をケースの workspace の下に置いて、コマンドを走らせる。
#
# $1 ケース名
# $2 以降 走らせるコマンド
with_case_target() {
  local case_name="$1"
  shift
  CARGO_TARGET_DIR="$work/$case_name/target" "$@"
}

# ケースの workspace の根を引数に渡して、検査を走らせる。
#
# $1 ケース名
# $2 以降 検査に渡す環境変数(`<名前>=<値>`。省くと何も足さない)
run_with_case_root() {
  local case_name="$1"
  shift
  with_case_target "$case_name" env "$@" bash "$script" "$work/$case_name"
}

place_case_tree P1 || exit 1
run_case pass '' 'P1 基準の木では何も出さずに exit 0' run_with_case_root P1

place_case_tree P2 && place_control P2 || exit 1
mkdir -p "$(infrastructure_dir_of P2)/src/driver/a" || exit 1
printf '\npub mod a;\n' >>"$(infrastructure_dir_of P2)/src/driver.rs"
printf 'pub mod b;\n' >"$(infrastructure_dir_of P2)/src/driver/a.rs"
append_io_function "$(infrastructure_dir_of P2)/src/driver/a/b.rs" is_file
run_case deny "$control_line" 'P2 driver の下の深いファイル(src/driver/a/b.rs)の I/O は報告しない' run_with_case_root P2

place_case_tree P3 && place_control P3 || exit 1
mkdir -p "$(infrastructure_dir_of P3)/src/driver" || exit 1
printf '\n#[cfg(test)]\nmod tests;\n' >>"$(infrastructure_dir_of P3)/src/driver.rs"
append_io_test "$(infrastructure_dir_of P3)/src/driver/tests.rs" is_file
run_case deny "$control_line" 'P3 driver の単体テスト(src/driver/tests.rs)の I/O は報告しない' run_with_case_root P3

place_case_tree P4 && place_control P4 || exit 1
mkdir -p "$(infrastructure_dir_of P4)/tests" || exit 1
append_io_test "$(infrastructure_dir_of P4)/tests/r1.rs" is_file
run_case deny "$control_line" 'P4 結合テスト(crates/infrastructure/tests/r1.rs)の I/O は報告しない' run_with_case_root P4

place_case_tree P5 && place_control P5 || exit 1
mv "$work/P5/crates/domain/clippy.toml" "$work/P5/crates/domain/.clippy.toml" || exit 1
run_case deny "$control_line" 'P5 domain が .clippy.toml だけを持つときも、その一覧で照らす' run_with_case_root P5

place_case_tree P6 || exit 1
append_translation P6 $'pub fn unused() {\n    let x = 1;\n}'
run_case pass '' 'P6 禁止の項目でない warning(未使用の変数)だけなら何も出さない' run_with_case_root P6

place_case_tree_with_other P7 && place_lockfile "$work/P7" || exit 1
run_case deny "$control_line" 'P7 infrastructure が依存しない、I/O を持つ別の crate は報告しない' run_with_case_root P7

place_case_tree_with_other P8 || exit 1
printf 'other = { path = "../other" }\n' >>"$(infrastructure_dir_of P8)/Cargo.toml"
place_lockfile "$work/P8" || exit 1
run_case deny "$control_line" 'P8 infrastructure が path で依存する、I/O を持つ crate は報告しない' run_with_case_root P8

place_case_tree D1 || exit 1
append_io_function "$(infrastructure_dir_of D1)/src/translation.rs" exists
run_case deny 'crates/infrastructure/src/translation.rs:5: use of a disallowed method `std::path::Path::exists`' \
  'D1 translation で &Path に exists を呼ぶとその行を報告し、driver.rs の I/O は報告しない' run_with_case_root D1

place_case_tree D2 || exit 1
append_translation D2 $'pub fn listed(p: &std::path::PathBuf) -> bool {\n    p.read_dir().is_ok()\n}'
run_case deny 'crates/infrastructure/src/translation.rs:5: use of a disallowed method `std::path::Path::read_dir`' \
  'D2 &PathBuf に read_dir を呼ぶと Path::read_dir として報告する' run_with_case_root D2

place_case_tree D3 || exit 1
append_translation D3 $'pub fn input() -> bool {\n    std::io::stdin().lines().next().is_some()\n}'
run_case deny 'crates/infrastructure/src/translation.rs:5: use of a disallowed method `std::io::stdin`' \
  'D3 std::io::stdin を呼ぶと報告する' run_with_case_root D3

place_case_tree D4 || exit 1
append_translation D4 $'pub fn shown() {\n    println!("x");\n}'
run_case deny 'crates/infrastructure/src/translation.rs:5: use of a disallowed macro `std::println`' \
  'D4 println! を呼ぶと報告する' run_with_case_root D4

place_case_tree D5 || exit 1
append_translation D5 $'pub fn home() -> bool {\n    std::env::var("HOME").is_ok()\n}'
run_case deny 'crates/infrastructure/src/translation.rs:5: use of a disallowed method `std::env::var`' \
  'D5 std::env::var を呼ぶと報告する' run_with_case_root D5

place_case_tree D6 || exit 1
append_translation D6 $'pub fn connected() -> bool {\n    std::net::TcpStream::connect("127.0.0.1:9").is_ok()\n}'
run_case deny 'crates/infrastructure/src/translation.rs:5: use of a disallowed type `std::net::TcpStream`' \
  'D6 std::net::TcpStream を使うと報告する' run_with_case_root D6

place_case_tree D7 || exit 1
printf 'pub mod adapter;\n' >>"$(infrastructure_dir_of D7)/src/lib.rs"
printf 'use std::io::*;\n\npub fn flushed() -> Result<()> {\n    stdout().flush()\n}\n' >"$(infrastructure_dir_of D7)/src/adapter.rs"
run_case deny 'crates/infrastructure/src/adapter.rs:4: use of a disallowed method `std::io::stdout`' \
  'D7 adapter で use std::io::*; の後に stdout() を呼ぶと報告する' run_with_case_root D7

place_case_tree D8 || exit 1
append_io_function "$(infrastructure_dir_of D8)/src/lib.rs" is_file
run_case deny 'crates/infrastructure/src/lib.rs:4: use of a disallowed method `std::path::Path::is_file`' \
  'D8 crate の根(lib.rs)の I/O を報告する' run_with_case_root D8

place_case_tree D9 || exit 1
append_translation D9 $'#[cfg(test)]\nmod tests;'
mkdir -p "$(infrastructure_dir_of D9)/src/translation" || exit 1
append_io_test "$(infrastructure_dir_of D9)/src/translation/tests.rs" exists
run_case deny 'crates/infrastructure/src/translation/tests.rs:3: use of a disallowed method `std::path::Path::exists`' \
  'D9 translation の単体テスト(src/translation/tests.rs)の I/O を報告する' run_with_case_root D9

place_case_tree D10 || exit 1
printf 'pub mod drivers;\n' >>"$(infrastructure_dir_of D10)/src/lib.rs"
mkdir -p "$(infrastructure_dir_of D10)/src/drivers" || exit 1
printf 'pub mod r1;\n' >"$(infrastructure_dir_of D10)/src/drivers.rs"
append_io_function "$(infrastructure_dir_of D10)/src/drivers/r1.rs" exists
run_case deny 'crates/infrastructure/src/drivers/r1.rs:2: use of a disallowed method `std::path::Path::exists`' \
  'D10 driver で始まる別のフォルダ(src/drivers/r1.rs)の I/O を報告する' run_with_case_root D10

place_case_tree D11 || exit 1
append_translation D11 $'pub fn both(p: &std::path::Path, q: &std::path::Path) -> bool {\n    p.exists() && q.exists()\n}'
run_case deny 'crates/infrastructure/src/translation.rs:5: use of a disallowed method `std::path::Path::exists`' \
  'D11 同じ行に同じ項目の呼び出しが 2 つあっても 1 行だけ出す' run_with_case_root D11

place_case_tree E1 && place_control E1 || exit 1
run_case deny "$control_line" 'E1 RUSTFLAGS に --cap-lints allow があっても報告する' \
  run_with_case_root E1 RUSTFLAGS='--cap-lints allow'

place_case_tree E2 && place_control E2 || exit 1
printf '\n[lints.clippy]\nunwrap_used = "deny"\n' >>"$(infrastructure_dir_of E2)/Cargo.toml"
append_translation E2 $'pub fn first(v: &[u8]) -> u8 {\n    *v.first().unwrap()\n}'
place_lockfile "$work/E2" || exit 1
run_case deny "$control_line" \
  'E2 infrastructure の [lints.clippy] で unwrap_used = "deny" にして translation に unwrap があっても、検査できないにならずに I/O だけを報告する' \
  run_with_case_root E2

place_case_tree E3 || exit 1
printf '\n[lints.clippy]\ndisallowed_methods = "allow"\ndisallowed_macros = "allow"\ndisallowed_types = "allow"\n' \
  >>"$(infrastructure_dir_of E3)/Cargo.toml"
place_lockfile "$work/E3" && place_control E3 || exit 1
append_translation E3 $'pub fn shown() {\n    println!("x");\n}\npub fn connected() -> bool {\n    std::net::TcpStream::connect("127.0.0.1:9").is_ok()\n}'
run_case deny "$control_line"$'\ncrates/infrastructure/src/translation.rs:8: use of a disallowed macro `std::println`\ncrates/infrastructure/src/translation.rs:11: use of a disallowed type `std::net::TcpStream`' \
  'E3 [lints.clippy] で disallowed_methods / disallowed_macros / disallowed_types を allow にしても、method・macro・type を 1 件ずつ報告する' \
  run_with_case_root E3

place_case_tree E4 && place_control E4 || exit 1
mkdir -p "$work/E4/empty" || exit 1
run_case deny "$control_line" 'E4 一覧の無いディレクトリを外から CLIPPY_CONF_DIR に渡しても報告する' \
  run_with_case_root E4 CLIPPY_CONF_DIR="$work/E4/empty"

place_case_tree E5 && place_control E5 || exit 1
run_case deny "$control_line" 'E5 CARGO_TERM_COLOR=always でも報告の行が同じ' run_with_case_root E5 CARGO_TERM_COLOR=always

place_case_tree E6 && place_control E6 || exit 1
run_case deny "$control_line" 'E6 別のディレクトリから相対の根(./E6)を渡しても報告する' \
  with_case_target E6 bash -c 'cd "$1" && bash "$2" ./E6' _ "$work" "$script"

place_case_tree E10 && place_control E10 || exit 1
run_case deny "$control_line" 'E10 CDPATH に親を入れて、./ の無い相対の根(E10)を渡しても報告する' \
  with_case_target E10 bash -c 'cd "$1" && CDPATH="$1" bash "$2" E10' _ "$work" "$script"

place_case_tree E7 && place_control E7 || exit 1
run_case deny "$control_line" 'E7 CARGO_ENCODED_RUSTFLAGS に --cap-lints allow があっても報告する' \
  run_with_case_root E7 CARGO_ENCODED_RUSTFLAGS=$'--cap-lints\x1fallow'

place_case_tree E8 && place_control E8 || exit 1
mkdir -p "$work/E8/.cargo" || exit 1
printf '[build]\nrustflags = ["--cap-lints", "allow"]\n' >"$work/E8/.cargo/config.toml"
run_case deny "$control_line" 'E8 根の .cargo/config.toml の [build] rustflags に --cap-lints allow があっても報告する' \
  run_with_case_root E8

place_case_tree E9 && place_control E9 || exit 1
printf '\n[workspace.lints.rust]\nwarnings = "allow"\n' >>"$work/E9/Cargo.toml"
printf '\n[lints]\nworkspace = true\n' >>"$(infrastructure_dir_of E9)/Cargo.toml"
place_lockfile "$work/E9" || exit 1
run_case deny "$control_line" 'E9 [workspace.lints.rust] の warnings = "allow" を継承しても報告する' run_with_case_root E9

place_case_tree U1 || exit 1
rm "$(infrastructure_dir_of U1)/Cargo.toml" || exit 1
run_unavailable_case '^io-outside-driver: .*crates/infrastructure/Cargo.toml がありません$' \
  'U1 crates/infrastructure/Cargo.toml が無いと検査できない' run_with_case_root U1

place_case_tree U2 || exit 1
rm "$work/U2/crates/domain/clippy.toml" || exit 1
run_unavailable_case '^io-outside-driver: .*crates/domain に clippy.toml も .clippy.toml もありません$' \
  'U2 domain に clippy.toml も .clippy.toml も無いと検査できない' run_with_case_root U2

place_case_tree U3 || exit 1
append_translation U3 $'pub fn wrong() -> u8 {\n    "x"\n}'
run_unavailable_case $'error\\[E0308\\]\n^io-outside-driver: clippy が終了コード 101 で終わりました$' \
  'U3 コンパイルできないと検査できない' run_with_case_root U3

place_case_tree U4 || exit 1
run_unavailable_case '^io-outside-driver: 根は 1 つだけ渡してください\(受け取った数: 2\)$' \
  'U4 根を 2 つ渡すと検査できない' with_case_target U4 bash "$script" "$work/U4" "$work/U4"

mkdir -p "$work/U5" || exit 1
run_unavailable_case '^io-outside-driver: 根が空です$' \
  'U5 空の根を渡すと検査できない' bash -c 'cd "$1" && bash "$2" ""' _ "$work/U5" "$script"

place_case_tree U6 && place_control U6 || exit 1
rm "$work/U6/Cargo.lock" || exit 1
run_unavailable_case $'--locked was passed to prevent this\n^io-outside-driver: clippy が終了コード 101 で終わりました$' \
  'U6 Cargo.lock が無いと検査できない' run_with_case_root U6

# ケースの workspace に Cargo.lock があるかを出す。あれば `present`、無ければ `absent`。
#
# $1 ケース名
lock_state_of() {
  if [ -e "$work/$1/Cargo.lock" ]; then
    echo present
    return 0
  fi
  echo absent
}

report absent "$(lock_state_of U6)" 'U6b U6 の後も Cargo.lock を作っていない'

run_unavailable_case '^io-outside-driver: 根 .*/U7 に移れません$' \
  'U7 存在しない根を渡すと検査できない' bash "$script" "$work/U7"

place_case_tree U8 && place_control U8 || exit 1
run_unavailable_case '^io-outside-driver: clippy の出力を読めませんでした$' \
  'U8 clippy の出力をふるい分ける awk が失敗すると検査できない' \
  run_with_case_root U8 PATH="$(failing_awk_path_prefix "$work/U8")$PATH"

place_case_tree M1 || exit 1
printf '\n#[macro_export]\nmacro_rules! read_env {\n    ($name:expr) => {\n        std::env::var($name).is_ok()\n    };\n}\n' \
  >>"$(infrastructure_dir_of M1)/src/driver.rs"
append_translation M1 $'pub fn home() -> bool {\n    crate::read_env!("HOME")\n}'
run_case miss '' 'M1 (見ない形)driver で #[macro_export] したマクロを translation から呼ぶ std::env::var は報告しない' \
  run_with_case_root M1

place_case_tree M2 && place_control M2 || exit 1
mkdir -p "$work/M2/.cargo" "$work/M2/empty" || exit 1
printf '[env]\nCLIPPY_CONF_DIR = { value = "empty", force = true, relative = true }\n' >"$work/M2/.cargo/config.toml"
run_case miss '' 'M2 (見ない形)根の .cargo/config.toml の [env] で CLIPPY_CONF_DIR を force すると報告しない' \
  run_with_case_root M2

place_case_tree M3 && place_control M3 || exit 1
mkdir -p "$work/M3/.cargo" || exit 1
printf '[env]\nCLIPPY_ARGS = { value = "--cap-lints__CLIPPY_HACKERY__allow__CLIPPY_HACKERY__", force = true }\n' \
  >"$work/M3/.cargo/config.toml"
run_case miss '' 'M3 (見ない形)根の .cargo/config.toml の [env] で CLIPPY_ARGS を force すると報告しない' \
  run_with_case_root M3

place_case_tree M4 && place_control M4 || exit 1
printf '\npub type Handle = std::fs::File;\n' >>"$(infrastructure_dir_of M4)/src/driver.rs"
append_translation M4 $'pub fn opened() -> bool {\n    crate::driver::Handle::open("x").is_ok()\n}'
run_case deny "$control_line" \
  'M4 (見ない形)driver で付けた型の別名(pub type Handle = std::fs::File;)を通して translation で Handle::open("x") を呼ぶ I/O は報告しない' \
  run_with_case_root M4

# スクリプトの本文から、`<名前>="$(cat <<'<名前>'` で始まるヒアドキュメントの中身を出す。
#
# $1 スクリプトのパス
# $2 ヒアドキュメントの名前(変数名と区切りが同じもの)
heredoc_of() {
  awk -v name="$2" '
    $0 == name "=\"$(cat <<\047" name "\047" { inside = 1; next }
    $0 == name { inside = 0 }
    inside
  ' "$1"
}

# 検査の `io_places` を、並べ替えて出す。
#
# $1 `io-outside-driver.sh` のパス
io_places_of() {
  heredoc_of "$1" io_places | LC_ALL=C sort
}

# folder-deps.sh の許可表で `std::fs` / `std::process` / `std::os` / `*` のどれかを許す infrastructure/src の場所を
# `io_places` の綴り(ファイルはそのまま、フォルダは `<フォルダ>.rs` と `<フォルダ>/`)にし、`crates/infrastructure/tests/`
# を足して、並べ替えて出す。
#
# $1 `folder-deps.sh` のパス
folder_io_places_of() {
  {
    heredoc_of "$1" allowed_dependencies | awk -F '|' '
      BEGIN { io_partner["std::fs"]; io_partner["std::process"]; io_partner["std::os"]; io_partner["*"] }
      function has_io_partner(partners,   count, words, i) {
        count = split(partners, words, " ")
        for (i = 1; i <= count; i++) if (words[i] in io_partner) return 1
        return 0
      }
      function is_infrastructure_io_place(place, partners) {
        return place ~ /^infrastructure\/src\// && has_io_partner(partners)
      }
      is_infrastructure_io_place($1, $2) {
        place = "crates/" $1
        if (place ~ /\.rs$/) { print place; next }
        print place ".rs"
        print place "/"
      }
    '
    echo crates/infrastructure/tests/
  } | LC_ALL=C sort
}

# 検査の `io_places` と、folder-deps.sh の許可表から出した場所が一致するかを出す。
# どちらかを読めなければ `読めない`、一致すれば `一致`、違えば `食い違う`。
#
# $1 `io-outside-driver.sh` のパス
# $2 `folder-deps.sh` のパス
io_places_agreement_of() {
  local io_places folder_places unreadable=no
  io_places="$(io_places_of "$1")"
  folder_places="$(folder_io_places_of "$2")"
  { [ -z "$io_places" ] || [ -z "$folder_places" ]; } && unreadable=yes
  if [ "$unreadable" = yes ]; then
    echo 読めない
    return 0
  fi
  if [ "$io_places" = "$folder_places" ]; then
    echo 一致
    return 0
  fi
  echo 食い違う
}

report 一致 "$(io_places_agreement_of "$script" "$here/folder-deps.sh" 2>/dev/null)" \
  'C1 io_places の全行が、folder-deps.sh の許可表で I/O を許す infrastructure/src の場所と crates/infrastructure/tests/ に一致する'

exit "$cases_failed"
