#!/usr/bin/env bash
#
# infrastructure crate の中で、I/O を持ってよい場所(下の `io_places`)の外が I/O を使っていないかの検査。
# I/O の項目は `crates/domain` の clippy の設定(`clippy.toml` か `.clippy.toml`。両方あれば clippy は `.clippy.toml` を
# 読む)の disallowed-macros / disallowed-methods / disallowed-types の一覧で、infrastructure に clippy を 1 回走らせ、
# その一覧で報告された禁止のうち場所の外を指すものを違反とする。借りた一覧の中身(I/O の項目の欠けと、一覧を持たない
# `.clippy.toml` による隠れ)は `clippy-config-cases.sh` の T10 が守る。
#
# 使い方: bash harness/githooks/lib/io-outside-driver.sh [<workspace の根>]   (<workspace の根> の既定は .)
# 違反が無ければ何も出さずに exit 0。
# 違反があれば、見出しの下に違反の行を並べ替えて出し、exit 1。同じ行に同じ文の報告が 2 つあれば 1 行にまとめる。
# 違反の行は次の形。
#   <ファイル>:<行>: use of a disallowed <method|macro|type> `<項目>`
# 検査できないときは、理由を `io-outside-driver: <理由>` で標準エラーへ出して exit 2。理由は次のとおり。
#   根を 2 つ以上受け取った / 根が空 / 根に移れない / `<根>/crates/infrastructure/Cargo.toml` が無い /
#   `<根>/crates/domain` に clippy.toml も .clippy.toml も無い / 一時ファイルを作れない /
#   clippy が 0 以外で終わった(cargo の出力も標準エラーへ出す。Cargo.lock が無い・合わない、コンパイルエラーを含む) /
#   clippy の出力をふるい分ける awk か sort が 0 以外で終わった
#
# 根をカレントディレクトリにして、次の引数で cargo を走らせる。それぞれが、外から何を渡されても報告が変わらないようにするもの。
# - `env CARGO_ENCODED_RUSTFLAGS=`: `RUSTFLAGS` / `CARGO_ENCODED_RUSTFLAGS` / `CARGO_BUILD_RUSTFLAGS` /
#   `.cargo/config.toml` の `build.rustflags` に `--cap-lints allow` や `-A warnings` があっても報告する
# - `CLIPPY_CONF_DIR=<根>/crates/domain`: 外から渡された `CLIPPY_CONF_DIR` を上書きし、domain の一覧で照らす
# - `--locked`: Cargo.lock が無い・合わないときに、lock を作らず書き換えずに落ちる
# - `-p infrastructure` と `--no-deps`: infrastructure 以外の crate と、infrastructure が path で依存する crate を照らさない
# - `--all-targets`: 単体テストと結合テスト(`crates/infrastructure/tests/`)も照らす
# - `--message-format=short` と `--color never`: `CARGO_TERM_COLOR=always` でも報告の行を同じ綴りで読む
# - `--cap-lints warn`: Cargo.toml の `[lints]` で deny / forbid にした lint に当たっても、検査できないにならない
# - `-W warnings`: `[workspace.lints.rust]` の `warnings = "allow"` を継承しても報告する
# - `-W clippy::disallowed_macros` / `-W clippy::disallowed_methods` / `-W clippy::disallowed_types`: `[lints.clippy]` で
#   これらを allow にしても報告する
#
# 見ない形
# - 一覧に無い std の項目(driver から受け取った I/O の値の、一覧に無いメソッド(`DirEntry::metadata` など)を含む)
# - driver で定義したマクロを外から呼んだ I/O(報告は driver の中の行に付く)
# - driver で付けた型の別名(`pub type`)を通した I/O(`pub type Handle = std::fs::File;` の `Handle::open` など)
# - `#[path]` で driver の下を経由したパス(`driver/../translation/x.rs` など)で読み込んだファイルの I/O(`folder-deps.sh` が
#   `#[path]` を落とす)
# - `#[cfg]` で外れたコード
# - ソースの lint の水準の属性(`lint-level-attributes.sh` が落とす)
# - `.cargo/config.toml` の `[env]` で force した `CLIPPY_CONF_DIR` / `CLIPPY_ARGS`
# - rustc-wrapper を通した lint の水準の変更
# - infrastructure 以外の crate と、infrastructure の依存先の crate
# - 外部 crate の関数を通した I/O
#
# 連想配列など bash 4 以降の機能は使わない。

