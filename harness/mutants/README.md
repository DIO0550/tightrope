# 差分の行の変異（ミューテーション、cargo-mutants）

## 何が走るか

PR ごとに CI の `Mutants` ワークフローが走る。中身と、そうした理由は
[`.github/workflows/mutants.yml`](../../.github/workflows/mutants.yml) が持つ。
実装の検証（`implementation-flow` フェーズ 6）では、`test-reviewer` が下の「走らせる」ブロックで同じものを走らせる。

## 手元での走らせ方

導入（`test-reviewer` は走らせない）。版は `mutants.yml` の `MUTANTS_INSTALL_VERSION` から読み、
入れる前に道具の cooldown を通す（[`harness/deps/README.md`](../deps/README.md)「道具の cooldown」）。

```bash
version="$(sed -n 's/^ *MUTANTS_INSTALL_VERSION: "\(.*\)"$/\1/p' .github/workflows/mutants.yml)"
bash harness/deps/tool-cooldown.sh cargo-mutants "$version" && cargo install cargo-mutants --locked --version "$version"
```

走らせる（1 回のシェルで走らせる）。最後の 2 行が、結果を置いた絶対パスと cargo mutants の終了コードを出す。

```bash
diff_file="$(mktemp)"
{
  git diff "$(git merge-base origin/main HEAD)"
  git ls-files --others --exclude-standard -z | xargs -0 -r -n1 git diff --no-index /dev/null
} > "$diff_file"
out="$(mktemp -d)"
status=0
cargo mutants --in-diff "$diff_file" -o "$out" || status=$?
printf '%s\n' "$out"
printf 'cargo mutants の終了コード: %s\n' "$status"
```

- まだ追跡していないファイルは `git diff --no-index` で差分に足す。足さないと、そこの変異が 0 件のまま通る。
  Why not（`git add -N`）: index を書き換えるので、走らせる前と後で `git status` が変わる
- `{ }` は、追跡していないファイルがあると終了コード 123 で終わる（`git diff --no-index` が差分ありで 1 を返す）。
  なので次の行へ `&&` でつながない
- 差分は走らせる直前に作る。作った後に木を変えると、差分と木が食い違う

## 結果の読み方

生き残った変異は `-o` に渡したディレクトリの下の `mutants.out/missed.txt`、タイムアウトは
`mutants.out/timeout.txt` に 1 行ずつ出る
（変異ごとの差分とログは `mutants.out/diff/` と `mutants.out/log/`）。CI ではアーティファクト
`mutants-out` から取れる。

変異が 1 件も無い差分（Rust を変えない・テストだけを変える等）では、終了コード 0 で、`-o` のディレクトリに
`mutants.out` が作られない。生き残り無し（変異 0 件）として読む。

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
