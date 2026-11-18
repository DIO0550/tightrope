# tightrope report - 出力仕様（フロントエンド）

> **機能**: [tightrope report（MVP）](./index.md)

## 概要

`coupling.json` から terminal の表と markdown を作る。画面は無いので、「表示データ」と「レイアウト」だけを決める。**出力の側は判定をやり直さない。**

## 表示データ

| フィールド | ソース | フォーマット | 取れなかったとき |
|:----------|:-------|:------------|:---------|
| 判定 | `judgement.verdict` | `RISK` / `WARN` / `TOLERATED` / `OK` | `HOLD`（理由を併記） |
| 依存 | `from` / `to` | `from → to` | — |
| 強度 | `strength.value` | 小文字の名前 | `partial` なら末尾に `?` |
| 距離 | `distance` | 小文字の名前 | — |
| 変動性 | `to` の module の `volatility.commits` | `7 回` | `—`（理由は詳細に出す） |
| refs | `refs` | 整数 | — |
| 理由 | `reasons` | 下の「理由の文」 | — |
| 根拠 | `evidence` | `path:line  code` | — |

### 理由の文

reason から組み立てる。例（risk の場合）:

```
強度 functional ≥ functional（強い）／距離 other-directory ≥ other-directory（遠い）／変動性 7 回 ≥ 5 回（高い）
```

## レイアウト（terminal）

既定では **risk / warn / 保留だけ**を判定の重い順に並べ、最後に件数のまとめを出す。tolerated と ok は件数だけ。

```
RISK  src/billing/invoice.ts → src/order/order.ts
      functional / other-directory / 7 回 / refs 3
      強度 functional ≥ functional（強い）／距離 other-directory ≥ other-directory（遠い）／変動性 7 回 ≥ 5 回（高い）
      src/billing/invoice.ts:12  calculateTotal(order)
      …ほか 2 件

WARN  ...

HOLD  src/a.ts → src/b.ts  変動性が取れなかった（not-a-git-repository）

modules 42 / dependencies 118 / risk 2 / warn 5 / tolerated 9 / ok 100 / 保留 2
解決できなかった import 1 件 / 読めなかったファイル 0 件 / LSP: 使用
```

- 根拠は依存ごとに先頭の 1 件だけ出し、残りは件数にする
- 色は端末が対応していれば判定ごとに付ける（`NO_COLOR` が設定されていれば付けない）
- 並び：判定の重い順 → `from` → `to`

## レイアウト（markdown）

PR コメントに貼る想定。terminal と同じ範囲（risk / warn / 保留）を表にし、根拠は `<details>` に畳む。

```markdown
## tightrope

| 判定 | 依存 | 強度 | 距離 | 変動性 | refs |
|:-----|:-----|:-----|:-----|:-------|-----:|
| 🔴 risk | `src/billing/invoice.ts` → `src/order/order.ts` | functional | other-directory | 7 回 | 3 |

<details><summary>根拠</summary>

- `src/billing/invoice.ts:12` `calculateTotal(order)`
</details>

modules 42 / dependencies 118 / risk 2 / warn 5 / tolerated 9 / ok 100 / 保留 2
```

## エラー表示

| ケース | 表示 |
|:-------|:-----|
| LSP を使わなかった | まとめの行に `LSP: 使わなかった（理由）` |
| git が使えなかった | まとめの行に `変動性: 取れなかった（理由）` |
| 該当する依存が 0 件 | 表の代わりに「risk / warn / 保留はありません」とまとめの行 |

## 制限事項

- tolerated / ok の依存を一覧で出す引数は置かない（必要なら `--format json` を読む）
- 改善のヒントは MVP では出さない

## 関連仕様

- [coupling-json-spec.md](./coupling-json-spec.md) - 入力
- [judgement-spec.md](./judgement-spec.md) - 判定と reason の意味
