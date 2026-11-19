//! 引数の受け口と値の解釈。

use std::path::PathBuf;

use clap::{Args, Parser};

/// コマンドと引数を受け取る。
#[derive(Debug, Parser)]
pub enum Cli {
    /// 走査の根を受け取る。
    Report(ReportArgs),
}

/// `report` が受け取る引数。
#[derive(Debug, Args)]
pub struct ReportArgs {
    /// 走査の根。
    // 省くと clap はフィールド名から `<ROOT>` を出し、docs/report/cli-spec.md「コマンド」の
    // `<dir>` と食い違う。
    #[arg(value_name = "dir")]
    pub(crate) root: PathBuf,
}

#[cfg(test)]
mod tests {
    use clap::error::ErrorKind;

    use super::*;

    const EXIT_CODE_CANNOT_START: i32 = 2;

    #[test]
    fn test_report_with_dir_takes_dir_as_root() {
        let Cli::Report(args) =
            Cli::try_parse_from(["tightrope", "report", "src"]).expect("<dir> を渡せば解釈できる");
        assert_eq!(args.root, PathBuf::from("src"));
    }

    #[test]
    fn test_report_without_dir_fails_with_usage_exit_code() {
        let error =
            Cli::try_parse_from(["tightrope", "report"]).expect_err("<dir> が無ければ解釈できない");
        assert_eq!(error.kind(), ErrorKind::MissingRequiredArgument);
        assert_eq!(error.exit_code(), EXIT_CODE_CANNOT_START);
    }

    #[test]
    fn test_report_without_dir_names_dir_in_message() {
        let error =
            Cli::try_parse_from(["tightrope", "report"]).expect_err("<dir> が無ければ解釈できない");
        assert!(
            error.to_string().contains("<dir>"),
            "エラー文が <dir> を名指ししていない: {error}"
        );
    }

    #[test]
    fn test_report_with_two_dirs_fails_with_usage_exit_code() {
        let error = Cli::try_parse_from(["tightrope", "report", "a", "b"])
            .expect_err("走査の根は 1 つだけ");
        assert_eq!(error.kind(), ErrorKind::UnknownArgument);
        assert_eq!(error.exit_code(), EXIT_CODE_CANNOT_START);
    }
}
