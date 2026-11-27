#!/usr/bin/env bash
#
# フォルダの依存の許可表の検査(`folder-deps.sh`)の判定表。
#
# ケースごとに使い捨ての木を組み直し(根は `$work/tree`。cargo は走らせない)、検査を走らせる。
# どのケースも基準の木 B(中身は `place_tree_b`)に手を入れて組む。違反は新しいファイル(`<場所>/r1.rs` など)に
# 置き、lib.rs・mod.rs のように場所そのものを見るケースだけ既存のファイルを書き換える・置き換える。
# 1 ケースの判定の綴りと、それをどう照らすかは `cases-allowlist.sh` の `decision_of`。期待の違反の行は、
# このファイルに直に書く。
# 走らせ方は、ケースの `run_case` / `run_unavailable_case` の後ろに渡すコマンド(多くは根を引数に渡す
# `run_with_root`)。見出し「検査できない」の下のケースは、検査できなかった理由が標準エラーに出るかまで照らす
# (`cases-allowlist.sh` の `run_unavailable_case`)。見出し「見ない形」の下のケースは検査が見ない形で、期待は `miss`。
#
# 使い方: bash harness/githooks/lib/folder-deps-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
script="$here/folder-deps.sh"

source "$here/../../../.claude/hooks/lib/cases-report.sh"
source "$here/../../../.claude/hooks/lib/cases-fixtures.sh"
source "$here/cases-allowlist.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT

tree="$work/tree"

# 検査が違反を報告するときの見出し。
heading='^フォルダの依存が許可表にありません'

# 木の中にファイルを置く。中身は標準入力。
#
# $1 根からのパス
place_file() {
  mkdir -p "$(dirname "$tree/$1")" || return 1
  cat >"$tree/$1"
}

# 木の中のファイルの先頭に 1 行足す。
#
# $1 根からのパス
# $2 足す行
prepend_to_file() {
  { printf '%s\n' "$2" && cat "$tree/$1"; } >"$tree/$1.next" || return 1
  mv "$tree/$1.next" "$tree/$1"
}

# 前のケースの木を消し、基準の木 B を置く。各 crate の場所ごとに、許可表で許された相手を参照するファイルを置く。
place_tree_b() {
  local member
  rm -rf "$tree" || return 1
  mkdir -p "$tree/crates" || return 1
  printf '[workspace]\nmembers = ["crates/*"]\nresolver = "3"\n' >"$tree/Cargo.toml" || return 1
  for member in domain application infrastructure presentation tightrope; do
    place_member "$tree/crates/$member" "$member" || return 1
  done

  place_file crates/domain/src/lib.rs <<'RS' || return 1
pub mod aggregate;
pub mod entity;
pub mod policy;
pub mod value_object;
pub mod workflow;
RS
  place_file crates/domain/src/value_object.rs <<<'pub struct Strength;' || return 1
  place_file crates/domain/src/entity.rs <<<'use crate::value_object::Strength;' || return 1
  place_file crates/domain/src/policy.rs <<<'pub mod lean;' || return 1
  place_file crates/domain/src/policy/lean.rs <<<'use super::super::value_object::Strength;' || return 1
  place_file crates/domain/src/aggregate.rs <<<'use crate::{entity::Module, value_object::Strength};' || return 1
  place_file crates/domain/src/workflow/report/step/resolve.rs \
    <<<'use super::super::super::super::{aggregate::Module, entity, policy::Lean, value_object::Strength};' || return 1
  place_file crates/domain/tests/model.rs <<'RS' || return 1
use domain::entity::Module;
use domain::value_object::Strength;
RS

  place_file crates/application/src/lib.rs <<'RS' || return 1
pub mod dto;
pub mod error;
pub mod mapping;
pub mod port;
pub mod usecase;
RS
  place_file crates/application/src/dto.rs <<'RS' || return 1
#[derive(serde::Serialize)]
pub struct Report;
RS
  place_file crates/application/src/port.rs <<<'use crate::dto::Report;' || return 1
  place_file crates/application/src/mapping.rs <<'RS' || return 1
use crate::dto::Report;
use domain::entity::Module;
RS
  place_file crates/application/src/usecase.rs <<'RS' || return 1
use crate::{dto::Report, error::Failure, mapping::Rows, port::Source};
use domain::workflow::Run;
RS
  place_file crates/application/src/error.rs <<<'use crate::dto::Report;' || return 1
  place_file crates/application/tests/flow.rs <<'RS' || return 1
use application::usecase::Run;
use domain::entity::Module;
#[derive(serde::Serialize)]
struct Row;
RS

  place_file crates/infrastructure/src/lib.rs <<'RS' || return 1
pub mod adapter;
pub mod driver;
pub mod translation;
RS
  place_file crates/infrastructure/src/driver.rs <<'RS' || return 1
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::process::Command;
RS
  place_file crates/infrastructure/src/translation.rs <<<'use application::dto::Report;' || return 1
  place_file crates/infrastructure/src/adapter.rs <<'RS' || return 1
use crate::{driver::Files, translation::Rows};
use application::{dto::Report, port::Source};
RS
  place_file crates/infrastructure/tests/io.rs <<'RS' || return 1
use std::fs;
use application::port::Source;
use infrastructure::adapter::Store;
RS

  place_file crates/presentation/src/lib.rs <<'RS' || return 1
pub mod controller;
pub mod presenter;
pub mod view;
pub mod view_model;
RS
  place_file crates/presentation/src/controller.rs <<<'use application::dto::Report;' || return 1
  place_file crates/presentation/src/view_model.rs <<<'pub struct Page;' || return 1
  place_file crates/presentation/src/presenter.rs <<'RS' || return 1
use crate::view_model::Page;
use application::{dto::Report, error::Failure};
RS
  place_file crates/presentation/src/view.rs <<'RS' || return 1
use crate::view_model::Page;
use application::dto::Report;
RS
  place_file crates/presentation/tests/render.rs <<'RS' || return 1
use presentation::view::Page;
use application::{dto::Report, error::Failure};
RS

  place_file crates/tightrope/src/lib.rs <<'RS' || return 1
pub mod composition;
pub mod exit_code;
pub mod sink;

pub use presentation::controller::cli;
RS
  place_file crates/tightrope/src/main.rs <<<'fn main() { tightrope::composition::run(); }' || return 1
  place_file crates/tightrope/src/composition.rs <<'RS' || return 1
use domain::policy::Lean;
use infrastructure::adapter::Store;
RS
  place_file crates/tightrope/src/sink.rs <<<'use std::fs::File;' || return 1
  place_file crates/tightrope/src/exit_code.rs <<'RS' || return 1
#[derive(serde::Serialize)]
pub struct ExitCode;
RS
  place_file crates/tightrope/tests/cli.rs <<'RS' || return 1
use std::process::Command;
use tightrope::composition::run;
RS
}

