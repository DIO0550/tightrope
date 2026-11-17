# tightrope

モジュール間の結合を**統合強度・距離・変動性**の 3 軸で測り、バランスを理由付きで判定する CLI。
『ソフトウェア設計における結合のバランス』（Vlad Khononov）のモデルを使う。

- 解析: tree-sitter（構文）＋ LSP（意味情報）＋ git 履歴（変動性）
- 対象: TypeScript / Rust / Java / Swift
- 出力: `coupling.json` を元に terminal / markdown / html

構想と全体構成は [`docs/tightrope-plan.md`](docs/tightrope-plan.md)。**まだ実装は無く、開発環境だけがある。**

## 開発

```bash
cargo build
cargo fmt
cargo clippy --all-targets -- -D warnings
cargo test
PRE_PUSH_REQUIRE_ALL=1 bash harness/githooks/pre-push   # push 前の検査をすべて（CI の harness ジョブと同じ）
```

- 依存を足す・更新するときは `cargo add` / `cargo update` を素で叩かず、`harness/deps/resolve.sh` を通す
  （公開から 14 日経っていないバージョンを使わない。nightly が要る。[`harness/deps/README.md`](harness/deps/README.md)）
- git hooks は `bash harness/githooks/set-hooks-path.sh` で配線する（Claude Code のセッション開始時と DevContainer の作成時にも走るが、フックが読まれない環境もある）
- DevContainer は `.devcontainer/`

## 実装の進め方とハーネス

AI エージェントが実装する前提で、規約と検査を置いてある。入口は [`AGENTS.md`](AGENTS.md)（`CLAUDE.md` はその symlink）。

| 置き場所 | 持つもの |
| --- | --- |
| `rules/` | 常時読み込む規約（構造・コーディング・命名・テスト・TDD） |
| `harness/case-law/` | 規約の実例（判例）。迷ったときだけ読む |
| `harness/records/` | マージした PR ごとの振り返りの記録と、再発を数える `count.sh` |
| `harness/githooks/` | push 前の検査（層 2） |
| `.claude/skills/` | 実装の手順（`implementation-flow`）・記録（`harness-record`）・改善（`harness-growth`） |
| `.claude/agents/` | 計画・実装・観点別の検証を担うサブエージェント |
| `.claude/hooks/` | Claude Code のフック（層 3） |
| `.github/workflows/` | CI（層 1） |

検査の強さの序列は `AGENTS.md`「強制力の序列」。
