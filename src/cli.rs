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
mod tests;
