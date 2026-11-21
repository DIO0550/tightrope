#!/usr/bin/env bash
#
# cargo の検査を 1 つ、Cargo.lock の外から依存を解決しない引数で走らせる。push 前の検査
# (`harness/githooks/pre-push`)・CI の check ジョブ(`.github/workflows/rust.yml`)・編集後のフック
# (`.claude/hooks/post-edit-rust.sh`)が同じ引数で走るよう、cargo の引数はここにだけ置く。
#
# 使い方: bash harness/githooks/lib/rust-checks.sh <fmt|clippy|doc|test>
# カレントディレクトリのクレートで走る。検査ごとの cargo の引数は下の `case` が持つ。
# 終了コードは cargo のもの。検査の名前が無い・知らない名前なら exit 2。
#
# clippy / doc / test は `--locked` で走るので、Cargo.toml の依存が Cargo.lock に無い・Cargo.lock が無いときは、
# lock を書き換えず・作らずに落ちる。cargo の標準エラーに `because --locked was passed` があれば、
# `harness/deps/resolve.sh` で lock を入れ直すよう案内する 1 行を標準エラーに足す。

set -uo pipefail

check="${1:-}"
case "$check" in
  fmt) command=(cargo fmt --check) ;;
  clippy) command=(cargo clippy --locked --all-targets -- -D warnings) ;;
  doc) command=(env RUSTDOCFLAGS="-D rustdoc::private_intra_doc_links" cargo doc --locked --no-deps) ;;
  test) command=(cargo test --locked) ;;
  *)
    printf 'rust-checks: 検査の名前は fmt / clippy / doc / test のどれかです（受け取った名前: %s）\n' "${check:-無し}" >&2
    exit 2
    ;;
esac

stderr_log="$(mktemp)" || exit 2
trap 'rm -f "$stderr_log"' EXIT

# 標準出力はそのまま流し、標準エラーは流しながら写しを取る(案内を足すかを、写しから決める)。
# pipefail なので、cargo が落ちればその終了コードが残る。
status=0
{ "${command[@]}" 2>&1 1>&3 3>&- | tee "$stderr_log" >&2; } 3>&1 || status=$?

if grep -qF 'because --locked was passed' "$stderr_log"; then
  echo 'rust-checks: Cargo.lock が Cargo.toml の依存と合わない(または無い)ので止めました。lock は bash harness/deps/resolve.sh update で入れ直してください' >&2
fi

exit "$status"
