# 命名規約

`snake_case` / `CamelCase` などの綴りの流儀は **rustfmt と clippy が見る**ので、ここには書かない
（ツールが強制するものを規約に二重に書かない）。ここに書くのは、ツールが見られない部分だけ。
実例（過去に踏んだ形）は [`harness/case-law/naming.md`](../harness/case-law/naming.md)。

## 名前と実体を一致させる

**名前が約束することと、実際にやること・返すものを一致させる。**
名前を読んで想像した挙動と実装がずれていたら、名前が間違っている。

- **戻り値を名前に出す。** エラーの一覧を返すだけの関数を `validate_*` と名付けない
  （「検証して成否を返す」と読める）。返すものを名前に出して `config_errors_of`
- 探索していない関数に `find_*` を使わない
- **1 つのモジュール内で語彙を混在させない。** 内部だけ直して公開 API に古い名前を残さない

| NG | OK | 理由 |
|---|---|---|
| `validate_config(config)` | `config_errors_of(config)` | エラー一覧を返すだけで、成否は返さない |
| `find_package(path)` | `package_of(path)` | 何も探していない。パスから導いている |

## `And` を含む名前を作らない

`do_a_and_b` は、その関数が 2 つの振る舞いを持っている証拠。
**名前を工夫して押し込めるのではなく、処理を分ける。**
分けられないなら、2 つをまとめて表す 1 つの概念名を見つける。

## 条件を組んだ式に名前を付ける

`&&` / `||` で 2 つ以上の条件を組んだ式を `if` にそのまま置かない。
**何を判定しているのかを表す名前の変数に入れてから使う。**

```rust
// NG
if strength >= Strength::Model && distance >= Distance::OtherPackage && volatility.is_high() { ... }

// OK
let tightly_coupled = strength >= Strength::Model && distance >= Distance::OtherPackage;
if tightly_coupled && volatility.is_high() { ... }
```

条件が 2 つ以上要る理由がコードから読み取れないなら、変数のそばに Why を残す。
単独の条件（`dependencies.is_empty()` など）はそのまま置いてよい。

## 内容を表さない汎用語を使わない

`Info` / `Data` / `Detail` / `Manager` / `Helper` / `Util` は、何を指すのかを伝えない。

**名前が思いつかないのは、その型が 2 つの役割を抱き合わせているサイン**であることが多い。
改名で解決しようとする前に、役割を分けられないか確認する（分けた結果その型自体が不要になることもある）。

## その名前が既に別の意味を持っていないか確認する

**新しく付ける識別子名は、書く前にこのリポジトリの他の場所を探す。** 命名規約に沿っていても、
既存の接頭辞・仕様書（`docs/tightrope-plan.md`）・下の語彙表が既にその語を別の意味で使っていることがある。
接頭辞・語幹を grep し、借りた慣習名がこの文脈で何を指すかを言えるか確かめる。

## このツールの語彙を固定する

**同じものを段ごとに違う名前で呼ばない。** `docs/tightrope-plan.md` が使っている語を出発点にし、
コードに語を足したらこの表にも足す。語を増やす前に、既にある語で言えないかを先に確かめる。

| 語 | 指すもの |
|---|---|
| `module` | 結合を測る単位。ファイル・ディレクトリ・パッケージのどれを指すかは、最初に置いた回にここへ書く |
| `dependency` | ある `module` から別の `module` への依存 1 本。`from` / `to` を持つ |
| `strength` | 統合強度。`Intrusive` / `Functional` / `Model` / `Contract` の 4 つ |
| `distance` | 距離。`SameDirectory` < `OtherDirectory` < `OtherPackage` の 3 段（近い順。package の決め方は `docs/report/distance-volatility-spec.md`「距離」） |
| `volatility` | 変動性。git 履歴の変更頻度 |
| `refs` | 依存ごとの参照箇所の数（LSP の references で数える） |
| `verdict` | 判定の結果（`risk` / `warn` / `tolerated` / `ok`） |
| `reason` | 判定を傾けた根拠 1 件。人が読む文ではなく、値と向きの構造 |
| `evidence` | 判定の根拠になったコードの位置（`ファイル:行`） |
| `coupling.json` | 解析結果のすべてを持つ JSON。出力はこれだけを入力にする |
| `grammar` | ソースを読むのに使う tree-sitter の文法。拡張子で決まる |
| `language id` | LSP がサーバに伝える言語の名前。`grammar` とは綴りを決める相手が違う |

## `create` / `new` / `from_*` の使い分け

- **`new`**: 引数がその値の材料であるとき（`Evidence::new(path, line)`）
- **`from_*`**: 別の表現から作り直すとき。変換元を名前に出す（`Dependency::from_reference`）
- 判定は `is_*` / `has_*`、変換は `to_*` / `into_*`（Rust の慣習に従う）
- **複数をまとめて返すものは `<返すもの>_of`**（`config_errors_of` / `dependencies_of`）

## `collect` を名前に使わない

**自前の関数・型の名前に `collect` / `Collection` を入れない。** 代わりに
`<返すもの>_of` で、**返すものを名前に出す**（`Iterator::collect` の呼び出しは対象外）。

**Why**: Rust では `collect` が `Iterator::collect`（イテレータを別のコレクションへ集約する）と
強く結びついている。自前の関数に付けると、読む側が標準のそれと同じ操作を想像する。

**Why not（「集める」関数には使ってよい、としない）**: 「集めている」かどうかは
**呼ぶ側から見えない実装の手順**で、名前が伝えるべき「何が返るか」を押しのける。
呼ぶ側が知りたいのは**何が返るか**である。
