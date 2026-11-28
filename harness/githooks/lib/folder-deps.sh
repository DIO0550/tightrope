#!/usr/bin/env bash
#
# crate の中のファイルが、許可表(下の `allowed_dependencies`)に無い相手を参照していないかの検査
# (`rules/architecture.md`「依存方向のルール（必須要件）」)。相手は同じ crate の役割フォルダ・別の crate の
# 役割フォルダ・`std` の下の I/O のモジュール(awk の `is_io_module` が I/O とみなすもの)・`serde`。
# 外部 crate を使ってよいかは crate 単位で `crate-deps.sh` が見る。
#
# 使い方: bash harness/githooks/lib/folder-deps.sh [<workspace の根>]   (<workspace の根> の既定は .)
# 違反が無ければ何も出さずに exit 0。
# 違反があれば、見出しの下に違反の行を並べ替えて出し、exit 1。違反の行は次の形。
#   <ファイル>:<行>: <参照先>(許可表の行 <場所>|<参照してよい相手>)
#   <ファイル>:<行>: <参照先>(許可表の <crate>/src の行の和集合)
#   <場所>: 許可表に行が無い場所
#   <ファイル>[:<行>]: 読めない参照の形(<形>)
# 検査できないときは、理由を `folder-deps: <理由>` で標準エラーへ出して exit 2。理由は次のとおり。
#   隣の `test-file-path.sh` を読み込めない / <根>/crates がディレクトリでない /
#   `<根>/crates/*/Cargo.toml` が 1 つも無い / crate のディレクトリ名に `-` がある /
#   `[package]` の name が無いかディレクトリ名と違う / `[lib]` の name がディレクトリ名と違う /
#   `[package]` か `[lib]` の name が 3 重引用符の文字列(`"""…"""` / `'''…'''`)で読めない /
#   crate の Cargo.toml が `[lib]` / `[[bin]]` / `[[test]]` / `[[example]]` / `[[bench]]` に `path =` を、
#   `[package]` に `build =` を書いている / crate の Cargo.toml が `lib` を見出し(`[lib]`)の外に書いている /
#   crate の Cargo.toml か根の Cargo.toml に依存の別名(`package =`)がある / 走査(find か awk)に失敗した。
#   Cargo.toml の見出しの名前とキーは、引用符を外して読む(`["lib"]` は `[lib]`、`"name" =` は `name =`)
# 参照に出る crate 名を `crates/` の下のディレクトリ名とみなし、crate の本体が `crates/` の下の決まった場所に
# あるとみなして照らすので、そうみなせない workspace は検査しない。
#
# ファイルの場所(`<根>/crates` からのパスで決める)
# - `<crate>/src/lib.rs` と `<crate>/src/main.rs` は、それぞれが 1 つの場所
# - `<crate>/src/<名前>.rs` と `<crate>/src/<名前>/` の下は `<crate>/src/<名前>`。単体テスト(`tests.rs` と
#   `tests/<観点>.rs`)もそのフォルダの場所。`<crate>/src/tests.rs` は `<crate>/src/tests`
# - `<crate>/tests/` の下(結合テスト)は、その crate の `<crate>/src/` の行の相手をすべて合わせたものに、
#   各フォルダ `<crate>::<フォルダ>` を足して照らす。`crate::` / `self::` / `super::` で始まる参照は照らさない。
#   `<crate>/tests/fixtures/` の下は見ない(`fixtures_pattern`)。ただしその直下の `main.rs` と `mod.rs` は
#   読めない参照の形として出す
# - それ以外は `<crate>/<最初の段>`(`build.rs` / `examples` など)。Cargo.toml の無いディレクトリも
#   `<ディレクトリ>/<最初の段>`
# - 許可表に行が無い場所は 1 行だけ出し、そこのファイルの参照は照らさない(読めない参照の形は出す)
#
# 拾う参照
# - 行頭(字下げを除く)が `//` の行は読まない。文字列・ブロックコメントの中は読み分けずに参照として数える
# - `use` の宣言(グループ・入れ子・`self`・`as` を展開する)と、式・型の中の `crate` / `self` / `super` /
#   `std` / crate 名で始まるパス。直前が `<識別子>::` の語は、その識別子が Rust のキーワードでもライフタイム
#   (`'a` の `a`)でもなければパスの途中の段なので、根として読まない(`foo::std::fs`)。`std::` の下は
#   `is_io_module` のものだけを照らす
# - 識別子 `serde` は、use の中か外か・パスのどの段かを問わず `serde` と数える
# - `super` はファイルの深さ(`src/` からの段の数。`mod.rs` は 1 段浅い)と比べ、根まで上がれば次の段を
#   フォルダとして照らす。自分のフォルダへの参照は照らさない。inline の `mod` は段に数えないので、その中の
#   `super` は根の側へずれ、誤検知の側に倒れる
#
# 読めない参照の形(行が無い場所・相手の列が `*` の場所でも出す)
#   `#[path]`(`cfg_attr` の中を含む)/ `include!` / `extern crate` / 根の別名(`use std;` / `use crate as x;` など) /
#   根の glob(`use crate::*;` など)/ 根より上の super / use の木(展開できない use)/
#   `::` の後ろが識別子でないパス(`std::/**/fs`。型引数の `::<` は除く)/
#   I/O か serde の再エクスポート(`pub` の付いた use の葉が `is_io_module` の std の下か、段に `serde` を持つ)/
#   tests/fixtures の main.rs か mod.rs(Cargo が結合テストとして拾うか、`mod fixtures;` で取り込める)/
#   シンボリックリンク(`fixtures_pattern` の下は、直下の `main.rs` と `mod.rs` だけ)
#
# 見ない形
# - マクロの展開先(`$crate::` は定義した側で拾う)
# - 名前に出ない I/O(`Path::exists` などのメソッド、`pub type` を経由した I/O の型)と、`std::io` / `std::env` /
#   `std::net`(infrastructure では、このうち `crates/domain` の clippy の一覧に並ぶメソッドと項目を `io-outside-driver.sh` が
#   見る。`pub type` を経由した I/O の型は、`io-outside-driver.sh` も見ない)
# - `pub` の付いた use が、I/O や serde に付けた別名を再エクスポートする形(`use std::fs as x; pub use self::x;`)
# - 行頭が `//` の行の中身(doc の例と、複数行の文字列・ブロックコメントの中で行頭が `//` になった行の
#   後ろのコードを含む)
# - 字句の区切りが Rust と合わない形: rustc が空白とみなす ASCII 以外の文字(U+200E など)が識別子に
#   くっついた語 / `pub` と `use` の間にコメントを挟んだ use(`pub/**/use`)の再エクスポート
# - 属性の中の文字列が `]` を含むときの、その後ろの `path =`
# - 空のファイルの場所に、許可表の行があるか(参照を持たないので、隠れる参照も無い)
#
# macOS の /bin/bash(3.2)でも走るよう、連想配列など bash 4 以降の機能は使わない。

