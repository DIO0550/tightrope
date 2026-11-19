//! 依存 1 本の `from` と `to` がどれだけ離れているか(距離)の語彙。
//! 条件は `docs/report/distance-volatility-spec.md`「距離」。
//!
//! Why: config・judgement・report・距離の計測という複数の段が使う語彙なので、どの段の下にも置かない。
//! Why not: 同一ファイル・別チームの段は置かない。理由は同節の箇条。

/// 依存 1 本の距離。近いほど小さい。
///
/// Why: `Ord` は宣言順から derive する。並べ替えると遠さの比較が変わる。
/// Why not: 手書きの `Ord` は、順序を宣言と `match` の 2 箇所に持つことになる。
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
mod tests {
    use super::*;

    #[test]
    fn test_distance_same_directory_is_nearer_than_other_directory() {
        assert!(Distance::SameDirectory < Distance::OtherDirectory);
    }

    #[test]
    fn test_distance_other_directory_is_nearer_than_other_package() {
        assert!(Distance::OtherDirectory < Distance::OtherPackage);
    }
}