# 表

place_tree_b || exit 1
run_case pass '' 'P1 基準の木 B(どの場所も許可表で許された相手だけを参照する)は通る' run_with_root "$tree"

place_tree_b || exit 1
rm -rf "$tree/crates/application" || exit 1
run_case pass '' 'P2 表にあって木に無い crate(application)があっても通る' run_with_root "$tree"

place_tree_b || exit 1
printf '%s\n' 'presentation = { path = "../presentation" }' '' '[dependencies.domain]' 'path = "../domain"' \
  >>"$tree/crates/tightrope/Cargo.toml" || exit 1
run_case pass '' 'P3 依存の path = があっても検査できないとしない' run_with_root "$tree"

place_tree_b || exit 1
printf '%s\n' '["package"]' '"name" = "domain"' 'version = "0.1.0"' 'edition = "2024"' '' "['lib']" "'name' = 'domain'" \
  >"$tree/crates/domain/Cargo.toml" || exit 1
run_case pass '' 'P4 引用符付きの見出しとキーで name をディレクトリ名と同じに書けば通る' run_with_root "$tree"

place_tree_b || exit 1
prepend_to_file crates/domain/src/lib.rs 'use std::fs;' || exit 1
place_file crates/domain/src/value_object/r1.rs <<<'use std::process::Command;' || exit 1
place_file crates/domain/src/entity/r1.rs <<<'use std::os::unix::fs::PermissionsExt;' || exit 1
place_file crates/domain/src/policy/r1.rs <<<'use crate::entity::Module;' || exit 1
place_file crates/domain/src/aggregate/r1.rs <<<'use crate::policy::Lean;' || exit 1
place_file crates/domain/src/workflow/r1.rs <<<'#[derive(serde::Serialize)] struct Step;' || exit 1
prepend_to_file crates/application/src/lib.rs 'use domain::entity::Module;' || exit 1
place_file crates/application/src/dto/r1.rs <<<'use domain::entity::Module;' || exit 1
place_file crates/application/src/port/r1.rs <<<'use crate::mapping::Rows;' || exit 1
place_file crates/application/src/mapping/r1.rs <<<'use crate::usecase::Run;' || exit 1
place_file crates/application/src/usecase/r1.rs <<<'use std::fs;' || exit 1
place_file crates/application/src/error/r1.rs <<<'use crate::port::Source;' || exit 1
prepend_to_file crates/infrastructure/src/lib.rs 'use application::dto::Report;' || exit 1
place_file crates/infrastructure/src/driver/r1.rs <<<'use application::dto::Report;' || exit 1
place_file crates/infrastructure/src/translation/r1.rs <<<'use std::process::Command;' || exit 1
place_file crates/infrastructure/src/adapter/r1.rs <<<'use std::os::unix::fs::PermissionsExt;' || exit 1
prepend_to_file crates/presentation/src/lib.rs 'use std::process::exit;' || exit 1
place_file crates/presentation/src/controller/r1.rs <<<'use std::fs;' || exit 1
place_file crates/presentation/src/view_model/r1.rs <<<'use application::dto::Report;' || exit 1
place_file crates/presentation/src/presenter/r1.rs <<<'use crate::controller::cli;' || exit 1
place_file crates/presentation/src/view/r1.rs <<<'use std::os::fd::AsFd;' || exit 1
place_file crates/domain/tests/r1.rs <<<'use application::dto::Report;' || exit 1
place_file crates/application/tests/r1.rs <<<'use presentation::view::Page;' || exit 1
place_file crates/infrastructure/tests/r1.rs <<<'#[derive(serde::Deserialize)] struct Row;' || exit 1
place_file crates/presentation/tests/r1.rs <<<'use std::fs;' || exit 1
run_case deny 'crates/domain/src/lib.rs:1: std::fs(許可表の行 domain/src/lib.rs|)
crates/domain/src/value_object/r1.rs:1: std::process(許可表の行 domain/src/value_object|)
crates/domain/src/entity/r1.rs:1: std::os(許可表の行 domain/src/entity|domain::value_object)
crates/domain/src/policy/r1.rs:1: domain::entity(許可表の行 domain/src/policy|domain::value_object)
crates/domain/src/aggregate/r1.rs:1: domain::policy(許可表の行 domain/src/aggregate|domain::entity domain::value_object)
crates/domain/src/workflow/r1.rs:1: serde(許可表の行 domain/src/workflow|domain::policy domain::aggregate domain::entity domain::value_object)
crates/application/src/lib.rs:1: domain::entity(許可表の行 application/src/lib.rs|)
crates/application/src/dto/r1.rs:1: domain::entity(許可表の行 application/src/dto|serde)
crates/application/src/port/r1.rs:1: application::mapping(許可表の行 application/src/port|application::dto)
crates/application/src/mapping/r1.rs:1: application::usecase(許可表の行 application/src/mapping|application::dto domain::*)
crates/application/src/usecase/r1.rs:1: std::fs(許可表の行 application/src/usecase|application::port application::mapping application::dto application::error domain::*)
crates/application/src/error/r1.rs:1: application::port(許可表の行 application/src/error|application::dto)
crates/infrastructure/src/lib.rs:1: application::dto(許可表の行 infrastructure/src/lib.rs|)
crates/infrastructure/src/driver/r1.rs:1: application::dto(許可表の行 infrastructure/src/driver|std::fs std::process std::os)
crates/infrastructure/src/translation/r1.rs:1: std::process(許可表の行 infrastructure/src/translation|application::dto)
crates/infrastructure/src/adapter/r1.rs:1: std::os(許可表の行 infrastructure/src/adapter|infrastructure::driver infrastructure::translation application::port application::dto)
crates/presentation/src/lib.rs:1: std::process(許可表の行 presentation/src/lib.rs|)
crates/presentation/src/controller/r1.rs:1: std::fs(許可表の行 presentation/src/controller|application::dto)
crates/presentation/src/view_model/r1.rs:1: application::dto(許可表の行 presentation/src/view_model|)
crates/presentation/src/presenter/r1.rs:1: presentation::controller(許可表の行 presentation/src/presenter|presentation::view_model application::dto application::error)
crates/presentation/src/view/r1.rs:1: std::os(許可表の行 presentation/src/view|presentation::view_model application::dto)
crates/domain/tests/r1.rs:1: application::dto(許可表の domain/src の行の和集合)
crates/application/tests/r1.rs:1: presentation::view(許可表の application/src の行の和集合)
crates/infrastructure/tests/r1.rs:1: serde(許可表の infrastructure/src の行の和集合)
crates/presentation/tests/r1.rs:1: std::fs(許可表の presentation/src の行の和集合)' \
  'R1 * 以外の 21 行と 4 つの crate の tests/ に許可されていない相手を 1 つずつ足すと 25 行出る' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/application/src/mapping/r1.rs <<'RS' || exit 1
