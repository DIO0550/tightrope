# tightrope report - 統合強度仕様（バックエンド）

> **機能**: [tightrope report（MVP）](./index.md)

## 概要

依存 1 本の中の参照箇所（evidence）ごとに統合強度を決め、依存の強度にまとめる。構文で決まるものは tree-sitter で決め、型の位置の参照だけ LSP の definition で宣言を確かめる。

## 強度の段

強い順に Intrusive > Functional > Model > Contract。

| 強度 | 何で決めるか | LSP が要るか |
|:-----|:-------------|:-------------|
| Intrusive | 公開口を飛ばした深い import（下の STR-001） | 要らない |
| Functional | import した名前を値として使っている（呼び出し・`new`・値としての参照） | 要らない |
| Model | 型の位置で使っていて、宣言が `class` / `enum` | **要る**（definition） |
| Contract | `import type` / `import { type X }`、または型の位置で使っていて、宣言が `interface` / `type` | `import type` なら要らない |

## ビジネスロジック

| ID | ルール | 条件 | 振る舞い |
|:---|:-------|:-----|:---------|
| STR-001 | 深い import | `to` の祖先ディレクトリ（走査の根まで）のうち `index.*` を持ち、`from` を含まないものが 1 つでもある。`to` がその `index.*` 自身なら当たらない | その import から来た evidence はすべて Intrusive |
| STR-002 | evidence の単位 | import した名前が `from` の中で使われている箇所 1 つ | evidence 1 件。`ファイル:行` と、その行のコードを持つ |
| STR-003 | 使われていない import | import した名前が 1 回も使われていない・副作用の import（`import "./x"`） | import 文そのものを evidence 1 件にする。強度は Functional（読み込みで実行されるため） |
| STR-004 | 名前空間の import | `import * as ns` | `ns.x` の使われ方で 1 件ずつ決める |
| STR-005 | 再輸出 | `export { x } from` / `export * from` | 再輸出文を evidence 1 件にする。強度は再輸出した名前の種類で決める（型だけなら Contract 側の規則、値なら Functional） |
| STR-006 | 型の位置の参照 | 型注釈・`implements` / `extends` の型・型引数 | definition で宣言を確かめ、宣言が `class` / `enum` なら Model、`interface` / `type` なら Contract |
| STR-007 | `extends` するクラス | `class A extends B` の `B` | 値として使っているので Functional |
| STR-008 | 依存の強度 | — | evidence のうち最も強いもの |
| STR-009 | refs | — | 依存 1 本が持つ evidence の数 |

### LSP が答えないとき

- `--no-lsp`、サーバが無い、definition が空・タイムアウトのとき、型の位置の evidence は **Model か Contract かを「取れなかった」にする**。0 や Contract で埋めない
- 依存の強度は「取れなかった evidence を除いた最も強いもの」と「取れなかった evidence が Model だった場合」の両方を考え、**強い / 弱いの判定が変わらないならその答えを使う**
- 既定のしきい値（`functional` 以上が強い）では Model も Contract も弱い側なので、判定は変わらない。`strong_from = "model"` のときだけ、その依存の強弱が「取れなかった」になり、判定は保留になりうる（[judgement-spec.md](./judgement-spec.md)）
- 依存の強度として出す値は、確定した evidence の最も強いものと、「Model / Contract が未確定」の印

**Why（判定に効かない欠けで判定を消さない）**: LSP の無い環境で判定がすべて消えると、構文だけで十分に決まる Intrusive / Functional の結果まで失う。

## 外部サービス連携

| サービス | 用途 | 通信方式 | フォールバック |
|:---------|:-----|:---------|:-------------|
| typescript-language-server | 型の位置の参照の宣言の場所（definition） | 子プロセス・JSON-RPC（stdio） | 上の「LSP が答えないとき」 |

- 問い合わせは**宣言の場所が一意に決まる単位**で 1 回だけにする。同じファイルの同じ import 名への型の位置の参照は、definition を 1 回だけ尋ねて結果を配る
- 宣言の種類（`class` / `interface` など）は、definition が返したファイルを tree-sitter で読んで決める

## 制限事項

- `as any` / `// @ts-ignore` などで内部に触る箇所は Intrusive に数えない
- パスの規約（`contracts/` / `dto/`）や設定による Model / Contract の補正はしない
- `abstract class` は Model として扱う
- 型の位置の参照の宣言が走査の外（`node_modules` など）にあるときは、宣言を読めないので「取れなかった」にする

## 関連仕様

- [dependency-spec.md](./dependency-spec.md) - evidence を拾う import
- [judgement-spec.md](./judgement-spec.md) - 強い / 弱いのしきい値
- [technical-spec.md](./technical-spec.md) - LSP クライアントの移植
