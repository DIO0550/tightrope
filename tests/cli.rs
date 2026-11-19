use std::process::Command;

const EXIT_CODE_USAGE: i32 = 2;

#[test]
fn test_binary_report_without_dir_exits_with_usage_code() {
    let status = Command::new(env!("CARGO_BIN_EXE_tightrope"))
        .arg("report")
        .status()
        .expect("tightrope のバイナリを起動できる");
    assert_eq!(status.code(), Some(EXIT_CODE_USAGE));
}