use presentation::view::Page;
use domain::workflow::Run;
RS
run_case deny 'crates/application/src/mapping/r1.rs:1: presentation::view(許可表の行 application/src/mapping|application::dto domain::*)' \
  'T1 domain::* は domain の下だけを通し、domain 以外の crate は通さない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/infrastructure/tests/r1.rs <<'RS' || exit 1
use std::process::Command;
use application::port::Source;
use infrastructure::adapter::Store;
use domain::entity::Module;
RS
run_case deny 'crates/infrastructure/tests/r1.rs:4: domain::entity(許可表の infrastructure/src の行の和集合)' \
  'T2 結合テストは、その crate の src の行の和集合と各フォルダで照らす' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'use crate::policy::Lean;' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: domain::policy(許可表の行 domain/src/entity|domain::value_object)' \
  'D1 引数なしで呼ぶとカレントディレクトリを根として検査する' run_in_root "$tree"

# 参照の綴り

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
fn f() -> Vec<crate::policy::Lean> { crate::aggregate::build() }
fn g() { crate::value_object::std::fs::read(); }
RS
run_case deny 'crates/domain/src/entity/r1.rs:1: domain::policy(許可表の行 domain/src/entity|domain::value_object)
crates/domain/src/entity/r1.rs:1: domain::aggregate(許可表の行 domain/src/entity|domain::value_object)' \
  'F1 式の中のパスとジェネリクスの中のパスを拾い、パスの続きの段(::std)は拾わない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
use crate::{
    value_object::Strength,
    policy::Lean,
    aggregate::Module,
};
RS
run_case deny 'crates/domain/src/entity/r1.rs:3: domain::policy(許可表の行 domain/src/entity|domain::value_object)
crates/domain/src/entity/r1.rs:4: domain::aggregate(許可表の行 domain/src/entity|domain::value_object)' \
  'F2 複数行の use crate::{…} は要素の行で出す' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'use std::{fs::{self, File}, io};' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: std::fs(許可表の行 domain/src/entity|domain::value_object)' \
  'F3 入れ子のグループと self は展開し、同じ行の同じ参照先は 1 行にまとめる' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'use {crate::policy::Lean, ::std::fs::read};' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: domain::policy(許可表の行 domain/src/entity|domain::value_object)
crates/domain/src/entity/r1.rs:1: std::fs(許可表の行 domain/src/entity|domain::value_object)' \
  'F4 トップのグループと先頭の :: を読む' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
