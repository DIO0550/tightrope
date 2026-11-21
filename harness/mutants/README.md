# 差分の行の変異（cargo-mutants）

## 何が走るか

PR ごとに CI の `Mutants` ワークフローが走る。中身と、そうした理由は
[`.github/workflows/mutants.yml`](../../.github/workflows/mutants.yml) が持つ。
実装の検証（`implementation-flow` フェーズ 6）では、`test-reviewer` が下の「走らせる」ブロックで同じものを走らせる。

## 手元での走らせ方

導入。`test-reviewer` が走らせるかは [`.claude/agents/test-reviewer.md`](../../.claude/agents/test-reviewer.md) が持つ。
版は `mutants.yml` の `MUTANTS_INSTALL_VERSION` から読み、入れる前に道具の cooldown を通す（[`harness/deps/README.md`](../deps/README.md)「道具の cooldown」）。

```bash
version="$(sed -n 's/^ *MUTANTS_INSTALL_VERSION: "\(.*\)"$/\1/p' .github/workflows/mutants.yml)"
bash harness/deps/tool-cooldown.sh cargo-mutants "$version" && cargo install cargo-mutants --locked --version "$version"
```

走らせる（1 回のシェルで走らせる）。最後の 3 行が、差分ファイルの大きさ、`mutants.out` を作ったディレクトリの
絶対パス、cargo mutants の終了コードを出す。差分を作れなければ、その 3 行を出さずに止まる。

```bash
(
  base="$(git merge-base origin/main HEAD)" || { echo "差分の基点が取れない（origin/main が無い）。git fetch origin main の後に走らせ直す" >&2; exit 1; }
  work="$(mktemp -d)" || exit 1
  trap 'rm -rf "$work"' EXIT
  diff_file="$work/diff"
  git diff "$base" > "$diff_file" || exit 1
  git ls-files --others --exclude-standard -z > "$work/untracked" || exit 1
  while IFS= read -r -d '' path; do
    diff_status=0
    git_error="$(git diff --no-index -- /dev/null "$path" 2>&1 >> "$diff_file")" || diff_status=$?
    [ -z "$git_error" ] || { printf '%s\n追跡していないファイルの差分を作れない: %s\n' "$git_error" "$path" >&2; exit 1; }
    [ "$diff_status" -le 1 ] || { echo "追跡していないファイルの差分を作れない: $path（終了コード $diff_status）" >&2; exit 1; }
  done < "$work/untracked"
  out="$(mktemp -d)" || exit 1
  status=0
  CARGO_TARGET_DIR="$work/target" cargo mutants --in-diff "$diff_file" -o "$out" || status=$?
  printf '差分ファイルの大きさ: %s バイト\n' "$(wc -c < "$diff_file")"
  printf '%s\n' "$out"
  printf 'cargo mutants の終了コード: %s\n' "$status"
)
```

- `( )` の中で止めるので、手で打つシェルは閉じない
- 基点を先に取る。Why not（`git diff "$(git merge-base …)"` に埋め込む）: 基点が取れなくても先へ進む。
  追跡していないファイルが無ければ空の差分で終了コード 0 になり、変異 0 件と見分けがつかない
- まだ追跡していないファイルは `git diff --no-index` で差分に足す。足さないと、そこの変異が 0 件のまま通る。
  Why not（`git add -N`）: index を書き換えるので、走らせる前と後で `git status` が変わる
- `--` を `/dev/null` の前に置く。置かないと、`--output=Cargo.toml` のような `-` で始まる名前の
  ファイルをオプションとして読み、`=` の後の名前のファイル（この例では `Cargo.toml`）を空にする
- 追跡していないファイルは一覧を先にファイルへ取ってから 1 件ずつ回す。`git ls-files` の失敗で止めるため
- `git diff --no-index` は差分ありで 1 を返し、入れ子の Git リポジトリを読めなかったときも 1 を返す。なので失敗は
  終了コード（2 以上。読めないファイルは 128）と stderr の両方で見分ける。Why not（`xargs`）: 失敗も 123 にまとめ、欠けた差分のまま進む
- 差分ファイルとビルド先（`CARGO_TARGET_DIR`）は、呼ぶたびに作る一時ディレクトリに置き、終わったときに消す。
  ビルド先を自分専用にして、並列で動く他のビルドと `target/` を取り合わない。`-o` のディレクトリは結果を読むために残す
- 差分は走らせる直前に作る。作った後に木を変えると、差分と木が食い違う

## 結果の読み方

生き残った変異は `-o` に渡したディレクトリの下の `mutants.out/missed.txt`、タイムアウトは
`mutants.out/timeout.txt` に 1 行ずつ出る
（変異ごとの差分とログは `mutants.out/diff/` と `mutants.out/log/`）。CI ではアーティファクト
`mutants-out` から取れる。

変異が 1 件も無い差分（Rust を変えない・テストだけを変える等）では、終了コード 0 で、`-o` のディレクトリに
`mutants.out` が作られない。生き残り無し（変異 0 件）として読む。ただし差分ファイルが 0 バイトのときも
同じ形（終了コード 0、`mutants.out` 無し）になるので、変異 0 件と読むのは差分ファイルが 0 バイトでないときだけにする。

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
