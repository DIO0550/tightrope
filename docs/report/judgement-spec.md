# tightrope report - 判定仕様（バックエンド）

> **機能**: [tightrope report（MVP）](./index.md)

## 概要

依存 1 本の 3 軸（強度・距離・変動性）から、判定（risk / warn / tolerated / ok）か保留を決め、判定を傾けた根拠（reason）を付ける。**しきい値の既定値と決定木は、ここに書いた 1 箇所にだけ置く。**

## 判定の基本

```
BALANCE = (STRENGTH XOR DISTANCE) OR NOT VOLATILITY
```

（[計画書](../tightrope-plan.md)「判定の基本」）

## しきい値と既定値

| しきい値 | 設定のキー | 既定値 | 意味 |
|:---------|:-----------|:-------|:-----|
| 強いとみなす強度の下限 | `strong_from` | `functional` | これ以上（Intrusive / Functional）を「強い」 |
| 遠いとみなす距離の下限 | `far_from` | `other-directory` | これ以上を「遠い」 |
| 変動性を測る期間 | `volatility_window_days` | 180 | 日 |
| 変動性が高いとみなす変更回数 | `volatile_from_commits` | 5 | 期間内にこの回数以上で「高い」 |

設定（`tightrope.toml`）を読む側は既定値を持たない（[cli-spec.md](./cli-spec.md)）。

## 判定表

| 強度 | 距離 | 変動性が高い | 変動性が低い | 変動性が取れない |
|:-----|:-----|:-------------|:-------------|:-----------------|
| 強い | 遠い | **risk** | tolerated | 保留 |
| 弱い | 近い | **warn** | tolerated | 保留 |
| 強い | 近い | ok | ok | ok |
| 弱い | 遠い | ok | ok | ok |

| ID | ルール | 条件 | 振る舞い |
|:---|:-------|:-----|:---------|
| JDG-001 | バランスが良い | 強度 XOR 距離 | 変動性に関わらず ok。**変動性が取れなくても判定できる** |
| JDG-002 | 密結合 | 強い かつ 遠い | 変動性が高ければ risk、低ければ tolerated |
| JDG-003 | 低凝集 | 弱い かつ 近い | 変動性が高ければ warn、低ければ tolerated |
| JDG-004 | 変動性の保留 | JDG-002 / JDG-003 に当たり、変動性が取れない | 保留。理由 `volatility-unavailable` |
| JDG-005 | 強度の保留 | 強い / 弱いが決まらない（[strength-spec.md](./strength-spec.md)「LSP が答えないとき」） | 強い・弱いの両方で判定し、同じ答えならそれを使う。違えば保留。理由 `strength-unavailable` |
| JDG-006 | 判定の順 | — | risk > warn > tolerated > ok（`--fail-on` とホットスポットの並びに使う） |

- warn を risk より軽くするのは、低凝集は 1 箇所に寄せれば直る（直す先が近い）が、密結合は境界をまたいで直すことになるため

## 保留の持ち方

- 判定（verdict）の語彙は risk / warn / tolerated / ok の **4 つのまま**にする
- 保留は 5 つ目の判定ではなく、**「判定した」と「判定できなかった」を分けた外側の型**で持つ。判定できなかったときは理由を持ち、判定を持たない

```
judgement = judged(verdict) | undetermined(reason)
```

**Why（保留を tolerated で埋めない）**: git 履歴の無い環境で密結合がすべて tolerated になり、本当に変わらないのか測れなかったのかを読者が区別できない。

**Why not（verdict に 5 つ目を足す）**: verdict を受け取る側（`--fail-on`・並べ替え・色分け）がすべて「判定できなかった」を判定の 1 つとして扱うことになり、判定の段と出力の段の両方で意味が混ざる。

## reason

判定を傾けた根拠 1 件。人が読む文ではなく、値と向きの構造で持つ。文は出力の側が組み立てる。

| 項目 | 内容 |
|:-----|:-----|
| `axis` | `strength` / `distance` / `volatility` |
| `value` | その軸の値（取れなかったときは取れなかった理由） |
| `threshold` | 当てたしきい値 |
| `lean` | 傾けた向き。`strong` / `weak`、`far` / `near`、`volatile` / `stable`、取れなかったときは `none` |

- 判定 1 つにつき 3 軸の reason を必ず出す（ok でも出す）
- 改善のヒントは判定と reason から出力の側が組み立てる。判定の段は持たない

## 制限事項

- 数値スコアは出さない（HTML のホットスポットの並べ替えで要るようになったら、3 軸の段階から導く式を決める）
- 判定はファイル単位の依存だけ。パッケージ単位にまとめた判定は出さない

## 関連仕様

- [strength-spec.md](./strength-spec.md) / [distance-volatility-spec.md](./distance-volatility-spec.md) - 3 軸の値
- [coupling-json-spec.md](./coupling-json-spec.md) - `judgement` と `reasons` の出し方
- [cli-spec.md](./cli-spec.md) - しきい値の設定と `--fail-on`
