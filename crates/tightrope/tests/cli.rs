use std::process::Command;

const EXIT_CODE_SUCCESS: i32 = 0;
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

#[test]
fn test_binary_help_flag_exits_with_success_printing_usage_to_stdout() {
    let output = Command::new(env!("CARGO_BIN_EXE_tightrope"))
        .arg("--help")
        .output()
        .expect("tightrope のバイナリを起動できる");
    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    assert_eq!(
        output.status.code(),
        Some(EXIT_CODE_SUCCESS),
        "--help は成功の終了コードで終わる。stderr: {stderr}"
    );
    assert!(
        stdout.contains("Usage: tightrope"),
        "標準出力に使い方が出る。stdout: {stdout}"
    );
    assert!(
        stderr.is_empty(),
        "標準エラーには何も出ない。stderr: {stderr}"
    );
}
