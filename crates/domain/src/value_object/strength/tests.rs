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
