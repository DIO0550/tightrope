#!/usr/bin/env bash
#
# cargo の検査を 1 つ、Cargo.lock の外から依存を解決しない引数で走らせる。commit 前の検査
# (`harness/githooks/pre-commit`)・push 前の検査(`harness/githooks/pre-push`)・CI の check ジョブ
# (`.github/workflows/rust.yml`)・編集後のフック(`.claude/hooks/post-edit-rust.sh`)が同じ引数で走るよう、
# これらの cargo の引数はここにだけ置く。clippy の出力を場所でふるい分ける `io-outside-driver.sh` は、cargo の終了コードと
# 出力をそのまま返すこのファイルを通せないので、cargo の引数を自分で持つ。
#
# 使い方: bash harness/githooks/lib/rust-checks.sh <fmt|clippy|doc|test>
# カレントディレクトリのクレートで走る。検査ごとの cargo の引数は下の `case` が持つ。
# 終了コードは cargo のもの。検査の名前が無い・知らない名前なら exit 2。
#
# clippy / doc / test は `--locked` で走る(理由と落ちたときの直し方は harness/deps/README.md「lock の外で解決しない」)。
# cargo の標準エラーに `--locked was passed to prevent this` があれば、`harness/deps/resolve.sh` で lock に
# 足りない依存を入れるよう案内する 1 行を標準エラーに足す。
#
# clippy は `CARGO_ENCODED_RUSTFLAGS` を空にして走らせる。stable の cargo はこの変数があると(空でも)ほかの
# rustflags の入口(`RUSTFLAGS`・`CARGO_BUILD_RUSTFLAGS`・`CARGO_TARGET_<triple>_RUSTFLAGS`・設定ファイルの
# `build.rustflags` / `target.*.rustflags`・`--config`)を読まないので、`-A` / `--cap-lints` で workspace の lints の
# deny が外れない。手元の rustflags(リンカの指定など)も、clippy の検査の中では効かない。空にしても塞がらない経路も
# ある(網羅ではない。例: `[env]` の `CLIPPY_ARGS`・`build.rustc-wrapper` / `RUSTC_WRAPPER`)。
# 素の `cargo clippy` では設定ファイルの rustflags が効くので、リポジトリの中のものは `cargo-config-rustflags.sh` が
# 落とす。doc / test は rustflags を空にしない。

set -uo pipefail

check="${1:-}"
case "$check" in
  fmt) command=(cargo fmt --check) ;;
  clippy) command=(env CARGO_ENCODED_RUSTFLAGS= cargo clippy --locked --all-targets -- -D warnings) ;;
  # 公開項目の doc から非公開項目へ intra-doc link を張ると、リンクが解決しない。
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

# cargo 1.85〜1.92 は `the lock file ... needs to be updated but --locked was passed to prevent this`、
# 1.93 以降は `cannot update the lock file ... because --locked was passed to prevent this` と出す。両方に含まれる部分で見る。
if ! grep -qF -e '--locked was passed to prevent this' "$stderr_log"; then
  exit "$status"
fi

# resolve.sh はリポジトリの根へ移ってから cargo を走らせるので、根でないクレートは manifest を名指しする。
repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
manifest="$(cargo locate-project --workspace --message-format plain 2>/dev/null)"
manifest_dir="$(cd "$(dirname "$manifest")" 2>/dev/null && pwd -P)"
outside_repository_root=no
[ -n "$manifest" ] && [ "$manifest_dir" != "$repository_root" ] && outside_repository_root=yes
manifest_option=""
if [ "$outside_repository_root" = yes ]; then
  manifest_option=" --manifest-path ${manifest_dir}/Cargo.toml"
fi
echo "rust-checks: Cargo.lock が Cargo.toml の依存と合わない(または無い)ので止めました。lock に足りない依存は bash harness/deps/resolve.sh update --workspace${manifest_option} で入れてください" >&2

exit "$status"
