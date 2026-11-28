#!/usr/bin/env bash
#
# cargo の設定ファイル(`.cargo/config.toml` / 旧名 `.cargo/config`)に、rustflags を渡しうる箇所が無いかの検査。
# 素の `cargo clippy` や IDE では設定ファイルの rustflags の `-A` / `-W` / `--cap-lints` が効き、workspace の lints の
# deny が manifest を変えずに外れるので、根の下に置いた設定ファイルの rustflags は場所を出して落とす。
# 検査の clippy でどの入口が塞がるかは `rust-checks.sh` が持つ。
#
# 使い方: bash harness/githooks/lib/cargo-config-rustflags.sh [<根>]   (<根> の既定は .)
# 違反が無ければ何も出さずに exit 0。
# 違反があれば、見出しの下に `<ファイル>:<行>: <行の中身>` と `<パス>: シンボリックリンク` を並べ替えて出し、exit 1。
# <ファイル> と <パス> は根からのパス(`.cargo/config.toml`・`crates/a/.cargo`)。
# 検査できないときは、理由を `cargo-config-rustflags: <理由>` で標準エラーへ出して exit 2。理由は
# 隣の `test-file-path.sh` を読み込めない / <根> がディレクトリでない / 走査(find か awk)に失敗した、のどれか。
#
# 拾う行
# - <根> の下(`<根>/target` と `<根>/.git` の下を除く)の `.cargo/config.toml` と `.cargo/config` の
#   すべての行のうち、語 `rustflags` / `include` か `\` を含む行。コメント行も拾う
# - `.cargo` と、`.cargo/config.toml` / `.cargo/config` がシンボリックリンクなら、リンク先を開かずにその場所を出す
#   (リンク先がディレクトリ・ファイル・リンク切れのどれでも同じ)
# - 値は見ない。`-A` / `-W` / `--cap-lints` のどれを渡すかに関わらず、キーの綴りで拾う
# - 複数行の配列は、キーの行だけを拾う
#
# 漏れの倒れる向き
# - キーを `rustflags` と綴らずに書くには、引用符つきキーのエスケープ(`\u` / `\U` / `\x` など)が要り、どれも `\` を
#   含む。`\` を 1 つでも含む行を拾うので、エスケープの種類が増えても漏れない
# - 別の設定ファイルを読ませる `include` も、読む先の中身を見ずに拾う
# - コメントかどうかを見分けない。複数行の文字列の途中にある `#` で始まる行はコメントではなく、同じ行にキーを
#   続けて書けるので、見分けると漏れる
# - `.cargo` と設定ファイルのリンクは、リンク先を開かずに落とす。開くと根の外のファイルの行を出しうるうえ、リンク先が
#   FIFO なら読み終わらない
#
# 落とす側へ倒した代償と、避け方
# - lint と関係の無い rustflags(`-C target-cpu=native` など)と、`[profile.*]` の rustflags → 手元の
#   `$CARGO_HOME/config.toml` に置く
# - crate の下の設定ファイル(`crates/a/.cargo/config.toml`)と、git が追跡していない設定ファイル → 同じ
# - コメント・行末のコメント・文字列の中の語 `rustflags` / `include` と、`\` を含む行(Windows のパス) → 言い換える。
#   パスは `/` で区切る
# - `.cargo` がファイルへのリンク・リンク切れのリンク → リンクをやめ、`.cargo` をディレクトリとして置く
# - 設定ファイルのリンク(リンク先が根の中のファイルでも) → リンクをやめ、ファイルとして置く
#
# 見ない形
# - <根> より上の階層の設定ファイル・`$CARGO_HOME/config.toml`・`--config` の引数・`include` が読む先の中身・
#   `.cargo` の外の名前の設定ファイル(`config.toml`・`.cargo/mutants.toml`)・`.cargo` 以外の名前の
#   ディレクトリへのシンボリックリンクの下(`find` は辿らない)
# - ファイルでもシンボリックリンクでもない `.cargo/config.toml` / `.cargo/config`(FIFO・ディレクトリ)
# - rustflags / include 以外のキー
# - このうち検査の clippy で効くものと効かないものは `rust-checks.sh` が持つ

set -uo pipefail

# 検査できなかった理由を標準エラーへ出し、exit 2 で終える。
#
# $1 理由
exit_unavailable() {
  printf 'cargo-config-rustflags: %s\n' "$1" >&2
  exit 2
}

here="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$here/test-file-path.sh" || exit_unavailable "$here/test-file-path.sh を読み込めません"

root="${1:-.}"

# 拾う語。rustflags を渡すキーと、別の設定ファイルを読ませるキー。
rustflags_or_include_pattern='rustflags|include'
# `\` 1 文字。
backslash_pattern='\\'

# 拾った行を `<根からのパス>:<行>: <行の中身>` で出す awk。式は環境変数 `RUSTFLAGS_OR_INCLUDE_PATTERN` /
# `BACKSLASH_PATTERN` で受け取る(`-v` で渡すと awk がエスケープを読み替える)。
found_awk='
{
  has_rustflags_or_include = ($0 ~ ENVIRON["RUSTFLAGS_OR_INCLUDE_PATTERN"])
  has_backslash = ($0 ~ ENVIRON["BACKSLASH_PATTERN"])
  picked = (has_rustflags_or_include || has_backslash)
  if (picked) {
    print relative_path_of(FILENAME) ":" FNR ": " $0
  }
}
'

# 引数に受けたシンボリックリンク(`.cargo` と設定ファイル)を `<根からのパス>: シンボリックリンク` で出す awk。
# BEGIN だけなので、リンク先を開かない。
symlink_awk='
BEGIN {
  for (i = 1; i < ARGC; i++) {
    print relative_path_of(ARGV[i]) ": シンボリックリンク"
  }
}
'

if [ ! -d "$root" ]; then
  exit_unavailable "$root はディレクトリではありません"
fi

found="$(
  export RUSTFLAGS_OR_INCLUDE_PATTERN="$rustflags_or_include_pattern" BACKSLASH_PATTERN="$backslash_pattern" LC_ALL=C
  CDPATH= cd -- "$root" &&
    find . \( -path ./target -o -path ./.git \) -prune -o \
      -type l \( -name .cargo -o -path '*/.cargo/config' -o -path '*/.cargo/config.toml' \) \
      -exec awk "$test_file_path_awk$symlink_awk" {} + -o \
      -type f \( -path '*/.cargo/config' -o -path '*/.cargo/config.toml' \) \
      -exec awk "$test_file_path_awk$found_awk" {} +
)"
scan_status=$?
if [ "$scan_status" -ne 0 ]; then
  exit_unavailable "$root の走査に失敗しました(終了コード $scan_status)"
fi

if [ -z "$found" ]; then
  exit 0
fi

printf '%s\n' 'cargo の設定に、rustflags を渡しうる箇所があります(rustflags / include の語か \ を含む行と、シンボリックリンクの .cargo と設定ファイル):'
printf '%s\n' "$found" | LC_ALL=C sort
exit 1
