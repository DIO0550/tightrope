use std::process::Command;

const EXIT_CODE_CANNOT_START: i32 = 2;

#[test]
fn test_binary_report_without_dir_exits_with_usage_code_naming_dir() {
    let output = Command::new(env!("CARGO_BIN_EXE_tightrope"))
        .arg("report")
        .output()
        .expect("tightrope のバイナリを起動できる");
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(
        output.status.code(),
        Some(EXIT_CODE_CANNOT_START),
        "<dir> が無いときは起動できない終了コードで止まる。stderr: {stderr}"
    );
    assert!(
        stderr.contains("<dir>"),
        "標準エラーが足りない引数 <dir> を名指しする。stderr: {stderr}"
    );
}
