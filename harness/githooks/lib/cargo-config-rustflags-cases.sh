#!/usr/bin/env bash
#
# cargo の設定の rustflags の検査(`cargo-config-rustflags.sh`)の判定表。
#
# ケースごとに使い捨ての木を組み直し(根は `$work/tree`。M1 はその下の `inner/`、E1 はファイル。cargo は走らせない)、
# 検査を走らせる。
# どのケースも `place_tree` が置く根(空の `.cargo/` だけを持つ)に、決まったパス(多くは `.cargo/config.toml`)へ
# 中身を直に書いて組む。
# 1 ケースの判定の綴りと、それをどう照らすかは `cases-allowlist.sh` の `decision_of`。期待の違反の行は、
# このファイルに直に書く。
# 走らせ方は、ケースの `run_case` / `run_unavailable_case` の後ろに渡すコマンド(多くは根を引数に渡す
# `run_with_root`)。例外は 3 つで、D1 は根をカレントにして引数なしで呼び(`run_in_root`)、E2 は失敗する awk を
# PATH の先頭に置いて、E3 は検査のスクリプトだけを別のディレクトリへ写して呼ぶ。
# 見出し「検査できない」の下のケースは、検査できなかった理由が標準エラーに出るかまで照らす(`cases-allowlist.sh` の
# `run_unavailable_case`)。見出し「見ない形」の下のケースは検査が見ない形で、期待は `miss`。
#
# 使い方: bash harness/githooks/lib/cargo-config-rustflags-cases.sh
# 食い違ったケースがあれば exit 1(`ok` だけなら期待どおり)。

set -uo pipefail

here="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
script="$here/cargo-config-rustflags.sh"

source "$here/../../../.claude/hooks/lib/cases-report.sh"
source "$here/../../../.claude/hooks/lib/cases-fixtures.sh"
source "$here/cases-allowlist.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT

tree="$work/tree"

# 検査が違反を報告するときの見出し。
heading='^cargo の設定に、'

# 多くのケースが中身を書くファイル。
config_toml="$tree/.cargo/config.toml"

# 前のケースの木を消し、空の `.cargo/` だけを持つ根を置く。
place_tree() {
  rm -rf "$work/outer" "$tree" || return 1
  mkdir -p "$tree/.cargo" || return 1
}

# 落とす形

place_tree || exit 1
printf '[build]\nrustflags = ["-A", "clippy::unwrap_used"]\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:2: rustflags = ["-A", "clippy::unwrap_used"]' \
  'C1 [build] の rustflags を落とし、その行を出す' run_with_root "$tree"

place_tree || exit 1
printf '[target.x86_64-unknown-linux-gnu]\nrustflags = ["-A", "warnings"]\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:2: rustflags = ["-A", "warnings"]' \
  'C2 [target.<triple>] の rustflags を落とす' run_with_root "$tree"

place_tree || exit 1
printf "[target.'cfg(all())']\nrustflags = [\"-W\", \"clippy::unwrap_used\"]\n" >"$config_toml" || exit 1
run_case deny ".cargo/config.toml:2: rustflags = [\"-W\", \"clippy::unwrap_used\"]" \
  "C3 [target.'cfg(all())'] の rustflags の -W を落とす(値は見ない)" run_with_root "$tree"

place_tree || exit 1
printf 'build.rustflags = ["-A", "warnings"]\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:1: build.rustflags = ["-A", "warnings"]' \
  'C4 点つきキー build.rustflags を落とす' run_with_root "$tree"

place_tree || exit 1
printf 'build = { rustflags = ["-A", "warnings"] }\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:1: build = { rustflags = ["-A", "warnings"] }' \
  'C5 インラインの表の中の rustflags を落とす' run_with_root "$tree"

place_tree || exit 1
printf '[build]\n"rustflags" = ["-A", "warnings"]\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:2: "rustflags" = ["-A", "warnings"]' \
  'C6 引用符つきキー "rustflags" を落とす' run_with_root "$tree"

place_tree || exit 1
printf '[build]\n"rust\\u0066lags" = ["-A", "warnings"]\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:2: "rust\u0066lags" = ["-A", "warnings"]' \
  'C7 \u で綴ったキーを落とす' run_with_root "$tree"

place_tree || exit 1
printf '[build]\n"rust\\U00000066lags" = ["-A", "warnings"]\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:2: "rust\U00000066lags" = ["-A", "warnings"]' \
  'C8 \U で綴ったキーを落とす' run_with_root "$tree"

place_tree || exit 1
printf '[build]\nrustflags = [\n  "-A",\n  "warnings",\n]\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:2: rustflags = [' \
  'C9 複数行の配列は、キーの行だけを出す' run_with_root "$tree"

place_tree || exit 1
printf '[build]\nrustflags = ["-C", "target-cpu=native"]\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:2: rustflags = ["-C", "target-cpu=native"]' \
  'C10 lint と関係の無い rustflags も落とす' run_with_root "$tree"