use super::super::policy::Lean;
fn f() { self::super::super::aggregate::build(); super::Sibling; }
RS
run_case deny 'crates/domain/src/entity/r1.rs:1: domain::policy(許可表の行 domain/src/entity|domain::value_object)
crates/domain/src/entity/r1.rs:2: domain::aggregate(許可表の行 domain/src/entity|domain::value_object)' \
  'F5 super と self::super が根まで上がれば次の段をフォルダとし、自分のフォルダに留まる super は出さない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'macro_rules! lean { () => { $crate::policy::Lean } }' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: domain::policy(許可表の行 domain/src/entity|domain::value_object)' \
  'F6 macro_rules! の中の $crate:: は crate:: と読む' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/policy/r1.rs <<'RS' || exit 1
pub(crate) fn a() {}
pub(super) fn b() {}
pub(in crate::policy) fn c() {}
fn d() { crate::entity::Module; }
RS
run_case deny 'crates/domain/src/policy/r1.rs:4: domain::entity(許可表の行 domain/src/policy|domain::value_object)' \
  'F7 pub(crate) / pub(super) / pub(in crate::policy) は出さない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'use crate::policy as p;' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: domain::policy(許可表の行 domain/src/entity|domain::value_object)' \
  'F8 フォルダに as で別名を付けても、参照先はそのフォルダ' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/application/src/port/r1.rs <<'RS' || exit 1
use serde_json::Value;
#[serde(rename = "x")]
struct Query;
RS
run_case deny 'crates/application/src/port/r1.rs:2: serde(許可表の行 application/src/port|application::dto)' \
  'F9 serde は名前がどこに出ても serde と数え、serde_json は数えない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
use std::os::unix::fs::MetadataExt;
use std::os::fd::AsFd;
RS
run_case deny 'crates/domain/src/entity/r1.rs:1: std::os(許可表の行 domain/src/entity|domain::value_object)
crates/domain/src/entity/r1.rs:2: std::os(許可表の行 domain/src/entity|domain::value_object)' \
  'F10 std::os の下はどの段も std::os と数える' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
use std::path::Path;
use std::io::Read;
use std::fmt;
fn f() { std::fs::write("a", "b"); }
RS
run_case deny 'crates/domain/src/entity/r1.rs:4: std::fs(許可表の行 domain/src/entity|domain::value_object)' \
  'F11 std::path・std::io・std::fmt は照らさない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/value_object/r1.rs <<'RS' || exit 1
fn a() -> i32 { return ::std::process::exit(1); }
fn b(p: &str) { for _e in ::std::fs::read_dir(p) {} }
fn c(f: &mut ::std::fs::File) {}
impl ::std::process::Termination for Strength {}
fn d(x: &dyn ::std::os::fd::AsFd) {}
fn e() -> i32 { if ::std::fs::exists("x") { 1 } else { 0 } }
RS
run_case deny 'crates/domain/src/value_object/r1.rs:1: std::process(許可表の行 domain/src/value_object|)
crates/domain/src/value_object/r1.rs:2: std::fs(許可表の行 domain/src/value_object|)
crates/domain/src/value_object/r1.rs:3: std::fs(許可表の行 domain/src/value_object|)
crates/domain/src/value_object/r1.rs:4: std::process(許可表の行 domain/src/value_object|)
crates/domain/src/value_object/r1.rs:5: std::os(許可表の行 domain/src/value_object|)
crates/domain/src/value_object/r1.rs:6: std::fs(許可表の行 domain/src/value_object|)' \
  'F12 キーワード(return / in / mut / impl / dyn / if)の直後の ::std はパスの続きの段と読まない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/value_object/r1.rs <<'RS' || exit 1
fn d() -> ::std::process::ExitCode { todo!() }
fn e(x: u8) { match x { 0 => {} _ => ::std::fs::remove_file("x") } }
fn g() -> ::domain::entity::Module { todo!() }
RS
run_case deny 'crates/domain/src/value_object/r1.rs:1: std::process(許可表の行 domain/src/value_object|)
crates/domain/src/value_object/r1.rs:2: std::fs(許可表の行 domain/src/value_object|)
crates/domain/src/value_object/r1.rs:3: domain::entity(許可表の行 domain/src/value_object|)' \
  'F13 -> と => の後ろの ::std と ::<crate> はパスの続きの段と読まない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/value_object/r1.rs <<'RS' || exit 1
fn f() { foo::std::fs::read("x"); r#return::std::process::exit(1); }
fn g() { ::std::fs::read("x"); }
RS
run_case deny 'crates/domain/src/value_object/r1.rs:2: std::fs(許可表の行 domain/src/value_object|)' \
  'F14 キーワードでない識別子の後ろの ::std はパスの続きの段として拾わない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
fn f() { std::/**/fs::read("x"); }
fn g() { crate::/**/policy::Lean; }
fn h() { crate::value_object::Strength::<u8>::new(); }
RS
run_case deny 'crates/domain/src/entity/r1.rs:1: 読めない参照の形(:: の後ろが識別子でないパス)
crates/domain/src/entity/r1.rs:2: 読めない参照の形(:: の後ろが識別子でないパス)' \
  'F15 :: の後ろが識別子でないパスは読めない形で、型引数の ::< は出さない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/application/src/port/r1.rs <<'RS' || exit 1
use crate::dto::serde::Serialize;
use crate::dto::Report;
RS
run_case deny 'crates/application/src/port/r1.rs:1: serde(許可表の行 application/src/port|application::dto)' \
  'F16 use の中でも、serde はパスのどの段に出ても serde と数える' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/value_object/r1.rs <<'RS' || exit 1
fn f<'a>(x: &'a ::std::fs::File) {}
RS
run_case deny 'crates/domain/src/value_object/r1.rs:1: std::fs(許可表の行 domain/src/value_object|)' \
  'F17 ライフタイムの後ろの ::std はパスの続きの段と読まない' run_with_root "$tree"

