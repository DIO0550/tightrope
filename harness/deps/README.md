# 依存の解決

`cargo update` / `cargo add` は **`harness/deps/resolve.sh` を通す**。素で叩かない
（`AGENTS.md`「依存の更新は cooldown を通す」）。

```bash
bash harness/deps/resolve.sh add clap --features derive
bash harness/deps/resolve.sh update
bash harness/deps/resolve.sh update -p clap
```

cooldown の長さは `.cargo/config.toml` の `global-min-publish-age`（14 日）。仕組みと移植元は dryguard。

## なぜ入口を 1 つにするか

悪意あるバージョンは、**`cargo build` の時点で build script と proc macro がローカル実行される**。
掴んだ後に CI で気付いても、コードはもう自分のマシンで走っている。止められるのは**解決の瞬間**だけ。

`.cargo/config.toml` の `global-min-publish-age` が「公開から N 日経っていないバージョンを
使わない」を指定するが、**これは nightly でしか効かない**（`min-publish-age` は unstable）。

stable で走らせても**エラーにも警告にもならず、ただ無保護になる**。
`resolve.sh` は nightly が無ければ落ちるので、この「走ったが守られていない」を作らない。

## 効いていることの確かめ方

期間内のバージョンを名指しで取りにいって、弾かれることを見る。

```bash
bash harness/deps/resolve.sh update -p <crate> --precise <公開間もないバージョン>
```

公開時刻は sparse index から引ける（crates.io の API を叩かなくてよい）。

```bash
curl -s https://index.crates.io/cl/ap/clap | tail -1 | grep -o '"pubtime":"[^"]*"'
```

## 前提として引き受けること

- **既存の `Cargo.lock` は免除される。** cooldown は入口のフィルタで、既に lock にあるバージョンは
  そのまま通る。最初の依存（`toml`）を足した回から効いている
- **registry 由来の依存にしか効かない。** git / path 依存は `pubtime` を持たない
- **cooldown は検知しない。** 発見・yank されるまでの時間を稼ぐだけなので、これ単体を拠り所にしない
- **緊急のセキュリティ修正は逃げ道を使う。** `incompatible-publish-age` を `allow` にして
  `cargo update --precise` で取り込む。**使ったことを PR に書く**（黙って抜けると、なぜ期間内の
  バージョンが lock に入ったのかが後から読めない）

## まだ置いていないもの

dryguard は CI で LSP サーバ（typescript-language-server）を pnpm で入れるため、`resolve-node.sh` と
`pnpm-workspace.yaml` の `minimumReleaseAge` を持つ。tightrope にはまだ LSP を要するテストが無いので
置いていない。**最初の LSP のテストを足す回に**、CI へサーバを入れるステップと一緒に持ってくる
（`rules/testing.md`「LSP を要するテストは、飛ばしたことが分かる形にする」）。