place_tree || exit 1
printf '[profile.dev]\nrustflags = ["-A", "warnings"]\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:2: rustflags = ["-A", "warnings"]' \
  'C11 [profile.dev] の rustflags も落とす' run_with_root "$tree"

place_tree || exit 1
printf 'include = ["../extra.toml"]\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:1: include = ["../extra.toml"]' \
  'C12 include を落とす' run_with_root "$tree"

place_tree || exit 1
printf '[build]\nrustflags = ["-A", "warnings"]\n' >"$tree/.cargo/config" || exit 1
run_case deny '.cargo/config:2: rustflags = ["-A", "warnings"]' \
  'C13 旧名の .cargo/config も見る' run_with_root "$tree"

place_tree || exit 1
printf '[build]\nrustflags = ["-A", "warnings"]\n' >"$config_toml" || exit 1
mkdir -p "$tree/crates/a/.cargo" || exit 1
printf 'build.rustflags = ["-A", "warnings"]\n' >"$tree/crates/a/.cargo/config.toml" || exit 1
run_case deny '.cargo/config.toml:2: rustflags = ["-A", "warnings"]
crates/a/.cargo/config.toml:1: build.rustflags = ["-A", "warnings"]' \
  'C14 根と crates/a/.cargo/config.toml の両方を見る' run_with_root "$tree"

place_tree || exit 1
printf '[build]\nrustflags = ["-A", "warnings"]\n' >"$tree/linked.toml" || exit 1
ln -s ../linked.toml "$config_toml" || exit 1
run_case deny '.cargo/config.toml: シンボリックリンク' \
  'C15 .cargo/config.toml がファイルへのリンクなら、リンク先を読まずにその場所を出す' run_with_root "$tree"

place_tree || exit 1
printf '[build]\njobs = 2 # rustflags は使わない\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:2: jobs = 2 # rustflags は使わない' \
  'C16 行末のコメントの中の語も出す' run_with_root "$tree"

place_tree || exit 1
printf '# rustflags = ["-A", "warnings"]\n  # "rust\\u0066lags" = []\n[build]\nrustflags = ["-A", "warnings"]\n' \
  >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:1: # rustflags = ["-A", "warnings"]
.cargo/config.toml:2:   # "rust\u0066lags" = []
.cargo/config.toml:4: rustflags = ["-A", "warnings"]' \
  'C17 コメント行(字下げしたものも)の語と \ も拾う' run_with_root "$tree"

place_tree || exit 1
printf '[build]\nrustflags = ["-A", "warnings"]\n' >"$config_toml" || exit 1
printf 'build.rustflags = ["-A", "warnings"]\n' >"$tree/config.toml" || exit 1
mkdir -p "$tree/crates/a" || exit 1
printf 'build.rustflags = ["-A", "warnings"]\n' >"$tree/crates/a/config.toml" || exit 1
printf 'additional_cargo_args = ["--config", "build.rustflags=[]"]\n' >"$tree/.cargo/mutants.toml" || exit 1
run_case deny '.cargo/config.toml:2: rustflags = ["-A", "warnings"]' \
  'C18 .cargo の外の config.toml と、.cargo/mutants.toml は見ない' run_with_root "$tree"

place_tree || exit 1
printf '[build]\nrustflags = ["-A", "warnings"]\n' >"$config_toml" || exit 1
mkdir -p "$tree/target/cases.x/.cargo" "$tree/.git/.cargo" || exit 1
printf 'build.rustflags = ["-A", "warnings"]\n' >"$tree/target/cases.x/.cargo/config.toml" || exit 1
printf 'build.rustflags = ["-A", "warnings"]\n' >"$tree/.git/.cargo/config.toml" || exit 1
run_case deny '.cargo/config.toml:2: rustflags = ["-A", "warnings"]' \
  'C19 根の target/ と .git/ の下は見ない' run_with_root "$tree"

place_tree || exit 1
printf '[build]\n"rust\\x66lags" = ["-A", "warnings"]\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:2: "rust\x66lags" = ["-A", "warnings"]' \
  'C20 TOML 1.1 の \x で綴ったキーを落とす' run_with_root "$tree"

place_tree || exit 1
printf "[build]\ntarget-dir = 'C:\\\\cargo\\\\target'\n" >"$config_toml" || exit 1
run_case deny ".cargo/config.toml:2: target-dir = 'C:\\cargo\\target'" \
  'C21 \ を含むリテラル文字列(Windows のパス)も出す' run_with_root "$tree"

place_tree || exit 1
printf 'build = { target-dir = """\n# """, rustflags = ["-A", "warnings"] }\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:2: # """, rustflags = ["-A", "warnings"] }' \
  'C22 複数行の文字列の途中にある # で始まる行の語も拾う' run_with_root "$tree"