# 場所

place_tree_b || exit 1
place_file crates/domain/src/policy/lean/tests.rs <<'RS' || exit 1
use super::*;
use crate::entity::Module;
RS
place_file crates/domain/src/policy/lean/tests/edge.rs <<<'use crate::aggregate::Module;' || exit 1
run_case deny 'crates/domain/src/policy/lean/tests.rs:2: domain::entity(許可表の行 domain/src/policy|domain::value_object)
crates/domain/src/policy/lean/tests/edge.rs:1: domain::aggregate(許可表の行 domain/src/policy|domain::value_object)' \
  'L1 単体テスト(tests.rs と tests/<観点>.rs)は、そのフォルダの行で照らす' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/service.rs <<<'use crate::entity::Module;' || exit 1
place_file crates/domain/src/service/r1.rs <<<'use std::fs;' || exit 1
run_case deny 'domain/src/service: 許可表に行が無い場所' \
  'L2 許可表に行が無いフォルダは、ファイルがいくつあっても 1 行だけ出し、参照は照らさない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/build.rs <<<'use std::fs;' || exit 1
place_file crates/domain/examples/demo.rs <<<'fn main() {}' || exit 1
place_file crates/domain/src/tests.rs <<<'use crate::entity::Module;' || exit 1
run_case deny 'domain/build.rs: 許可表に行が無い場所
domain/examples: 許可表に行が無い場所
domain/src/tests: 許可表に行が無い場所' \
  'L3 build.rs・examples/・src/tests.rs は許可表に行が無い場所' run_with_root "$tree"

place_tree_b || exit 1
place_member "$tree/crates/extra" extra || exit 1
place_file crates/extra/src/lib.rs <<<'use std::fs;' || exit 1
place_file crates/scratch/src/lib.rs <<<'use std::fs;' || exit 1
run_case deny 'extra/src/lib.rs: 許可表に行が無い場所
scratch/src: 許可表に行が無い場所' \
  'L4 表に無いメンバーと Cargo.toml の無いディレクトリは許可表に行が無い場所' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/tests/fixtures/deep/a.rs <<<'use std::fs;' || exit 1
place_file crates/domain/tests/support/deep/b.rs <<<'use std::process;' || exit 1
place_file crates/domain/src/value_object/fixtures/c.rs <<<'use std::fs;' || exit 1
run_case deny 'crates/domain/src/value_object/fixtures/c.rs:1: std::fs(許可表の行 domain/src/value_object|)
crates/domain/tests/support/deep/b.rs:1: std::process(許可表の domain/src の行の和集合)' \
  'L5 見ないのは crate の tests/fixtures/ の下だけ' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/tests/r1.rs <<'RS' || exit 1
use crate::helper;
use self::fixture;
use super::shared;
use domain::entity::Module;
use application::dto::Report;
RS
run_case deny 'crates/domain/tests/r1.rs:5: application::dto(許可表の domain/src の行の和集合)' \
  'L6 結合テストの crate:: / self:: / super:: は照らさず、crate 名で書いた参照は照らす' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/lib.rs <<'RS' || exit 1
pub mod aggregate;
pub mod entity;
pub mod policy;
pub mod value_object;
pub mod workflow;
pub use self::entity::Module;
RS
run_case deny 'crates/domain/src/lib.rs:6: domain::entity(許可表の行 domain/src/lib.rs|)' \
  'L7 lib.rs の pub mod は通し、pub use self::entity::Module; は落とす' run_with_root "$tree"

place_tree_b || exit 1
rm -f "$tree/crates/domain/src/policy.rs" || exit 1
place_file crates/domain/src/policy/mod.rs <<'RS' || exit 1
pub mod lean;
use super::entity::Module;
RS
run_case deny 'crates/domain/src/policy/mod.rs:2: domain::entity(許可表の行 domain/src/policy|domain::value_object)' \
  'L8 mod.rs は 1 段浅く数える' run_with_root "$tree"

place_tree_b || exit 1
ln -s policy.rs "$tree/crates/domain/src/linked.rs" || exit 1
ln -s policy "$tree/crates/domain/src/linked_dir" || exit 1
mkdir -p "$tree/crates/domain/tests/fixtures" || exit 1
ln -s ../model.rs "$tree/crates/domain/tests/fixtures/linked.rs" || exit 1
run_case deny 'crates/domain/src/linked.rs: 読めない参照の形(シンボリックリンク)
crates/domain/src/linked_dir: 読めない参照の形(シンボリックリンク)' \
  'L9 ファイルとディレクトリへのシンボリックリンクを出し、tests/fixtures/ の下のものは出さない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'mod inner { use super::super::policy::Lean; }' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: domain::policy(許可表の行 domain/src/entity|domain::value_object)' \
  'L10 inline の mod の中の super は数えず、誤検知の側にずれる' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/tests/fixtures/main.rs <<<'use std::fs;' || exit 1
