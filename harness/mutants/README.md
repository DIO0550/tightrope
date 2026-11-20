# 差分の行の変異（ミューテーション、cargo-mutants）

## 何が走るか

PR ごとに CI の `Mutants` ワークフローが走る。中身と、そうした理由は
[`.github/workflows/mutants.yml`](../../.github/workflows/mutants.yml) が持つ。

## 手元での走らせ方

版は `mutants.yml` の `MUTANTS_INSTALL_VERSION` から読み、入れる前に道具の cooldown を通す
（[`harness/deps/README.md`](../deps/README.md)「道具の cooldown」）。

```bash
version="$(sed -n 's/^ *MUTANTS_INSTALL_VERSION: "\(.*\)"$/\1/p' .github/workflows/mutants.yml)"
bash harness/deps/tool-cooldown.sh cargo-mutants "$version" && cargo install cargo-mutants --locked --version "$version"
git add -N <新しく足したファイル>
git diff "$(git merge-base origin/main HEAD)" > "${TMPDIR:-/tmp}/pr.diff"
cargo mutants --in-diff "${TMPDIR:-/tmp}/pr.diff"
```

- `git add -N` を忘れると、まだ追跡していないファイルが差分に出ず、そこの変異が 0 件のまま通る
- 差分は走らせる直前に作る。作った後に木を変えると、差分と木が食い違う

## 結果の読み方

生き残った変異は `mutants.out/missed.txt`、タイムアウトは `mutants.out/timeout.txt` に 1 行ずつ出る
（変異ごとの差分とログは `mutants.out/diff/` と `mutants.out/log/`）。CI ではアーティファクト
`mutants-out` から取れる。Rust を変えない差分では `mutants.out` が作られず、生き残り無しとして読む。

**合否は `missed.txt` が空かどうかで決める。** タイムアウトだけなら通す（変異が無限ループなどを
起こし、テストがタイムアウトで止めている = 捕まえている）。

終了コードは `missed.txt` の照合の後に見て、0（すべて捕まえた）と 3（タイムアウトがあった）以外なら落ちる。
代表は 4（変異を入れる前の木でテストが落ちた）と 5（差分と木が食い違う）。
生き残りとタイムアウトが両方あると、終了コードは 2（生き残り）ではなく 3 になる。
終了コードを合否に使わないのはこのため。

## 生き残りを意図して許すとき

`.cargo/mutants.toml` の `exclude_re` に足し、**各 `exclude_re` の隣に 1〜2 行の Why** を書く。
経緯は Issue に書く。

```toml
exclude_re = [
    # Why: <なぜこの変異はテストで落とさなくてよいか>
    "<変異の名前に当たる正規表現>",
]
```

## 版の上げ方

`mutants.yml` の `MUTANTS_INSTALL_VERSION` を書き換える。上げる先は、公開から
`.cargo/config.toml` の `global-min-publish-age` の期間が経っていて、`.crate` に `Cargo.lock` を
同梱している版にする（日数はここへ写さない）。期間が足りているかは CI の「道具の cooldown」の
ステップ（`harness/deps/tool-cooldown.sh`）が確かめ、足りなければ落ちる。
