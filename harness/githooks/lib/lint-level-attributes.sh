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
# `<根>/crates` がディレクトリでない / 走査(find か awk)に失敗した、のどちらか。
#
# 拾う行
# - `<根>/crates` の下のすべての `.rs`(`tests/fixtures/` の下も含む)で、語 `allow` / `expect` / `warn` の後に、
#   空白を挟んでよいとして `(`・`//`・`/*`・行末のどれかが続く行。外側の `#[..]`・内側の `#![..]`・
#   `cfg_attr` の中・生の識別子(`r#allow`)を区別せずに拾う
# - 空白には、rustc が空白とみなす ASCII 以外の文字(U+0085・U+200E・U+200F・U+2028・U+2029)も含める。
#   awk は `LC_ALL=C` で走らせ、これらを UTF-8 のバイト列で照らす(UTF-8 のロケールでは、gawk と BWK awk で
#   バイト列の式が当たらない)
# - 語の直前が `.` / `:` / 識別子の文字なら拾わない(`.expect(`・`Result::expect(`・`my_allow(`)
# - doc・`//` のコメント・文字列の中も読み分けずに拾う
#
# 落とす側へ倒した代償と、避け方
# - `allow` / `expect` / `warn` という名前の関数の定義と、修飾しない呼び出し → 名前を変える。
#   語は大文字と小文字を区別するので、enum のバリアント `Warn` は拾わない
# - 語で終わる行 → 言い換える
# - 語の後に `(` が続く英文の doc → 言い換える
# - doc・`//`・文字列の中の属性の例 → 解析用の Rust のサンプルには lint の属性の語を含めない。含めるなら
#   `.rs` 以外の拡張子(`<名前>.rs.txt`)のファイルに置き、`include_str!` で読む
#
# 見ない形
# - 属性の名前をマクロの変数で渡す形(`#[$l(dead_code)]` の `$l` に `allow` を渡す)
# - `<根>/crates` の外のファイルと、`.rs` 以外のファイル
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

root="${1:-.}"

if [ ! -d "$root/crates" ]; then
  exit_unavailable "$root/crates はディレクトリではありません"
fi

found="$(CDPATH= cd -- "$root" && LC_ALL=C find crates -type f -name '*.rs' -exec awk '
  /(^|[^.:[:alnum:]_])(allow|expect|warn)([[:space:]]|\302\205|\342\200[\216\217\250\251])*(\(|\/[*\/]|$)/ {
    print FILENAME ":" FNR ": " $0
  }
' {} +)"
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
