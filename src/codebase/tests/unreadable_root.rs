use super::fixture::fixture;
use crate::codebase::{CodebaseError, typescript_paths_of};
use std::error::Error;
use std::io;

#[test]
fn test_typescript_paths_of_a_missing_root_reports_the_root_as_unreadable() {
    let root = fixture("missing");

    let result = typescript_paths_of(&root);

    let Err(CodebaseError::DirectoryUnreadable { directory, .. }) = result else {
        panic!("存在しない根は DirectoryUnreadable になる");
    };
    assert_eq!(directory, root, "受け取った根をそのまま持つ");
}

#[test]
fn test_typescript_paths_of_a_file_as_the_root_reports_the_root_as_unreadable() {
    let root = fixture("extensions/a.ts");

    let result = typescript_paths_of(&root);

    let Err(CodebaseError::DirectoryUnreadable { directory, .. }) = result else {
        panic!("ディレクトリでない根は DirectoryUnreadable になる");
    };
    assert_eq!(directory, root, "受け取った根をそのまま持つ");
}

#[test]
fn test_codebase_error_of_a_missing_root_displays_the_root() {
    let root = fixture("missing");

    let error = typescript_paths_of(&root).expect_err("存在しない根は走査できない");

    let message = error.to_string();
    assert!(
        message.contains(&root.display().to_string()),
        "読めなかったディレクトリが文に出ていない: {message}"
    );
}

#[test]
fn test_codebase_error_of_a_missing_root_has_the_not_found_io_error_as_its_source() {
    let root = fixture("missing");

    let error = typescript_paths_of(&root).expect_err("存在しない根は走査できない");

    let cause = error
        .source()
        .and_then(|source| source.downcast_ref::<io::Error>())
        .expect("原因の io::Error を持つ");
    assert_eq!(cause.kind(), io::ErrorKind::NotFound);
}
