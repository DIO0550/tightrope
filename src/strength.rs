//! 統合強度の語彙。
//!
//! 構文解析・pipeline が作り、判定が比べ、設定が書き、レポートが出す語彙なので、
//! どの段の下にも置かない。

/// 統合強度。相手のどこまでを知って使っているかの度合い。
///
/// どの強度になるかの決め方は `docs/report/strength-spec.md`「強度の段」にある。
// derive(Ord) は宣言順で比べるので、弱い順に宣言して強いほど大きくする（強い順に並べ替えない）。
// 強い順に宣言して Ord を手で書く案は、順序の情報が宣言と Ord 実装の 2 か所に分かれるので採らない。
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
mod tests {
    use super::*;

    #[test]
    fn test_strength_intrusive_vs_functional_is_stronger() {
        assert!(
            Strength::Intrusive > Strength::Functional,
            "Intrusive should be stronger than Functional"
        );
    }

    #[test]
    fn test_strength_functional_vs_model_is_stronger() {
        assert!(
            Strength::Functional > Strength::Model,
            "Functional should be stronger than Model"
        );
    }

    #[test]
    fn test_strength_model_vs_contract_is_stronger() {
        assert!(
            Strength::Model > Strength::Contract,
            "Model should be stronger than Contract"
        );
    }
}