place_file crates/domain/tests/fixtures/mod.rs <<<'pub mod deep;' || exit 1
place_file crates/domain/tests/fixtures/deep.rs <<<'use std::fs;' || exit 1
place_file crates/domain/tests/fixtures/sub/main.rs <<<'use std::fs;' || exit 1
run_case deny 'crates/domain/tests/fixtures/main.rs: 読めない参照の形(tests/fixtures の main.rs か mod.rs)
crates/domain/tests/fixtures/mod.rs: 読めない参照の形(tests/fixtures の main.rs か mod.rs)' \
  'L11 tests/fixtures の直下の main.rs と mod.rs は読めない形で、その他の fixtures は見ない' run_with_root "$tree"

place_tree_b || exit 1
mkdir -p "$tree/crates/domain/tests/fixtures" || exit 1
ln -s ../model.rs "$tree/crates/domain/tests/fixtures/main.rs" || exit 1
ln -s ../model.rs "$tree/crates/domain/tests/fixtures/linked.rs" || exit 1
run_case deny 'crates/domain/tests/fixtures/main.rs: 読めない参照の形(シンボリックリンク)' \
  'L12 tests/fixtures の直下の main.rs のシンボリックリンクは出し、その他の fixtures のリンクは出さない' run_with_root "$tree"

# 読めない形

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
use std as standard;
use crate as this;
use super::super as up;
use domain;
use std;
use self::super::super as up_again;
RS
run_case deny 'crates/domain/src/entity/r1.rs:1: 読めない参照の形(根の別名)
crates/domain/src/entity/r1.rs:2: 読めない参照の形(根の別名)
crates/domain/src/entity/r1.rs:3: 読めない参照の形(根の別名)
crates/domain/src/entity/r1.rs:4: 読めない参照の形(根の別名)
crates/domain/src/entity/r1.rs:5: 読めない参照の形(根の別名)
crates/domain/src/entity/r1.rs:6: 読めない参照の形(根の別名)' \
  'U1 根そのものを use する 6 つの形(as の有無を問わない)は読めない形' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
use std::*;
use crate::*;
use super::super::*;
use application::*;
RS
run_case deny 'crates/domain/src/entity/r1.rs:1: 読めない参照の形(根の glob)
crates/domain/src/entity/r1.rs:2: 読めない参照の形(根の glob)
crates/domain/src/entity/r1.rs:3: 読めない参照の形(根の glob)
crates/domain/src/entity/r1.rs:4: 読めない参照の形(根の glob)' \
  'U2 根の glob の 4 つの形は読めない形' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'use super::super::super::Module;' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: 読めない参照の形(根より上の super)' \
  'U3 根より上へ上がる super は読めない形' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'extern crate std as standard;' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: 読めない参照の形(extern crate)' \
  'U4 extern crate は読めない形' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
#[path = "x.rs"] mod a;
#[cfg_attr(unix, path = "y.rs")] mod b;
fn f() { let path = 1; }
RS
run_case deny 'crates/domain/src/entity/r1.rs:1: 読めない参照の形(#[path])
crates/domain/src/entity/r1.rs:2: 読めない参照の形(#[path])' \
  'U5 #[path] と cfg_attr の中の path は読めない形で、let path = 1; は出さない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'include!("x.rs");' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: 読めない参照の形(include!)' \
  'U6 include! は読めない形' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'macro_rules! reexport { ($p:path) => { use $p; } }' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: 読めない参照の形(use の木)' \
  'U7 macro_rules! の中の use $p; は use の木' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/infrastructure/src/driver/r1.rs <<'RS' || exit 1
pub use std;
pub use std::fs as f;
pub(crate) use std::process::Command;
pub use std::os::unix;
use std::fs::read;
RS
run_case deny 'crates/infrastructure/src/driver/r1.rs:1: 読めない参照の形(根の別名)
crates/infrastructure/src/driver/r1.rs:2: 読めない参照の形(I/O か serde の再エクスポート)
crates/infrastructure/src/driver/r1.rs:3: 読めない参照の形(I/O か serde の再エクスポート)
crates/infrastructure/src/driver/r1.rs:4: 読めない参照の形(I/O か serde の再エクスポート)' \
  'U8 driver が pub の付いた use で I/O を再エクスポートする形は読めない形で、use std::fs::read; は出さない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/application/src/dto/r1.rs <<<'pub use serde::Serialize;' || exit 1
place_file crates/domain/src/aggregate/r1.rs <<<'pub use crate::entity::Module;' || exit 1
run_case deny 'crates/application/src/dto/r1.rs:1: 読めない参照の形(I/O か serde の再エクスポート)' \
  'U9 dto の pub use serde::Serialize; は読めない形で、フォルダの再エクスポートは出さない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/tightrope/src/sink/r1.rs <<'RS' || exit 1
use std as standard;
pub use std::fs;
RS
run_case deny 'crates/tightrope/src/sink/r1.rs:1: 読めない参照の形(根の別名)
crates/tightrope/src/sink/r1.rs:2: 読めない参照の形(I/O か serde の再エクスポート)' \
  'U10 相手の列が * の場所でも読めない形は出す' run_with_root "$tree"

# 字句を読まないこと

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'fn f() -> &'"'"'static str { "crate::policy" }' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: domain::policy(許可表の行 domain/src/entity|domain::value_object)' \
  'S1 文字列の中のパスも参照に数える' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'fn f() -> &'"'"'static str { "please use the --x flag" }' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: 読めない参照の形(use の木)' \
  'S2 文字列の中の use は use の木' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
// use crate::policy::Lean;
/// crate::policy::Lean
//! std::fs
    // serde
fn f() { crate::aggregate::build(); } // crate::policy::Lean
RS
run_case deny 'crates/domain/src/entity/r1.rs:5: domain::aggregate(許可表の行 domain/src/entity|domain::value_object)
crates/domain/src/entity/r1.rs:5: domain::policy(許可表の行 domain/src/entity|domain::value_object)' \
  'S3 行頭(字下げを除く)が // の行は数えず、行末の // の後ろは数える' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
fn f<'a>(x: &'a u8) -> impl Sized + use<'a> { x }
fn g() { crate::policy::Lean; }
RS
run_case deny 'crates/domain/src/entity/r1.rs:2: domain::policy(許可表の行 domain/src/entity|domain::value_object)' \
  'S4 impl Sized + use<'"'"'a> は use の宣言と読まない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'fn r#use() {} fn g() { r#serde(); }' || exit 1
