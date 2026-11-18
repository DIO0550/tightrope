# tightrope report - CLI 仕様（バックエンド）

> **機能**: [tightrope report（MVP）](./index.md)

## 概要

`tightrope report` の引数・出力先・終了コードと、走査の根に置く設定ファイル `tightrope.toml` を決める。

## コマンド

```
tightrope report <dir> [--format terminal|json|markdown] [-o <file>] [--fail-on risk|warn] [--no-lsp]
```

| 引数 | 型 | 必須 | 既定 | 説明 |
|:-----|:---|:-----|:-----|:-----|
| `<dir>` | パス | はい | — | 走査の根。この下の TypeScript ファイルを解析する |
| `--format` | `terminal` / `json` / `markdown` | いいえ | `terminal` | 出力形式。`json` は `coupling.json` の中身 |
| `-o`, `--output` | パス | いいえ | 標準出力 | 出力先のファイル |
| `--fail-on` | `risk` / `warn` | いいえ | 無し | 指定した判定以上が 1 件でもあれば終了コード 1 |
| `--no-lsp` | フラグ | いいえ | 無し | LSP サーバを起動しない |

- `--lang` は置かない。選べるのが TypeScript だけのうちは、選べるのに何も変わらない選択肢になる
- `--fail-on warn` は warn と risk の両方で落ちる
- **保留では落とさない。** 落とさなかった保留の件数は標準エラーに出す

## 終了コード

| コード | 条件 |
|:-------|:-----|
| 0 | 解析が終わり、`--fail-on` に当たる判定が無い（`--fail-on` 未指定を含む） |
| 1 | `--fail-on` に当たる判定がある |
| 2 | 解析を始められなかった（引数の誤り・`<dir>` が無い・`tightrope.toml` の誤り・出力先に書けない） |

## `tightrope.toml`

走査の根（`<dir>`）に置く。無くても動く。

```toml
[thresholds]
strong_from = "functional"        # intrusive / functional / model / contract
far_from = "other-directory"      # same-directory / other-directory / other-package
volatility_window_days = 180      # 1 以上の整数
volatile_from_commits = 5         # 1 以上の整数
```

| キー | 値 | 意味 |
|:-----|:---|:-----|
| `strong_from` | 強度の名前 | これ以上の強度を「強い」とする |
| `far_from` | 距離の名前 | これ以上の距離を「遠い」とする |
| `volatility_window_days` | 1 以上の整数 | 変動性を数える期間（日） |
| `volatile_from_commits` | 1 以上の整数 | 期間内にこの回数以上変わったら「変動性が高い」 |

- 既定値は [judgement-spec.md](./judgement-spec.md) が持つ。設定を読む側は**書かれていたかどうかと値だけ**を持ち、既定値を持たない
- 書かれていないキーは既定値になる
- **知らないキー・知らない値・範囲外の値はエラーにして止める**（終了コード 2）。黙って既定値にしない

## エラーハンドリング

| エラーケース | 発生条件 | 振る舞い | 終了コード |
|:------------|:---------|:---------|:-----------|
| 走査の根が無い | `<dir>` が存在しない・ディレクトリでない | 標準エラーにパスを出して止める | 2 |
| 設定ファイルの誤り | TOML として読めない・知らないキー・知らない値・範囲外 | どのキーのどの値が駄目かを出して止める | 2 |
| 出力先に書けない | `-o` のパスに書けない | パスと理由を出して止める | 2 |
| LSP サーバが無い | `typescript-language-server` が見つからない・起動しない | 標準エラーに出して `--no-lsp` と同じ扱いで続ける | 0 / 1 |
| git が使えない | git のリポジトリでない・`git` が無い | 変動性を「取れなかった」にして続ける | 0 / 1 |
| ファイルが読めない | 権限・UTF-8 でない | そのファイルを解析から外し、件数とパスを出す | 0 / 1 |

## 制限事項

- 走査の根は 1 つだけ
- LSP サーバは `PATH` 上の `typescript-language-server` を使う。場所を指定する引数は置かない

## 関連仕様

- [judgement-spec.md](./judgement-spec.md) - しきい値の既定値と、`--fail-on` が見る判定
- [output-spec.md](./output-spec.md) - `--format` ごとの見せ方
- [coupling-json-spec.md](./coupling-json-spec.md) - `--format json` の中身
