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

## 道具の cooldown

**`cargo install` は `global-min-publish-age` を見ない。** `cargo install` で入れる道具は、
入れる前に `harness/deps/tool-cooldown.sh` を通す。公開から期間が経っていないとき、crate の名前が crates.io の文字種で
ないとき、設定・index・版のどれかが読めないときに落ちる。

```bash
bash harness/deps/tool-cooldown.sh cargo-mutants <版> && cargo install cargo-mutants --locked --version <版>
bash harness/deps/tool-cooldown-cases.sh   # 判定表
```

- **`.crate` に `Cargo.lock` を同梱している版を選ぶ。** `--locked` が公開時の lock で入れ、依存の版の
  公開が本体より前になるので、本体の期間が依存全体の下限になる。lock が無いと依存は入れる時点で解決される

## lock の外で解決しない

**依存を解決するのは `resolve.sh` だけにし、検査とビルドは `Cargo.lock` にある版だけで走らせる。** 素の
`cargo test` などは、Cargo.toml の依存が lock に無ければその場で解決して lock を書き換えるので、`resolve.sh` を
通らない解決の経路になる。push 前の検査・CI の check ジョブ・編集後のフックの cargo（引数は
`harness/githooks/lib/rust-checks.sh` が持つ）、CI の msrv ジョブ、cargo-mutants（`.cargo/mutants.toml`）は
`--locked` で走り、lock に無い依存がある・lock が無いときは lock を書き換えずに落ちる。

落ちたら `resolve.sh` で lock を入れ直し、入れ直した lock をコミットする。

```bash
bash harness/deps/resolve.sh update
```

- **`cargo fmt` には付けない。** 依存を解決しないので、lock に無い依存があっても lock を書き換えない

## lock の公開からの期間（PR での事後の検知）

**PR で `Cargo.lock` に足した crates.io の版は、CI（`.github/workflows/lock-publish-age.yml`）が、その版を
足したコミットの時点で公開から期間を経ていたかを確かめる。** `resolve.sh` を通さずに解決した版や、逃げ道で
取り込んだ版を、PR の上で赤くして見えるようにする。cooldown（解決の入口で止める）とは別の事後の検知で、
防御にはならない（理由は「なぜ入口を 1 つにするか」）。

```bash
bash .github/scripts/lock-publish-age.sh origin/main HEAD   # 手元で PR の先端を(CI は main とのマージ結果を見る)
bash .github/scripts/lock-publish-age-cases.sh              # 判定表
```

- **見るのは足したコミットの committer の時刻。** 時刻はコミットに固定されるので、時間が経っても答えは
  甘くならない。何をどう確かめるかは `lock-publish-age.sh` の冒頭
- **解決した時刻は残らないので、committer の時刻は甘い側に寄る。** 期間内の版を足したコミットを、公開から期間を
  経た後に rebase して時刻を新しくすると通る
- **main への直接 push は見ない。** 走るのは PR だけ
- **判定は PR 自身の設定・スクリプト・コミットで行う。** 期間を縮める・スクリプトを変える・committer の時刻を
  未来にする、のどれでも通せるので、それらを変えた PR は人が差分を見る

## 前提として引き受けること

- **既存の `Cargo.lock` は免除される。** cooldown は入口のフィルタで、既に lock にあるバージョンは
  そのまま通る。今は依存が無いので、最初の依存を足す回から効く
- **registry 由来の依存にしか効かない。** git / path 依存は `pubtime` を持たない
- **cooldown は検知しない。** 発見・yank されるまでの時間を稼ぐだけなので、これ単体を拠り所にしない。
  抜けた版を PR の上で見つけるのは「lock の公開からの期間（PR での事後の検知）」で、こちらも事後に見えるだけ
  （防御にならない理由は「なぜ入口を 1 つにするか」）
- **緊急のセキュリティ修正は逃げ道を使う。** `incompatible-publish-age` を `allow` にして
  `cargo update --precise` で取り込む。**使ったことを PR に書く**（黙って抜けると、なぜ期間内の
  バージョンが lock に入ったのかが後から読めない）。逃げ道で期間内の版を足した PR は、lock の公開からの
  期間の検査が赤くなる。例外を書くファイルは置かない。必須チェックにした場合は、管理者が理由を PR に書いてマージする

## まだ置いていないもの

dryguard は CI で LSP サーバ（typescript-language-server）を pnpm で入れるため、`resolve-node.sh` と
`pnpm-workspace.yaml` の `minimumReleaseAge` を持つ。tightrope にはまだ LSP を要するテストが無いので
置いていない。**最初の LSP のテストを足す回に**、CI へサーバを入れるステップと一緒に持ってくる
（`rules/testing.md`「LSP を要するテストは、飛ばしたことが分かる形にする」）。
