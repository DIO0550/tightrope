# tightrope report - coupling.json 仕様（データ）

> **機能**: [tightrope report（MVP）](./index.md)

## 概要

`coupling.json` は解析結果のすべてを持つ JSON。terminal / markdown（と、後の HTML）は**これだけを入力にし、判定をやり直さない**。DB は持たないので、テーブルの代わりに JSON のスキーマを決める。

## 全体

```json
{
  "schema_version": 1,
  "root": "src",
  "history": { "head": "3aa4ece", "window_days": 180 },
  "thresholds": {
    "strong_from": "functional",
    "far_from": "other-directory",
    "volatility_window_days": 180,
    "volatile_from_commits": 5
  },
  "lsp": { "status": "used" },
  "modules": [ ... ],
  "dependencies": [ ... ],
  "unresolved_imports": [ ... ],
  "skipped_files": [ ... ],
  "summary": { ... }
}
```

| キー | 型 | 説明 |
|:-----|:---|:-----|
| `schema_version` | 整数 | このスキーマの版。互換でない変更で上げる |
| `root` | 文字列 | 走査の根（コマンドに渡されたとおり） |
| `history` | オブジェクト / 取れなかった | 数えた時点の `HEAD` と期間。git が使えなければ取れなかった形 |
| `thresholds` | オブジェクト | **実際に当てた**しきい値（既定値を含めて全部） |
| `lsp` | オブジェクト | `used` / 使わなかった理由（`disabled` / `server-unavailable`） |
| `modules` | 配列 | module ごと |
| `dependencies` | 配列 | 依存ごと |
| `unresolved_imports` | 配列 | 解決できなかった相対指定 |
| `skipped_files` | 配列 | 読めずに外したファイルと理由 |
| `summary` | オブジェクト | 件数のまとめ |

## modules

```json
{
  "path": "src/order/order.ts",
  "language": "typescript",
  "loc": 120,
  "package": ".",
  "volatility": { "status": "measured", "commits": 7 }
}
```

| キー | 型 | 説明 |
|:-----|:---|:-----|
| `path` | 文字列 | 走査の根からの相対パス。区切りは `/` |
| `language` | 文字列 | MVP では `typescript` のみ |
| `loc` | 整数 | 行数（空行を含む） |
| `package` | 文字列 | package のディレクトリ（走査の根からの相対、根なら `.`） |
| `volatility` | 取れた / 取れなかった | `{ "status": "measured", "commits": N }` か `{ "status": "unavailable", "reason": "..." }` |

## dependencies

```json
{
  "from": "src/billing/invoice.ts",
  "to": "src/order/order.ts",
  "strength": { "status": "measured", "value": "functional" },
  "distance": "other-directory",
  "refs": 3,
  "judgement": { "status": "judged", "verdict": "risk" },
  "reasons": [
    { "axis": "strength", "value": "functional", "threshold": "functional", "lean": "strong" },
    { "axis": "distance", "value": "other-directory", "threshold": "other-directory", "lean": "far" },
    { "axis": "volatility", "value": 7, "threshold": 5, "lean": "volatile" }
  ],
  "evidence": [
    { "path": "src/billing/invoice.ts", "line": 12, "strength": "functional", "code": "calculateTotal(order)" }
  ]
}
```

| キー | 型 | 説明 |
|:-----|:---|:-----|
| `from` / `to` | 文字列 | module の `path` |
| `strength` | 取れた / 一部取れなかった | `{ "status": "measured", "value": "..." }`、Model / Contract が未確定の evidence を含むときは `{ "status": "partial", "value": "<確定分の最大>", "unresolved": N }` |
| `distance` | 文字列 | `same-directory` / `other-directory` / `other-package` |
| `refs` | 整数 | evidence の数 |
| `judgement` | 判定した / できなかった | `{ "status": "judged", "verdict": "risk" }` か `{ "status": "undetermined", "reason": "volatility-unavailable" }` |
| `reasons` | 配列 | 3 軸ぶん（[judgement-spec.md](./judgement-spec.md)「reason」） |
| `evidence` | 配列 | 参照箇所。`strength` は確定しなければ `"model-or-contract"` |

- 依存の変動性は `to` の module が持つので、依存の側には重ねて書かない（reason に当てた値が出る）
- 改善のヒント（構想メモの `hint`）は持たない。出力の側が判定と reason から組み立てる

## unresolved_imports / skipped_files

```json
{ "path": "src/app.ts", "line": 3, "specifier": "./missing" }
{ "path": "src/legacy.ts", "reason": "not-utf8" }
```

## summary

```json
{
  "modules": 42,
  "dependencies": 118,
  "verdicts": { "risk": 2, "warn": 5, "tolerated": 9, "ok": 100 },
  "undetermined": 2
}
```

## データ整合性

| ルール | 説明 |
|:-------|:-----|
| 並びは決定的 | `modules` はパス順、`dependencies` は `from` → `to` 順、`evidence` は行順。同じ入力から同じ JSON が出ないと、CI の成果物を比べられない |
| 取れなかった値の形 | `status` と `reason` を持つ形で統一する。`null` や 0 で埋めない |
| 判定と reason の一致 | `reasons` の `lean` から判定表を引くと `judgement` に一致する |
| `summary` | `dependencies` から数え直した値と一致する |
| 時刻 | 生成時刻は持たない（再現性のため）。履歴は `history.head` で特定する |

## 制限事項

- スキーマの版を上げたときの移行手段は持たない（MVP の間は `schema_version: 1` のまま変えうる）

## 関連仕様

- [judgement-spec.md](./judgement-spec.md) - `judgement` / `reasons` の中身
- [output-spec.md](./output-spec.md) - この JSON から作る出力