set -uo pipefail

# 検査できなかった理由を標準エラーへ出し、exit 2 で終える。
#
# $1 理由
exit_unavailable() {
  printf 'folder-deps: %s\n' "$1" >&2
  exit 2
}

here="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$here/test-file-path.sh" || exit_unavailable "$here/test-file-path.sh を読み込めません"

root="${1:-.}"

# 許可表。1 行 `<場所>|<参照してよい相手>`。場所は `crates/` からのパスで、完全一致で引く。相手は空白区切りの
# `<crate>::<フォルダ>` / `<crate>::*`(その crate の下すべて)/ `std::<モジュール>`(`is_io_module` が
# I/O とみなすもの)/ `serde` / `*`(すべて)。空の列は何も許さない。
allowed_dependencies="$(cat <<'allowed_dependencies'
domain/src/lib.rs|
domain/src/value_object|
domain/src/entity|domain::value_object
domain/src/policy|domain::value_object
domain/src/aggregate|domain::entity domain::value_object
domain/src/workflow|domain::policy domain::aggregate domain::entity domain::value_object
application/src/lib.rs|
application/src/dto|serde
application/src/port|application::dto
application/src/mapping|application::dto domain::*
application/src/usecase|application::port application::mapping application::dto application::error domain::*
application/src/error|application::dto
infrastructure/src/lib.rs|
infrastructure/src/driver|std::fs std::process std::os
infrastructure/src/translation|application::dto
infrastructure/src/adapter|infrastructure::driver infrastructure::translation application::port application::dto
presentation/src/lib.rs|
presentation/src/controller|application::dto
presentation/src/view_model|
presentation/src/presenter|presentation::view_model application::dto application::error
presentation/src/view|presentation::view_model application::dto
tightrope/src/lib.rs|*
tightrope/src/main.rs|*
tightrope/src/composition|*
tightrope/src/sink|*
tightrope/src/exit_code|*
allowed_dependencies
)"

