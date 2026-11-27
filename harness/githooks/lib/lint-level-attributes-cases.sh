#!/usr/bin/env bash
#
# lint の水準の属性の検査(`lint-level-attributes.sh`)の判定表。
#
# ケースごとに使い捨ての木を組み直し(根は `$work/tree`。cargo は走らせない)、検査を走らせる。
# どのケースも `place_tree` が置く木(`crates/a/src/lib.rs` と、空の `crates/a/src/m`・`crates/a/tests/fixtures`)に、
# 決まったパス(多くは `crates/a/src/x.rs`)へ中身を直に書いて組む。1 ケースの判定の綴りと、それをどう照らすかは
# `cases-allowlist.sh` の `decision_of`。期待の違反の行は、このファイルに直に書く。
# 走らせ方は、ケースの `run_case` / `run_unavailable_case` の後ろに渡すコマンド(多くは根を引数に渡す
# `run_with_root`)。例外は 3 つで、D1 は根をカレントにして引数なしで呼び(`run_in_root`)、L17 は UTF-8 のロケールで、
# E2 は失敗する awk を PATH の先頭に置いて呼ぶ。見出し「検査できない」の下のケースは、検査できなかった理由が
# 標準エラーに出るかまで照らす(`cases-allowlist.sh` の `run_unavailable_case`)。見出し「見ない形」の下のケースは
# 検査が見ない形で、期待は `miss`。
#
# 使い方: bash harness/githooks/lib/lint-level-attributes-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
script="$here/lint-level-attributes.sh"

source "$here/../../../.claude/hooks/lib/cases-report.sh"
source "$here/../../../.claude/hooks/lib/cases-fixtures.sh"
source "$here/cases-allowlist.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT

tree="$work/tree"

# 検査が違反を報告するときの見出し。
heading='^deny / forbid 以外の lint の水準'

# 多くのケースが中身を書くファイル。
x_rs="$tree/crates/a/src/x.rs"

# 前のケースの木を消し、属性の無い crate を 1 つ置く。
place_tree() {
  rm -rf "$tree" || return 1
  mkdir -p "$tree/crates/a/src/m" "$tree/crates/a/tests/fixtures" || return 1
  printf 'pub fn f() {}\n' >"$tree/crates/a/src/lib.rs"
}

# 落とす形

place_tree || exit 1
printf '#[allow(dead_code)]\nfn f() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: #[allow(dead_code)]' \
  'L1 外側の #[allow(..)] を落とし、その行を出す' run_with_root "$tree"

place_tree || exit 1
printf '#![allow(dead_code)]\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: #![allow(dead_code)]' \
  'L2 内側の #![allow(..)] を落とす' run_with_root "$tree"

place_tree || exit 1
printf '#[expect(dead_code)]\nfn f() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: #[expect(dead_code)]' \
  'L3 外側の #[expect(..)] を落とす' run_with_root "$tree"

place_tree || exit 1
printf '#![expect(dead_code)]\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: #![expect(dead_code)]' \
  'L4 内側の #![expect(..)] を落とす' run_with_root "$tree"

place_tree || exit 1
printf '#[cfg_attr(test, allow(dead_code))]\nfn f() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: #[cfg_attr(test, allow(dead_code))]' \
  'L5 cfg_attr の中の allow を落とす' run_with_root "$tree"

place_tree || exit 1
cat >"$x_rs" <<'RS' || exit 1
#[cfg_attr(
    any(test, feature = "a-very-long-feature-name"),
    expect(dead_code, reason = "x")
)]
fn f() {}
RS
run_case deny 'crates/a/src/x.rs:3:     expect(dead_code, reason = "x")' \
  'L6 rustfmt が折り返した cfg_attr で、expect(..) だけの行を落とす' run_with_root "$tree"

place_tree || exit 1
printf '#![warn(warnings)]\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: #![warn(warnings)]' \
  'L7 #![warn(warnings)] を落とす' run_with_root "$tree"

place_tree || exit 1
printf '#[warn(clippy::disallowed_methods)]\nfn f() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: #[warn(clippy::disallowed_methods)]' \
  'L8 #[warn(clippy::disallowed_methods)] を落とす' run_with_root "$tree"

place_tree || exit 1
printf '#![warn(missing_docs)]\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: #![warn(missing_docs)]' \
  'L9 水準を上げる #![warn(missing_docs)] も落とす' run_with_root "$tree"

place_tree || exit 1
printf 'struct S;\nimpl S {\n    #[allow(dead_code)]\n    fn f() {}\n}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:3:     #[allow(dead_code)]' \
  'L10 impl の中で字下げした #[allow(..)] を落とす' run_with_root "$tree"

