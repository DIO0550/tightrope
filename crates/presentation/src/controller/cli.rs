//! 引数の受け口と値の解釈。

use std::path::PathBuf;

use clap::{Args, Parser};

/// コマンドと引数を受け取る。
#[derive(Debug, Parser)]
pub enum Cli {
    /// 走査の根を受け取る。
    Report(ReportArgs),
}

impl Cli {
    /// このプロセスが起動時に受け取った引数を解釈し、解釈した `Cli` を返す。
    ///
    /// 使い方を求められたとき(`--help` / `-h` / `help`)は使い方を標準出力へ出し、終了コード 0 で
    /// プロセスを終える。解釈できないとき(必須の引数が無い・サブコマンドが無い・定義していない引数がある)は、
    /// 理由か使い方を標準エラーへ出し、終了コード 2 でプロセスを終える。どちらのときも戻らない。
    pub fn from_process_args() -> Self {
        <Self as Parser>::parse()
    }
}

/// `report` が受け取る引数。
#[derive(Debug, Args)]
pub struct ReportArgs {
    /// 走査の根。
    #[arg(value_name = "dir")]
    pub(crate) root: PathBuf,
}

#[cfg(test)]
mod tests;
