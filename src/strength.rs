//! 統合強度の語彙。

/// 統合強度。相手のどこまでを知って使っているかの度合い。
///
/// 比べると強いほど大きい（`Intrusive > Functional > Model > Contract`）。
///
/// どの強度になるかの決め方は `docs/report/strength-spec.md`「強度の段」にある。
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Strength {
    /// `import type` / `import { type X }` での依存か、型の位置で使っていて宣言が `interface` / `type` の型への依存。
    Contract,
    /// 型の位置で使っていて、宣言が `class` / `enum` の型への依存。
    Model,
    /// 相手の振る舞いに依存している。
    Functional,
    /// 公開口を飛ばして相手の内部に踏み込んでいる。
    Intrusive,
}

#[cfg(test)]
mod tests;