run_case deny 'crates/domain/src/entity/r1.rs:1: serde(許可表の行 domain/src/entity|domain::value_object)' \
  'S5 r#use は use と読まず、r#serde は serde と読む' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
fn 名前() -> &'static str { let 値 = "あいう"; crate::policy::値::std::fs::read(); 値 }
fn g(c: char) -> bool { c == 'あ' }
RS
run_case deny 'crates/domain/src/entity/r1.rs:1: domain::policy(許可表の行 domain/src/entity|domain::value_object)' \
  'S6 非 ASCII の識別子は字句を崩さない(値::std はパスの続きの段)' run_with_root "$tree"

# 検査できない

place_tree_b || exit 1
rm -rf "$tree/crates" || exit 1
run_unavailable_case '^folder-deps: .*crates はディレクトリではありません' \
  'E1 crates が無ければ検査できない' run_with_root "$tree"

place_tree_b || exit 1
rm -f "$tree"/crates/*/Cargo.toml || exit 1
run_unavailable_case '^folder-deps: .*crates/\*/Cargo\.toml が 1 つもありません' \
  'E2 crates/*/Cargo.toml が 1 つも無ければ検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '[package]\nname = "dom"\nversion = "0.1.0"\nedition = "2024"\n' >"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[package\] の name' \
  'E3 [package] の name がディレクトリ名と違えば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '[package]\nversion = "0.1.0"\nedition = "2024"\n' >"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[package\] の name' \
  'E4 [package] の name が無ければ検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '\n[lib]\nname = "dom"\n' >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[lib\] の name' \
  'E5 [lib] の name がディレクトリ名と違えば検査できない' run_with_root "$tree"

place_tree_b || exit 1
place_member "$tree/crates/foo-bar" foo-bar || exit 1
run_unavailable_case '^folder-deps: .*crates/foo-bar の名前に - があります' \
  'E6 crates の下のディレクトリ名に - があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '%s\n' 'app = { package = "application", path = "../application" }' >>"$tree/crates/infrastructure/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/infrastructure/Cargo\.toml に依存の別名\(package =\)があります' \
  'E7 インラインの依存の別名(package =)があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '\n[dependencies.app]\npackage = "application"\npath = "../application"\n' >>"$tree/crates/presentation/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/presentation/Cargo\.toml に依存の別名\(package =\)があります' \
  'E8 [dependencies.app] の package = があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '\n[workspace.dependencies]\ns = { package = "serde", version = "1" }\n' >>"$tree/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: (.*/)?Cargo\.toml に依存の別名\(package =\)があります' \
  'E9 根の [workspace.dependencies] に依存の別名があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
failing_awk_prefix="$(failing_awk_path_prefix "$work")" || exit 1
run_unavailable_case '^folder-deps: .*走査に失敗' \
  'E10 awk が落ちれば、走査に失敗したことを出して検査できない' env PATH="$failing_awk_prefix$PATH" bash "$script" "$tree"

place_tree_b || exit 1
printf '\n[ lib ]\nname = "dom"\n' >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[lib\] の name' \
  'E11 見出しに空白がある [ lib ] の name がディレクトリ名と違えば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf 'lib.name = "dom"\n\n[package]\nname = "domain"\nversion = "0.1.0"\nedition = "2024"\n' \
  >"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の lib が見出し\(\[lib\]\)の外に書かれています' \
  'E12 見出しの外の lib.name = があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf 'lib = { name = "dom" }\n\n[package]\nname = "domain"\nversion = "0.1.0"\nedition = "2024"\n' \
  >"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の lib が見出し\(\[lib\]\)の外に書かれています' \
  'E13 見出しの外の lib = { … } があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '\n[lib]\npath = "tests/fixtures/lib.rs"\n' >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[lib\] に path = があります' \
  'E14 [lib] の path = があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '\n[[bin]]\nname = "x"\npath = "tests/fixtures/x.rs"\n' >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[bin\] に path = があります' \
  'E15 [[bin]] の path = があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '\n[[test]]\nname = "x"\npath = "tests/fixtures/x.rs"\n' >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[test\] に path = があります' \
  'E16 [[test]] の path = があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '\n[[example]]\nname = "x"\npath = "tests/fixtures/x.rs"\n' >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[example\] に path = があります' \
  'E17 [[example]] の path = があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '\n[[bench]]\nname = "x"\npath = "tests/fixtures/x.rs"\n' >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[bench\] に path = があります' \
  'E18 [[bench]] の path = があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '[package]\nname = "domain"\nbuild = "tests/fixtures/build.rs"\nversion = "0.1.0"\nedition = "2024"\n' \
  >"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[package\] に build = があります' \
  'E19 [package] の build = があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