heading='フォルダの依存が許可表にありません(許可表は harness/githooks/lib/folder-deps.sh の allowed_dependencies)'

# 見ない結合テストの置き場(`crates/` から始まるパスに当てる拡張正規表現)。
fixtures_pattern='^crates/[^/]+/tests/fixtures/'
# 見ない置き場の中で、Cargo が結合テストとして拾うか `mod fixtures;` で取り込めるファイル。
fixtures_entry_pattern="${fixtures_pattern}(main|mod)[.]rs\$"

# 参照を拾い、場所を決め、許可表と照らして、違反の行を 1 行 1 件で出す awk。ファイルごとに字句を溜め、
# 最後の行を読んだ後(`end_file`)にまとめて読む。許可表は環境変数 `FOLDER_DEPS_TABLE`、crate 名は
# 空白区切りの `FOLDER_DEPS_CRATES`、見ない置き場は `FOLDER_DEPS_FIXTURES` と `FOLDER_DEPS_FIXTURES_ENTRY` で
# 受け取る。同じ行は bash が `sort -u` でまとめる。
violations_awk='
function is_ident_char(c) { return c ~ /[A-Za-z0-9_]/ || c > "\177" }
function is_ident(t,   head) {
  if (t ~ /^r#/) return 1
  head = substr(t, 1, 1)
  if (head ~ /[0-9]/) return 0
  return is_ident_char(head)
}
function is_io_module(m) { return m == "fs" || m == "process" || m == "os" }
function is_serde(t) { return t == "serde" }
function is_relative_root(t) { return t == "crate" || t == "self" || t == "super" }
function is_path_root(t) {
  if (t == "std") return 1
  if (t in crate_names) return 1
  return is_relative_root(t)
}
function is_crate_root_name(name) { return name == "lib.rs" || name == "main.rs" }
function emit(t, ln) { ntok++; tok[ntok] = t; tline[ntok] = ln }
function ident_end(line, i,   n) {
  n = length(line)
  for (; i <= n; i++) if (!is_ident_char(substr(line, i, 1))) return i
  return i
}
function opens_raw_ident(line, w, j) {
  if (w != "r") return 0
  if (substr(line, j, 1) != "#") return 0
  return is_ident_char(substr(line, j + 1, 1))
}
function opens_dollar_crate(line, i) {
  if (substr(line, i, 6) != "$crate") return 0
  return !is_ident_char(substr(line, i + 6, 1))
}
function emit_word_at(line, i,   j, k, w) {
  j = ident_end(line, i)
  w = substr(line, i, j - i)
  if (!opens_raw_ident(line, w, j)) { emit(w, FNR); return j }
  k = ident_end(line, j + 1)
  w = substr(line, j + 1, k - j - 1)
  if (w in raw_keyword) w = "r#" w
  emit(w, FNR)
  return k
}
function emit_token_at(line, i,   c) {
  c = substr(line, i, 1)
  if (is_ident_char(c)) return emit_word_at(line, i)
  if (opens_dollar_crate(line, i)) { emit("crate", FNR); return i + 6 }
  if (substr(line, i, 2) == "::") { emit("::", FNR); return i + 2 }
  if (c ~ /[ \t\r]/) return i + 1
  emit(c, FNR)
  return i + 1
}
function emit_tokens_of(line,   n, i) {
  n = length(line)
  for (i = 1; i <= n; ) i = emit_token_at(line, i)
}
function begin_file() {
  ntok = 0
  path = "crates/" relative_path_of(FILENAME)
  skipping = (path ~ fixtures_pattern)
  if (path ~ fixtures_entry_pattern) print path ": 読めない参照の形(tests/fixtures の main.rs か mod.rs)"
}
FNR == 1 { if (current != "") end_file(); current = FILENAME; begin_file() }
skipping { next }
/^[ \t]*\/\// { next }
{ emit_tokens_of($0) }
END { if (current != "") end_file() }
function join(a, b) { if (a == "") return b; if (b == "") return a; return a "::" b }
function report(ln, msg) { print path ":" ln ": " msg }
function report_unreadable(ln, form) { report(ln, "読めない参照の形(" form ")") }
function locate(   rel, parts, np, first, names_crate_root) {
  rel = path; sub(/^crates\//, "", rel)
  np = split(rel, parts, "/")
  crate = parts[1]; kind = "other"; own = ""; depth = 0
  if (np == 1) { location = rel; return }
  if (!(crate in crate_names)) { location = crate "/" parts[2]; return }
  if (parts[2] == "tests") { location = crate "/tests"; kind = "integration"; return }
  if (parts[2] != "src") { location = crate "/" parts[2]; return }
  kind = "src"
  first = parts[3]
  names_crate_root = (np == 3 && is_crate_root_name(first))
  if (names_crate_root) { location = crate "/src/" first; return }
  sub(/\.rs$/, "", first)
  location = crate "/src/" first; own = crate "::" first
  depth = np - 2
  if (parts[np] == "mod.rs") depth--
}
function allowed_targets_of(loc,   r, prefix, union, name, found) {
  if (loc in table) return table[loc]
  if (kind != "integration") return "-"
  prefix = crate "/src/"
  union = ""; found = 0
  for (r in table) {
    if (index(r, prefix) != 1) continue
    found = 1
    union = union " " table[r]
    name = substr(r, length(prefix) + 1)
    if (is_crate_root_name(name)) continue
    union = union " " crate "::" name
  }
  if (!found) return "-"
  return union
}
function row_label(loc) {
  if (loc in table) return "許可表の行 " loc "|" table[loc]
  return "許可表の " crate "/src の行の和集合"
}
function pattern_allows(p, ref) {
  if (p == "*") return 1
  if (p == ref) return 1
  if (p !~ /::\*$/) return 0
  return index(ref, substr(p, 1, length(p) - 1)) == 1
}
function allows(allowed, ref,   pats, np, q) {
  np = split(allowed, pats, " ")
  for (q = 1; q <= np; q++) if (pattern_allows(pats[q], ref)) return 1
  return 0
}
function check(ref, ln) {
  if (ref == own) return
  if (allowed == "-") return
  if (allows(allowed, ref)) return
  report(ln, ref "(" row_label(location) ")")
}
function names_serde(s, ns,   q) {
  for (q = 1; q <= ns; q++) if (is_serde(s[q])) return 1
  return 0
}
function root_end_of(s, ns,   idx, ups) {
  if (s[1] == "std") { path_root = "std"; return 2 }
  if (s[1] in crate_names) { path_root = s[1]; return 2 }
  if (!is_relative_root(s[1])) return 0
  if (kind == "integration") return 0
  path_root = crate
  if (s[1] == "crate") return 2
  idx = 1
  if (s[1] == "self") idx = 2
  ups = 0
  for (; idx <= ns; idx++) { if (s[idx] != "super") break; ups++ }
  if (depth - ups >= 1) return 0
  if (depth - ups < 0) return -1
  return idx
}
function report_path_violations(p, in_use, is_pub, ln,   s, ns, at, reexports_serde) {
  ns = split(p, s, "::")
  reexports_serde = (is_pub && names_serde(s, ns))
  if (reexports_serde) report_unreadable(ln, reexport_form)
  at = root_end_of(s, ns)
  if (at == 0) return
  if (at < 0) { report_unreadable(ln, "根より上の super"); return }
  if (at > ns) { if (in_use) report_unreadable(ln, "根の別名"); return }
  if (s[at] == "*") { report_unreadable(ln, "根の glob"); return }
  if (path_root != "std") { check(path_root "::" s[at], ln); return }
  if (!is_io_module(s[at])) return
  check("std::" s[at], ln)
  if (is_pub) report_unreadable(ln, reexport_form)
}
function parse_use(k, is_pub,   sp, stack, leaf, leaf_line, t, closes_self) {
  sp = 1; stack[1] = ""; leaf = ""
  for (; k <= ntok; k++) {
    t = tok[k]
    if (t == ";") { if (leaf != "") report_path_violations(join(stack[sp], leaf), 1, is_pub, leaf_line); return k }
    if (t == "::") { if (leaf == "") leaf_line = tline[k]; continue }
    if (t == "{") { sp++; stack[sp] = join(stack[sp - 1], leaf); leaf = ""; continue }
    if (t == "," || t == "}") {
      closes_self = (leaf == "self" && stack[sp] != "")
      if (closes_self) report_path_violations(stack[sp], 1, is_pub, leaf_line)
      else if (leaf != "") report_path_violations(join(stack[sp], leaf), 1, is_pub, leaf_line)
      leaf = ""
      if (t == "}") sp--
      if (sp < 1) { report_unreadable(tline[k], "use の木"); return k }
      continue
    }
    if (t == "as") { k++; continue }
    if (t == "*") { if (leaf == "") leaf_line = tline[k]; leaf = join(leaf, "*"); continue }
    if (is_ident(t)) { if (leaf == "") leaf_line = tline[k]; leaf = join(leaf, t); continue }
    report_unreadable(tline[k], "use の木"); return k
  }
  report_unreadable(tline[ntok], "use の木")
  return k
}
function opening_paren_of(k,   d) {
  d = 0
  for (; k >= 1; k--) {
    if (tok[k] == ")") d++
    if (tok[k] != "(") continue
    d--
    if (d == 0) return k
  }
  return 0
}
function is_pub_before(k,   open) {
  if (k <= 1) return 0
  if (tok[k - 1] == "pub") return 1
  if (tok[k - 1] != ")") return 0
  open = opening_paren_of(k - 1)
  if (open <= 1) return 0
  return tok[open - 1] == "pub"
}
function opens_attribute(k) {
  if (tok[k] != "#") return 0
  if (tok[k + 1] == "[") return 1
  if (tok[k + 1] != "!") return 0
  return tok[k + 2] == "["
}
function sets_path(k) { if (tok[k] != "path") return 0; return tok[k + 1] == "=" }
function report_attribute_paths(   k, inside, bracket_depth) {
  inside = 0
  for (k = 1; k <= ntok; k++) {
    if (opens_attribute(k)) { inside = 1; bracket_depth = 0; continue }
    if (!inside) continue
    if (tok[k] == "[") bracket_depth++
    if (tok[k] == "]") { bracket_depth--; inside = (bracket_depth > 0) }
    if (sets_path(k)) report_unreadable(tline[k], "#[path]")
  }
}
function is_extern_crate(k) { if (tok[k] != "extern") return 0; return tok[k + 1] == "crate" }
function is_include_macro(k) { if (tok[k] != "include") return 0; return tok[k + 1] == "!" }
function opens_use_declaration(k) { if (tok[k] != "use") return 0; return tok[k + 1] != "<" }
function names_lifetime(k) { if (k <= 1) return 0; return tok[k - 1] == "\047" }
function is_path_continuation(k,   before) {
  if (k <= 2) return 0
  if (tok[k - 1] != "::") return 0
  before = tok[k - 2]
  if (!is_ident(before)) return 0
  if (before in rust_keyword) return 0
  return !names_lifetime(k - 2)
}
function starts_path(k) { if (!is_path_root(tok[k])) return 0; return tok[k + 1] == "::" }
function continues_path(k,   segment) {
  if (tok[k + 1] != "::") return 0
  segment = tok[k + 2]
  if (segment == "*") return 1
  return is_ident(segment)
}
function report_expression_path(k,   p, ln, cut) {
  p = tok[k]; ln = tline[k]
  for (; continues_path(k); k += 2) p = p "::" tok[k + 2]
  cut = (tok[k + 1] == "::" && tok[k + 2] != "<")
  if (cut) report_unreadable(ln, ":: の後ろが識別子でないパス")
  report_path_violations(p, 0, 0, ln)
  return k
}
function report_violations_at(k) {
  if (is_extern_crate(k)) { report_unreadable(tline[k], "extern crate"); return k }
  if (is_include_macro(k)) { report_unreadable(tline[k], "include!"); return k }
  if (opens_use_declaration(k)) return parse_use(k + 1, is_pub_before(k))
  if (is_path_continuation(k)) return k
  if (starts_path(k)) return report_expression_path(k)
  return k
}
function end_file(   k) {
  if (skipping) return
  tok[ntok + 1] = ""; tok[ntok + 2] = ""; tok[ntok + 3] = ""
  locate()
  allowed = allowed_targets_of(location)
  if (allowed == "-") print location ": 許可表に行が無い場所"
  for (k = 1; k <= ntok; k++) if (is_serde(tok[k])) check("serde", tline[k])
  report_attribute_paths()
  for (k = 1; k <= ntok; k++) k = report_violations_at(k)
}
BEGIN {
  nrows = split(ENVIRON["FOLDER_DEPS_TABLE"], rows, "\n")
  for (r = 1; r <= nrows; r++) {
    if (rows[r] == "") continue
    bar = index(rows[r], "|")
    table[substr(rows[r], 1, bar - 1)] = substr(rows[r], bar + 1)
  }
  nc = split(ENVIRON["FOLDER_DEPS_CRATES"], names, " ")
  for (r = 1; r <= nc; r++) crate_names[names[r]] = 1
  fixtures_pattern = ENVIRON["FOLDER_DEPS_FIXTURES"]
  fixtures_entry_pattern = ENVIRON["FOLDER_DEPS_FIXTURES_ENTRY"]
  reexport_form = "I/O か serde の再エクスポート"
  nw = split("as break const continue else enum extern false fn for if impl in let loop match mod move mut pub ref return static struct trait true type unsafe use where while async await dyn abstract become box do final macro override priv typeof unsized virtual yield try gen", words, " ")
  for (r = 1; r <= nw; r++) { rust_keyword[words[r]] = 1; raw_keyword[words[r]] = 1 }
  raw_keyword["crate"] = 1; raw_keyword["self"] = 1; raw_keyword["super"] = 1
}
'

# Cargo.toml の行が依存の別名(`package =`)を書いているか。`[package]` の見出しには当たらない。
rename_pattern='(^|[^A-Za-z0-9_-])["'"'"']?package["'"'"']?[[:space:]]*='
# TOML の表の見出し(`[package]` / `[[bin]]` / `["lib"]`)。1 つ目の組が、空白と引用符を除く前の表の名前。
section_pattern='^[[:space:]]*\[+([^]]*)\]+'
# 見出しの名前から除く文字(空白と引用符)。
section_noise='[[:space:]"'"'"']'
# 表の中の `name = "<名前>"`(キーは引用符で囲んでもよい)。1 つ目の組が名前。
name_pattern='^[[:space:]]*["'"'"']?name["'"'"']?[[:space:]]*=[[:space:]]*["'"'"']([^"'"'"']*)["'"'"']'
# 表の中の、値が 3 重引用符の文字列(`"""…"""` / `'''…'''`)の `name =`。`name_pattern` はこの値を空の名前と読む。
triple_quoted_name_pattern='^[[:space:]]*["'"'"']?name["'"'"']?[[:space:]]*=[[:space:]]*("""|'"'''"')'
# target の表の中の `path =`。
path_key_pattern='^[[:space:]]*["'"'"']?path["'"'"']?[[:space:]]*='
# `[package]` の中の `build =`。
build_key_pattern='^[[:space:]]*["'"'"']?build["'"'"']?[[:space:]]*='
# 見出しより前の、`lib` を見出しの外で書く行(`lib.name =` / `lib = { … }`)。
lib_key_pattern='^[[:space:]]*["'"'"']?lib["'"'"']?[[:space:]]*[.=]'

# Cargo.toml が依存の別名を書いていれば、検査できないとして終える。
#
# $1 Cargo.toml のパス
exit_if_renamed() {
  local line
  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" =~ $rename_pattern ]] && exit_unavailable "$1 に依存の別名(package =)があります"
  done <"$1"
  return 0
}

# Cargo.toml の 1 行が crate の本体の場所を変えうる書き方(target の `path =`・`[package]` の `build =`・
# 見出しの外の `lib`)なら、検査できないとして終える。
#
# $1 Cargo.toml のパス
# $2 その行がある表の名前(空白と引用符を除いたもの。見出しより前なら空)
# $3 行
exit_if_sources_relocated() {
  local manifest="$1" section="$2" line="$3"
  case "$section" in
    lib | bin | test | example | bench)
      [[ "$line" =~ $path_key_pattern ]] &&
        exit_unavailable "$manifest の [$section] に path = があります(crate の本体を走査の外へ出せる)"
      ;;
    package)
      [[ "$line" =~ $build_key_pattern ]] &&
        exit_unavailable "$manifest の [package] に build = があります(build script を走査の外へ出せる)"
      ;;
    '')
      [[ "$line" =~ $lib_key_pattern ]] &&
        exit_unavailable "$manifest の lib が見出し([lib])の外に書かれています"
      ;;
  esac
  return 0
}