place_tree || exit 1
printf 'macro_rules! m {\n    () => {\n        #[allow(dead_code)]\n        fn f() {}\n    };\n}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:3:         #[allow(dead_code)]' \
  'L11 macro_rules! の本体の #[allow(..)] を落とす' run_with_root "$tree"

place_tree || exit 1
printf 'id! {\n    #[allow\n    (dead_code)]\n    fn f() {}\n}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:2:     #[allow' \
  'L12 波括弧のマクロ呼び出しで #[allow と (dead_code)] を 2 行に分けても、#[allow の行を落とす' run_with_root "$tree"

place_tree || exit 1
printf 'id! {\n    #[allow // c\n    (dead_code)]\n    fn f() {}\n}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:2:     #[allow // c' \
  'L13 #[allow // c と (dead_code)] に分けても落とす' run_with_root "$tree"

place_tree || exit 1
printf '#[allow /* c */ (dead_code)]\nfn f() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: #[allow /* c */ (dead_code)]' \
  'L14 allow と ( の間にブロックコメントを挟んでも落とす' run_with_root "$tree"

place_tree || exit 1
printf '#[r#allow(dead_code)]\nfn f() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: #[r#allow(dead_code)]' \
  'L15 生の識別子 #[r#allow(..)] を落とす' run_with_root "$tree"

place_tree || exit 1
printf 'id! {\n    #[allow\342\200\216(dead_code)]\n    #[expect\302\205(dead_code)]\n    #[warn\342\200\251(x)]\n    fn f() {}\n}\n' \
  >"$x_rs" || exit 1
run_case deny "$(printf 'crates/a/src/x.rs:2:     #[allow\342\200\216(dead_code)]\ncrates/a/src/x.rs:3:     #[expect\302\205(dead_code)]\ncrates/a/src/x.rs:4:     #[warn\342\200\251(x)]')" \
  'L16 rustc が空白とみなす U+200E・U+0085・U+2029 を語と ( の間に挟んでも落とす' run_with_root "$tree"

place_tree || exit 1
printf 'id! {\n    #[allow\342\200\216(dead_code)]\n    fn f() {}\n}\n' >"$x_rs" || exit 1
run_case deny "$(printf 'crates/a/src/x.rs:2:     #[allow\342\200\216(dead_code)]')" \
  'L17 UTF-8 のロケールで走らせても、U+200E を挟んだ形を落とす' env LC_ALL=C.UTF-8 bash "$script" "$tree"

place_tree || exit 1
printf 'fn f() {}\n' >"$x_rs" || exit 1
printf '#![allow(x)]\n' >"$tree/crates/a/build.rs" || exit 1
printf '#[warn(x)]\n' >"$tree/crates/a/src/m/n.rs" || exit 1
printf '#[allow(dead_code)]\n' >"$tree/crates/a/tests/cli.rs" || exit 1
printf '#[expect(dead_code)]\n' >"$tree/crates/a/tests/fixtures/sample.rs" || exit 1
run_case deny 'crates/a/build.rs:1: #![allow(x)]
crates/a/src/m/n.rs:1: #[warn(x)]
crates/a/tests/cli.rs:1: #[allow(dead_code)]
crates/a/tests/fixtures/sample.rs:1: #[expect(dead_code)]' \
  'L18 下の階層も見る(build.rs・src の下の段・tests/・tests/fixtures/)' run_with_root "$tree"

place_tree || exit 1
printf '#[expect(dead_code)]\nfn f() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: #[expect(dead_code)]' \
  'D1 引数なしで呼ぶと、カレントディレクトリを根として検査する' run_in_root "$tree"

# 受け入れる誤検知

place_tree || exit 1
printf '/// 例: `#[allow(x)]`\npub const S: &str = "#[allow(x)]";\n// #[allow(x)]\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: /// 例: `#[allow(x)]`
crates/a/src/x.rs:2: pub const S: &str = "#[allow(x)]";
crates/a/src/x.rs:3: // #[allow(x)]' \
  'C1 doc・文字列・// のコメントの中の属性の例も出す(読み分けない)' run_with_root "$tree"

place_tree || exit 1
printf 'pub fn warn(score: f64) -> f64 {\n    score\n}\npub fn g() -> f64 {\n    warn(0.5)\n}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: pub fn warn(score: f64) -> f64 {
crates/a/src/x.rs:5:     warn(0.5)' \
  'C2 warn という名前の関数の定義と、修飾しない呼び出しも出す' run_with_root "$tree"

