# 依存の解決

`cargo update` / `cargo add` は **`harness/deps/resolve.sh` を通す**。素で叩かない
（`AGENTS.md`「依存の更新は cooldown を通す」）。

```bash
bash harness/deps/resolve.sh add <crate> -p <メンバー>   # 手順は下の「依存を足す」
bash harness/deps/resolve.sh update
bash harness/deps/resolve.sh update -p clap
```

cooldown の長さは `.cargo/config.toml` の `global-min-publish-age`（14 日）。仕組みと移植元は dryguard。

## 依存を足す

**外部依存の版は根の `[workspace.dependencies]` にだけ書き、メンバーは `<crate>.workspace = true` で受ける。**
手で書くのは根の 1 行だけで、メンバーの行と `Cargo.lock` は `resolve.sh` に書かせる。

`cargo add` には `[workspace.dependencies]` へ書くオプションが無い。根は `[package]` を持たない（virtual
manifest）ので、`-p` が無いと `could not determine which package to modify` で落ちる。`-p` だけで走らせると、
版がメンバーの `[dependencies]` に直接入る。

1. `bash harness/deps/resolve.sh add <crate> -p <メンバー> --dry-run` で、公開から期間を経た版を見る（何も書き換えない）。
   根に既にある crate なら `Adding <crate> (workspace) to dependencies` と出るので、2 を飛ばして 3 へ。
   features を増やすときは、根の既存の行の features を書き換える
2. 根の `[workspace.dependencies]` に、1 の dry-run が出した版で `<crate> = "<版>"` を手で書く。features もここに書く
3. `bash harness/deps/resolve.sh add <crate> -p <メンバー>` を走らせる

```bash
bash harness/deps/resolve.sh add <crate> -p <メンバー> --dry-run   # 1
bash harness/deps/resolve.sh add <crate> -p <メンバー>             # 3
```

2 で書く 1 行は、次のどちらかの形にする。

```toml
[workspace.dependencies]
<crate> = "<版>"                                             # features が既定のまま
<crate> = { version = "<版>", features = ["<feature>"] }     # features を選ぶとき
```

同じ追加で、次も直す。

- `harness/githooks/lib/crate-deps.sh` の `allowed_dependencies` で、足したメンバーの行の 3 列目（外部 crate）に
  crate の名前を足す。足さないと `crate-deps.sh` が `<メンバー>: [dependencies] の <crate>(外部 crate)` を出して
  exit 1 で落ちる
- `AGENTS.md`「プロジェクト構成」の外部依存の一覧（その行の「ここへ足す」）に足す
- 根の `[workspace.dependencies]` に依存の別名（`package =`）を書かない。根の `Cargo.toml` に `package =` の行が
  あると `harness/githooks/lib/folder-deps.sh` が検査できないとして exit 2 で落ちる（理由の一覧は `folder-deps.sh`
  の冒頭）。コメントの行の `package =` も拾う

手順を外れたときに起きること。

- 根に既にある crate の行を 2 で書き足すと、`Cargo.toml` が TOML の重複キー（`duplicate key`）で読めなくなる
- 2 に期間内の版を書くと、3 が `is too new` で落ち、`help:` に期間を経た版が出る。メンバーの行は書かれたまま
  残り、lock に無い依存を宣言した状態になるので、他の cargo を挟まずに、根の版を `help:` の版に直して 3 を
  すぐ走らせ直す（もう一度走らせてもメンバーの行は 1 行のまま）
- 3 に `--features` を付けると features がメンバーの側（`{ workspace = true, features = [...] }`）に入る

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
通らない解決の経路になる。`harness/githooks/lib/rust-checks.sh` を通る検査（呼び出し元はその冒頭）、`harness/githooks/lib/io-outside-driver.sh` の
clippy、CI の msrv ジョブ、cargo-mutants（`.cargo/mutants.toml`）は `--locked` で走り、lock に無い依存がある・lock が無いときは
lock を書き換えずに落ちる。

落ちたら `resolve.sh` で lock に足りない依存だけを入れ、入れた lock をコミットする。`update --workspace` は、
lock に既にある依存の版を上げない（lock に無いものだけを解決する）。`resolve.sh` はリポジトリの根へ移ってから
走るので、根でないクレートは `--manifest-path` でその `Cargo.toml` を名指しする（`rust-checks.sh` の案内はそれを付けて出す）。

```bash
bash harness/deps/resolve.sh update --workspace
bash harness/deps/resolve.sh update --workspace --manifest-path <クレート>/Cargo.toml   # 根でないクレート
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
  そのまま通る
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