# Cargo.toml の 1 行が `[package]` か `[lib]` の name を 3 重引用符の文字列で書いていれば、検査できないとして終える。
#
# $1 Cargo.toml のパス
# $2 その行がある表の名前(空白と引用符を除いたもの。見出しより前なら空)
# $3 行
exit_if_name_unreadable() {
  local manifest="$1" section="$2" line="$3"
  case "$section" in
    package | lib) ;;
    *) return 0 ;;
  esac
  [[ "$line" =~ $triple_quoted_name_pattern ]] &&
    exit_unavailable "$manifest の [$section] の name が 3 重引用符の文字列で読めません"
  return 0
}

# crate の Cargo.toml を読み、参照に出る crate 名をそのディレクトリ名とみなせなければ、検査できないとして終える。
#
# $1 Cargo.toml のパス
# $2 crate のディレクトリ名
exit_unless_named_after_directory() {
  local manifest="$1" crate_dir="$2" line section='' package_name='' lib_name='' lib_name_differs=no
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ $section_pattern ]]; then
      section="${BASH_REMATCH[1]//$section_noise/}"
      continue
    fi
    exit_if_sources_relocated "$manifest" "$section" "$line"
    exit_if_name_unreadable "$manifest" "$section" "$line"
    [[ "$line" =~ $name_pattern ]] || continue
    case "$section" in
      package) package_name="${BASH_REMATCH[1]}" ;;
      lib) lib_name="${BASH_REMATCH[1]}" ;;
    esac
  done <"$manifest"
  [ -n "$package_name" ] || exit_unavailable "$manifest の [package] の name がありません"
  [ "$package_name" = "$crate_dir" ] ||
    exit_unavailable "$manifest の [package] の name($package_name)がディレクトリ名($crate_dir)と違います"
  [ -n "$lib_name" ] && [ "$lib_name" != "$crate_dir" ] && lib_name_differs=yes
  [ "$lib_name_differs" = no ] ||
    exit_unavailable "$manifest の [lib] の name($lib_name)がディレクトリ名($crate_dir)と違います"
  return 0
}