place_tree || exit 1
printf '/// 判定が risk か warn\n/// this lint would allow\n/// what you would expect (roughly)\nfn f() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: /// 判定が risk か warn
crates/a/src/x.rs:2: /// this lint would allow
crates/a/src/x.rs:3: /// what you would expect (roughly)' \
  'C3 語で終わる doc の行と、語の後に ( が続く doc の行も出す' run_with_root "$tree"

place_tree || exit 1
printf 'const SAMPLE: &str = r#"#[allow(dead_code)] fn f() {}"#;\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: const SAMPLE: &str = r#"#[allow(dead_code)] fn f() {}"#;' \
  'C4 テストへ入力として渡す Rust の文字列の中の属性も出す' run_with_root "$tree"

# 拾わない形

place_tree || exit 1
printf 'fn f(r: Option<u8>) -> u8 {\n    r.expect("x")\n}\n#[allow(dead_code)]\nfn g() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:4: #[allow(dead_code)]' \
  'P1 .expect("..") は拾わない' run_with_root "$tree"

place_tree || exit 1
printf 'fn f(r: Result<u8, ()>) -> u8 {\n    Result::expect(r, "x")\n}\n#[allow(dead_code)]\nfn g() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:4: #[allow(dead_code)]' \
  'P2 Result::expect(r, "..") は拾わない' run_with_root "$tree"

place_tree || exit 1
printf '#![deny(warnings)]\n#[forbid(unsafe_code)]\nfn f() {}\n#[allow(dead_code)]\nfn g() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:4: #[allow(dead_code)]' \
  'P3 #![deny(..)] と #[forbid(..)] は拾わない' run_with_root "$tree"

place_tree || exit 1
cat >"$x_rs" <<'RS' || exit 1
fn allowed() {}
fn disallow() {}
fn expected() {}
const W: &str = "warn";
#[serde(rename = "warn")]
struct V;
#[allow(dead_code)]
fn g() {}
RS
run_case deny 'crates/a/src/x.rs:7: #[allow(dead_code)]' \
  'P4 fn allowed()・fn disallow()・fn expected()・"warn"・#[serde(rename = "warn")] は拾わない' run_with_root "$tree"

place_tree || exit 1
printf 'fn my_allow() {}\nfn f() {\n    my_allow();\n}\n#[allow(dead_code)]\nfn g() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:5: #[allow(dead_code)]' \
  'P5 my_allow( は拾わない' run_with_root "$tree"

place_tree || exit 1
printf '#[allow(dead_code)]\nfn g() {}\n' >"$x_rs" || exit 1
printf '#[allow(dead_code)]\n' >"$tree/crates/a/src/sample.rs.txt" || exit 1
printf '#[allow(x)]\n' >"$tree/crates/a/README.md" || exit 1
run_case deny 'crates/a/src/x.rs:1: #[allow(dead_code)]' \
  'P6 .rs 以外のファイル(.rs.txt・.md)は見ない' run_with_root "$tree"

place_tree || exit 1
printf '#[allow(dead_code)]\n' >"$tree/outside.rs" || exit 1
printf '#[allow(dead_code)]\nfn g() {}\n' >"$x_rs" || exit 1
run_case deny 'crates/a/src/x.rs:1: #[allow(dead_code)]' \
  'P7 <根>/crates の外の .rs は見ない' run_with_root "$tree"

place_tree || exit 1
run_case pass '' 'P8 属性の無い木なら exit 0 で何も出さない' run_with_root "$tree"

# 見ない形

place_tree || exit 1
cat >"$x_rs" <<'RS' || exit 1
macro_rules! m {
    ($l:ident) => {
        #[$l(dead_code)]
        fn f() {}
    };
}
m!(allow);
RS
run_case miss '' 'M1 属性の名前をマクロの変数で渡す形は見ない' run_with_root "$tree"

# 検査できない

place_tree || exit 1
rm -rf "$tree/crates" || exit 1
run_unavailable_case '^lint-level-attributes: .*crates はディレクトリではありません' \
  'E1 <根>/crates が無ければ検査できない' run_with_root "$tree"

place_tree || exit 1
failing_awk_prefix="$(failing_awk_path_prefix "$work")" || exit 1
run_unavailable_case '^lint-level-attributes: .*走査に失敗' \
  'E2 awk が落ちれば、走査に失敗したことを出して検査できない' env PATH="$failing_awk_prefix$PATH" bash "$script" "$tree"

exit "$cases_failed"