place_tree || exit 1
rm -r "$tree/.cargo" || exit 1
mkdir -p "$work/outer/.cargo" || exit 1
printf '[build]\nrustflags = ["-A", "warnings"]\n' >"$work/outer/.cargo/config.toml" || exit 1
ln -s ../outer/.cargo "$tree/.cargo" || exit 1
run_case deny '.cargo: シンボリックリンク' \
  'C23 .cargo がディレクトリへのリンクなら、リンク先を読まずにその場所を出す' run_with_root "$tree"

place_tree || exit 1
printf '[build]\nrustflags = ["-A", "warnings"]\n' >"$config_toml" || exit 1
mkdir -p "$tree/crates/a" || exit 1
ln -s ../../missing "$tree/crates/a/.cargo" || exit 1
run_case deny '.cargo/config.toml:2: rustflags = ["-A", "warnings"]
crates/a/.cargo: シンボリックリンク' \
  'C24 crate の下の .cargo がリンク切れのリンクでも、その場所を出す' run_with_root "$tree"

place_tree || exit 1
rm -r "$tree/.cargo" || exit 1
mkdir -p "$work/outer" || exit 1
printf '[build]\nrustflags = ["-A", "warnings"]\n' >"$work/outer/cargo-file" || exit 1
ln -s ../outer/cargo-file "$tree/.cargo" || exit 1
run_case deny '.cargo: シンボリックリンク' \
  'C25 .cargo がファイルへのリンクでも、リンク先を読まずにその場所を出す' run_with_root "$tree"

place_tree || exit 1
ln -s ../missing.toml "$config_toml" || exit 1
run_case deny '.cargo/config.toml: シンボリックリンク' \
  'C26 .cargo/config.toml がリンク切れのリンクでも、その場所を出す' run_with_root "$tree"

place_tree || exit 1
printf '[build]\nrustflags = ["-A", "warnings"]\n' >"$tree/linked.toml" || exit 1
ln -s ../linked.toml "$tree/.cargo/config" || exit 1
run_case deny '.cargo/config: シンボリックリンク' \
  'C27 旧名の .cargo/config がファイルへのリンクでも、リンク先を読まずにその場所を出す' run_with_root "$tree"

place_tree || exit 1
printf '[build]\nrustflags = ["-A", "warnings"]\n' >"$config_toml" || exit 1
run_case deny '.cargo/config.toml:2: rustflags = ["-A", "warnings"]' \
  'D1 引数なしで呼ぶと、カレントディレクトリを根として検査する' run_in_root "$tree"

# 拾わない形

place_tree || exit 1
cp "$here/../../../.cargo/config.toml" "$config_toml" || exit 1
run_case pass '' 'P1 このリポジトリの .cargo/config.toml の写しなら exit 0 で何も出さない' run_with_root "$tree"

place_tree || exit 1
rm -r "$tree/.cargo" || exit 1
printf '[package]\nname = "a"\n' >"$tree/Cargo.toml" || exit 1
run_case pass '' 'P2 設定ファイルが無い根なら exit 0 で何も出さない' run_with_root "$tree"

# 見ない形

place_tree || exit 1
printf '[build]\nrustflags = ["-A", "warnings"]\n' >"$config_toml" || exit 1
mkdir -p "$tree/inner" || exit 1
run_case miss '' 'M1 根より上の階層の .cargo/config.toml は見ない' run_with_root "$tree/inner"

place_tree || exit 1
mkdir -p "$work/outer/.cargo" || exit 1
printf '[build]\nrustflags = ["-A", "warnings"]\n' >"$work/outer/.cargo/config.toml" || exit 1
ln -s ../outer "$tree/linked" || exit 1
run_case miss '' 'M3 .cargo 以外の名前のディレクトリへのリンクは辿らない' run_with_root "$tree"

# 検査できない

place_tree || exit 1
printf 'x\n' >"$work/not-a-directory" || exit 1
run_unavailable_case '^cargo-config-rustflags: .*はディレクトリではありません' \
  'E1 根がディレクトリでなければ検査できない' run_with_root "$work/not-a-directory"

place_tree || exit 1
printf '[build]\njobs = 2\n' >"$config_toml" || exit 1
failing_awk_prefix="$(failing_awk_path_prefix "$work")" || exit 1
run_unavailable_case '^cargo-config-rustflags: .*走査に失敗' \
  'E2 awk が落ちれば、走査に失敗したことを出して検査できない' env PATH="$failing_awk_prefix$PATH" bash "$script" "$tree"

place_tree || exit 1
mkdir -p "$work/script-alone" || exit 1
# 検査のスクリプトが無ければ写さずに走らせ、このケースだけを落とす(続くケースも走らせる)。
[ ! -f "$script" ] || cp "$script" "$work/script-alone/" || exit 1
run_unavailable_case '^cargo-config-rustflags: .*test-file-path\.sh を読み込めません' \
  'E3 隣の test-file-path.sh を読み込めなければ、そのことを出して検査できない' \
  bash "$work/script-alone/cargo-config-rustflags.sh" "$tree"

exit "$cases_failed"