[ -d "$root/crates" ] || exit_unavailable "$root/crates はディレクトリではありません"

# 参照に出る crate 名とみなす、`crates/` の下のディレクトリ名(空白区切り)。
crate_names=''
for manifest in "$root"/crates/*/Cargo.toml; do
  [ -f "$manifest" ] || continue
  crate_dir="$(basename "$(dirname "$manifest")")"
  case "$crate_dir" in
    *-*) exit_unavailable "$root/crates/$crate_dir の名前に - があります(参照に出る crate 名は _ になる)" ;;
  esac
  exit_if_renamed "$manifest"
  exit_unless_named_after_directory "$manifest" "$crate_dir"
  crate_names="$crate_names $crate_dir"
done
[ -n "$crate_names" ] || exit_unavailable "$root/crates/*/Cargo.toml が 1 つもありません"
if [ -f "$root/Cargo.toml" ]; then
  exit_if_renamed "$root/Cargo.toml"
fi

# `find -type f` はシンボリックリンクを辿らないので、リンクは読めない参照の形として別に出す。
symlinks="$(CDPATH= cd -- "$root" && find crates -type l)"
symlink_status=$?
[ "$symlink_status" -eq 0 ] ||
  exit_unavailable "$root/crates のシンボリックリンクの走査に失敗しました(終了コード $symlink_status)"

violations="$(FOLDER_DEPS_TABLE="$allowed_dependencies" FOLDER_DEPS_CRATES="$crate_names" \
  FOLDER_DEPS_FIXTURES="$fixtures_pattern" FOLDER_DEPS_FIXTURES_ENTRY="$fixtures_entry_pattern" LC_ALL=C \
  awk_rs_files_under "$root/crates" "$test_file_path_awk$violations_awk")"
scan_status=$?
[ "$scan_status" -eq 0 ] || exit_unavailable "$root/crates の走査に失敗しました(終了コード $scan_status)"

symlink_violations="$(
  {
    printf '%s\n' "$symlinks" | grep -Ev -e '^$' -e "$fixtures_pattern"
    printf '%s\n' "$symlinks" | grep -E -e "$fixtures_entry_pattern"
  } | sed 's/$/: 読めない参照の形(シンボリックリンク)/'
)"

found="$(printf '%s\n%s\n' "$violations" "$symlink_violations" | grep -v '^$' | LC_ALL=C sort -u)"
if [ -z "$found" ]; then
  exit 0
fi

echo "$heading"
printf '%s\n' "$found"
exit 1
