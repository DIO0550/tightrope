#!/usr/bin/env bash
#
# `crates/` の Rust に、lint の水準を deny / forbid 以外(allow / expect / warn)にする属性が無いかの検査
# (`rules/coding.md`「禁止事項」)。
#
# 使い方: bash harness/githooks/lib/lint-level-attributes.sh [<workspace の根>]   (<workspace の根> の既定は .)
# 違反が無ければ何も出さずに exit 0。
# 違反があれば、見出しの下に `<ファイル>:<行>: <行の中身>` を並べ替えて出し、exit 1。<ファイル> は根からの
# パス(`crates/…`)。
# 検査できないときは、理由を `lint-level-attributes: <理由>` で標準エラーへ出して exit 2。理由は
# 隣の `test-file-path.sh` を読み込めない / `<根>/crates` がディレクトリでない / 走査(find か awk)に失敗した、
# のどれか。
#
# 拾う行
# - `<根>/crates` の下のすべての `.rs`(`tests/fixtures/` の下も含む)で、語 `allow` / `expect` / `warn` の後に、
#   空白を挟んでよいとして `(`・`//`・`/*`・行末のどれかが続く行。外側の `#[..]`・内側の `#![..]`・
#   `cfg_attr` の中・生の識別子(`r#allow`)を区別せずに拾う
# - 空白には、rustc が空白とみなす ASCII 以外の文字(U+0085・U+200E・U+200F・U+2028・U+2029)も含める。
#   awk は `LC_ALL=C` で走らせ、これらを UTF-8 のバイト列で照らす(UTF-8 のロケールでは、gawk と BWK awk で
#   バイト列の式が当たらない)
# - 語の直前が `.` / `:` / ASCII の識別子の文字(英数字と `_`)なら拾わない(`.expect(`・`Result::expect(`・`my_allow(`)
# - doc・`//` のコメント・文字列の中も読み分けずに拾う
#
# 落とす側へ倒した代償と、避け方
# - `allow` / `expect` / `warn` という名前の関数の定義と、修飾しない呼び出し → 名前を変える。
#   語は大文字と小文字を区別するので、enum のバリアント `Warn` は拾わない
# - ASCII 以外の文字で終わる識別子に続く語(`再試行allow(`)と、修飾した生の識別子(`.r#expect(`) → 名前を変える。
#   語を ASCII 以外の文字の直後に置かない・`r#` を使わない
# - 語で終わる行 → 言い換える
# - 語の後に `(` が続く英文の doc → 言い換える
# - 上の 2 つで、語がこのツールの語彙(`rules/naming.md` の語彙表の `verdict` の `warn`)なら、言い換えずに
#   語をバッククォートで囲むか、語の後ろに句読点を続ける
# - doc・`//`・文字列の中の属性の例 → 解析用の Rust のサンプルには lint の属性の語を含めない。含めるなら
#   `.rs` 以外の拡張子(`<名前>.rs.txt`)のファイルに置き、`include_str!` で読む。LSP や拡張子で文法を選ぶ
#   処理へ渡す fixture は `.rs` のままにするしかないので、語を含めない
#
# 見ない形
# - 属性の名前をマクロの変数で渡す形(`#[$l(dead_code)]` の `$l` に `allow` を渡す)
# - `<根>/crates` の外のファイルと、`.rs` 以外のファイル。`.rs` 以外のファイルを `include!` で読む経路は、
#   `folder-deps.sh` が `include!` を読めない参照の形として落とす
# - シンボリックリンク(`find -type f` は辿らない)
# - 属性以外で lint の水準を変える経路(`Cargo.toml` の `[lints]`・rustc の `-A` / `-W` を渡す `RUSTFLAGS` など)

set -uo pipefail

# 検査できなかった理由を標準エラーへ出し、exit 2 で終える。
#
# $1 理由
exit_unavailable() {
  printf 'lint-level-attributes: %s\n' "$1" >&2
  exit 2
}

here="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
. "$here/test-file-path.sh" || exit_unavailable "$here/test-file-path.sh を読み込めません"

root="${1:-.}"

# 語の直前。行頭か、`.` / `:` / ASCII の識別子の文字以外の 1 文字。
preceding_pattern='(^|[^.:[:alnum:]_])'
# lint の水準のうち、deny / forbid 以外の語。
level_word_pattern='(allow|expect|warn)'
# rustc が空白とみなす 1 文字。ASCII の空白か、ASCII 以外の空白(U+0085・U+200E・U+200F・U+2028・U+2029)の
# UTF-8 のバイト列。
rustc_whitespace_pattern='[[:space:]]|'$'\302\205|\342\200[\216\217\250\251]'
# 語の後ろ。`(`・`//`・`/*`・行末のどれか。
terminator_pattern='(\(|/[*/]|$)'
# 拾う行。語と後ろのあいだには、rustc の空白をいくつ挟んでもよい。
lint_level_pattern="${preceding_pattern}${level_word_pattern}(${rustc_whitespace_pattern})*${terminator_pattern}"

# 拾った行を `crates/<パス>:<行>: <行の中身>` で出す awk。式は環境変数 `LINT_LEVEL_PATTERN` で受け取る
# (`-v` で渡すと awk がエスケープを読み替える)。
found_awk='
$0 ~ ENVIRON["LINT_LEVEL_PATTERN"] {
  print "crates/" relative_path_of(FILENAME) ":" FNR ": " $0
}
'

if [ ! -d "$root/crates" ]; then
  exit_unavailable "$root/crates はディレクトリではありません"
fi

found="$(LINT_LEVEL_PATTERN="$lint_level_pattern" LC_ALL=C \
  awk_rs_files_under "$root/crates" "$test_file_path_awk$found_awk")"
scan_status=$?
if [ "$scan_status" -ne 0 ]; then
  exit_unavailable "$root/crates の走査に失敗しました(終了コード $scan_status)"
fi

if [ -z "$found" ]; then
  exit 0
fi

printf 'deny / forbid 以外の lint の水準(allow / expect / warn)を付けた属性があります:\n'
printf '%s\n' "$found" | LC_ALL=C sort
exit 1
