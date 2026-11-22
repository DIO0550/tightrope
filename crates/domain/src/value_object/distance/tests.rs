use super::*;

#[test]
fn test_distance_same_directory_is_nearer_than_other_directory() {
    assert!(Distance::SameDirectory < Distance::OtherDirectory);
}

#[test]
fn test_distance_other_directory_is_nearer_than_other_package() {
    assert!(Distance::OtherDirectory < Distance::OtherPackage);
}