set -uo pipefail

# 検査できなかった理由を標準エラーへ出し、exit 2 で終える。
#
# $1 理由
exit_unavailable() {
  printf 'io-outside-driver: %s\n' "$1" >&2
  exit 2
}

[ "$#" -le 1 ] || exit_unavailable "根は 1 つだけ渡してください(受け取った数: $#)"
root_argument="${1-.}"
[ -n "$root_argument" ] || exit_unavailable "根が空です"
root="$(cd "$root_argument" 2>/dev/null && pwd -P)" || exit_unavailable "根 $root_argument に移れません"

# infrastructure の中で I/O を持ってよい場所。1 行 1 つで、根からのパス。`/` で終わる行はその下すべて(前方一致)、
# それ以外はそのファイルだけ(完全一致)。
io_places="$(cat <<'io_places'
crates/infrastructure/src/driver.rs
crates/infrastructure/src/driver/
crates/infrastructure/tests/
io_places
)"

heading='infrastructure の driver の外で I/O を使っています(I/O の項目の一覧は crates/domain の clippy.toml(か .clippy.toml)、I/O を持ってよい場所は harness/githooks/lib/io-outside-driver.sh の io_places)'

[ -f "$root/crates/infrastructure/Cargo.toml" ] || exit_unavailable "$root/crates/infrastructure/Cargo.toml がありません"
config_dir="$root/crates/domain"
has_config=no
[ -f "$config_dir/clippy.toml" ] && has_config=yes
[ -f "$config_dir/.clippy.toml" ] && has_config=yes
[ "$has_config" = yes ] || exit_unavailable "$config_dir に clippy.toml も .clippy.toml もありません"

clippy_log="$(mktemp)" || exit_unavailable "一時ファイルを作れません"
trap 'rm -f "$clippy_log"' EXIT

status=0
(cd "$root" && env CARGO_ENCODED_RUSTFLAGS= CLIPPY_CONF_DIR="$config_dir" \
  cargo clippy --locked -p infrastructure --no-deps --all-targets --message-format=short --color never -- \
  --cap-lints warn -W warnings -W clippy::disallowed_macros -W clippy::disallowed_methods -W clippy::disallowed_types) \
  >"$clippy_log" 2>&1 || status=$?
if [ "$status" -ne 0 ]; then
  cat "$clippy_log" >&2
  exit_unavailable "clippy が終了コード $status で終わりました"
fi

# clippy の出力から、一覧で禁止した項目の報告のうち場所の外を指すものを `<ファイル>:<行>: <文>` で 1 件 1 行に出す awk。
# 場所は環境変数 `IO_PLACES` で受け取る。同じ行は bash が `sort -u` でまとめる。
violations_awk='
BEGIN {
  report_prefix = "^[^:]+:[0-9]+:[0-9]+: warning: "
  disallowed_report = report_prefix "use of a disallowed "
  place_count = split(ENVIRON["IO_PLACES"], places, "\n")
}
function is_directory_place(place) { return substr(place, length(place)) == "/" }
function is_io_place(path,   i, under_directory, in_place) {
  for (i = 1; i <= place_count; i++) {
    under_directory = is_directory_place(places[i]) && index(path, places[i]) == 1
    in_place = under_directory || path == places[i]
    if (in_place) return 1
  }
  return 0
}
$0 ~ disallowed_report {
  split($0, fields, ":")
  path = fields[1]
  if (is_io_place(path)) next
  text = $0
  sub(report_prefix, "", text)
  print path ":" fields[2] ": " text
}
'

violations="$(IO_PLACES="$io_places" awk "$violations_awk" "$clippy_log" | LC_ALL=C sort -u)" ||
  exit_unavailable "clippy の出力を読めませんでした"

[ -z "$violations" ] && exit 0
printf '%s\n' "$heading" "$violations"
exit 1