mkdir -p "$work/script-alone" || exit 1
# 検査のスクリプトが無ければ写さずに走らせ、このケースだけを落とす(続くケースも走らせる)。
[ ! -f "$script" ] || cp "$script" "$work/script-alone/" || exit 1
run_unavailable_case '^folder-deps: .*test-file-path\.sh を読み込めません' \
  'E20 隣の test-file-path.sh を読み込めなければ、そのことを出して検査できない' \
  bash "$work/script-alone/folder-deps.sh" "$tree"

place_tree_b || exit 1
printf '\n["lib"]\nname = "dom"\n' >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[lib\] の name' \
  'E21 二重引用符の見出し ["lib"] の name がディレクトリ名と違えば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf "\n['lib']\nname = 'dom'\n" >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[lib\] の name' \
  "E22 一重引用符の見出し ['lib'] の name がディレクトリ名と違えば検査できない" run_with_root "$tree"

place_tree_b || exit 1
printf '\n[lib]\n"name" = "dom"\n' >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[lib\] の name' \
  'E23 [lib] の二重引用符のキー "name" がディレクトリ名と違えば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf "\n[lib]\n'name' = \"dom\"\n" >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[lib\] の name' \
  "E24 [lib] の一重引用符のキー 'name' がディレクトリ名と違えば検査できない" run_with_root "$tree"

place_tree_b || exit 1
printf '\n["lib"]\n"path" = "tests/fixtures/lib.rs"\n' >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[lib\] に path = があります' \
  'E25 ["lib"] の "path" = があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf '\n[["bin"]]\nname = "x"\npath = "tests/fixtures/x.rs"\n' >>"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[bin\] に path = があります' \
  'E26 [["bin"]] の path = があれば検査できない' run_with_root "$tree"

place_tree_b || exit 1
printf "['package']\nname = 'domain'\n\"build\" = 'tests/fixtures/build.rs'\nversion = '0.1.0'\nedition = '2024'\n" \
  >"$tree/crates/domain/Cargo.toml" || exit 1
run_unavailable_case '^folder-deps: .*crates/domain/Cargo\.toml の \[package\] に build = があります' \
  "E27 ['package'] の \"build\" = があれば検査できない" run_with_root "$tree"

# 見ない形

place_tree_b || exit 1
place_file crates/infrastructure/src/driver/r1.rs <<<'macro_rules! read_all { () => { std::fs::read("x") } }' || exit 1
place_file crates/infrastructure/src/translation/r1.rs <<<'fn f() { let _ = read_all!(); }' || exit 1
run_case miss '' 'M1 #[macro_use] で他のフォルダのマクロが展開する I/O は見ない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'fn f(p: &std::path::Path) -> bool { p.exists() }' || exit 1
run_case miss '' 'M2 名前に出ない I/O(Path::exists などのメソッド)は見ない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/infrastructure/src/driver/r1.rs <<<'pub type Handle = std::fs::File;' || exit 1
place_file crates/infrastructure/src/adapter/r1.rs <<<'use crate::driver::Handle;' || exit 1
run_case miss '' 'M3 driver の pub type を経由した I/O の型は見ない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
/// ```
/// use std::fs;
/// ```
pub fn f() {}
RS
run_case miss '' 'M4 doc の中の例(行頭が // の行の中身)は見ない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<<'#[cfg_attr(feature = "]", path = "x.rs")] mod a;' || exit 1
run_case miss '' 'M5 属性の中の文字列が ] を含むとき、その後ろの path = は見ない' run_with_root "$tree"

place_tree_b || exit 1
: >"$tree/crates/domain/src/service.rs" || exit 1
run_case miss '' 'M6 許可表に行が無いフォルダの空のファイルは、行が無いことを出さない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/infrastructure/src/driver/r1.rs <<'RS' || exit 1
use std::fs as x;
pub use self::x as reexported;
RS
run_case miss '' 'M7 I/O に付けた別名を pub use で再エクスポートする形は見ない' run_with_root "$tree"

place_tree_b || exit 1
printf 'use std::\342\200\216fs;\n' | place_file crates/domain/src/entity/r1.rs || exit 1
run_case miss '' 'M8 rustc が空白とみなす U+200E が識別子にくっついた語は見ない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
fn f() -> &'static str { "a
///"; std::fs::write("x", "y"); "b" }
RS
run_case miss '' 'M9 複数行の文字列の中で行頭が // になった行の後ろのコードは見ない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/domain/src/entity/r1.rs <<'RS' || exit 1
/*
/// */ use std::fs;
RS
run_case miss '' 'M10 ブロックコメントの中で行頭が // になった行の後ろのコードは見ない' run_with_root "$tree"

place_tree_b || exit 1
place_file crates/infrastructure/src/driver/r1.rs <<<'pub/**/use std::fs::File;' || exit 1
run_case miss '' 'M11 pub と use の間にコメントを挟んだ再エクスポートは見ない' run_with_root "$tree"

exit "$cases_failed"
