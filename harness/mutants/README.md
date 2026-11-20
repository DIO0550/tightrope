# 差分の行の変異（cargo-mutants）

## 何が走るか

PR ごとに CI の `Mutants` ワークフローが走る。中身と、そうした理由は
[`.github/workflows/mutants.yml`](../../.github/workflows/mutants.yml) が持つ。

## 手元での走らせ方

版は `mutants.yml` の `CARGO_MUTANTS_VERSION` から読む。

```bash
cargo install cargo-mutants --locked --version "$(sed -n 's/^ *CARGO_MUTANTS_VERSION: "\(.*\)"$/\1/p' .github/workflows/mutants.yml)"
git add -N <新しく足したファイル>
git diff "$(git merge-base origin/main HEAD)" > "${TMPDIR:-/tmp}/pr.diff"
cargo mutants --in-diff "${TMPDIR:-/tmp}/pr.diff"
```

- `git add -N` を忘れると、まだ追跡していないファイルが差分に出ず、そこの変異が 0 件のまま通る
- 差分は走らせる直前に作る。作った後に木を変えると、差分と木が食い違う

## 結果の読み方

生き残った変異は `mutants.out/missed.txt`、タイムアウトは `mutants.out/timeout.txt` に 1 行ずつ出る
（変異ごとの差分とログは `mutants.out/diff/` と `mutants.out/logs/`）。CI ではアーティファクト
`mutants-out` から取れる。

このジョブで効く終了コード:

| 終了コード | 意味 |
| --- | --- |
| 2 | テストで落ちない変異が残った |
| 3 | 変異を入れたテストがタイムアウトした |
| 4 | 変異を入れる前の木でテストが落ちた |

## pre-push に入れない理由

- CI の harness ジョブは `PRE_PUSH_REQUIRE_ALL=1` で pre-push を走らせるので、入れると CI で
  cargo-mutants の導入が `Mutants` と合わせて 2 回になる
- 新しいブランチの初回 push では、pre-push が受け取る相手側の sha が 0 埋めで、差分の基点が決まらない

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

`mutants.yml` の `CARGO_MUTANTS_VERSION` を書き換える。上げる先は、公開から
`.cargo/config.toml` の `global-min-publish-age` の期間が経った版にする（日数はここへ写さない）。
足りているかは CI の「道具の cooldown」のステップが確かめ、足りなければ落ちる。
