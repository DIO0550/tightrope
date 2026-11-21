//! 依存 1 本の `from` と `to` がどれだけ離れているか(距離)の語彙。
//! 条件は `docs/report/distance-volatility-spec.md`「距離」。

/// 依存 1 本の距離。
///
/// 比べると近いほど小さい（`SameDirectory < OtherDirectory < OtherPackage`）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Distance {
    /// `from` と `to` が同じディレクトリにある。
    SameDirectory,
    /// ディレクトリが違い、package が同じ。
    OtherDirectory,
    /// package が違う(monorepo / workspace)。
    OtherPackage,
}

#[cfg(test)]
mod tests;
