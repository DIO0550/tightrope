//! ファイルシステムを読む。走査の根の下を歩いて、対象のファイルのパスを集めるところまでを持つ。
//!
//! ファイルシステムに触る I/O の境界（rules/coding.md「I/O を持ってよい場所」）。
//!
//! 移植元は dryguard（<https://github.com/DIO0550/dryguard>）の `src/codebase.rs`、
//! コミット `082c274`。

use std::error::Error;
use std::ffi::OsStr;
use std::fmt;
use std::fs::{self, FileType};
use std::io;
use std::path::{Path, PathBuf};

/// 集める TypeScript のファイルの拡張子。
///
/// `.d.ts` も `ts` で入る（`Path::extension` は最後の拡張子を返す）。
const TYPESCRIPT_EXTENSIONS: [&str; 4] = ["ts", "tsx", "mts", "cts"];

/// 走査の根の下を再帰的に辿り、TypeScript のファイルのパスを返す。
///
/// `root` は走査を始めるディレクトリ。返すパスは `root` を前に付けた形で、並びは決めない。
///
/// 走査の途中で見つけたシンボリックリンクは、ディレクトリのリンクもファイルのリンクも辿らず、返さない
/// （エントリの種類はリンク自身の種類で見る）。`root` そのものがディレクトリへのリンクなら、それは
/// 解決してリンク先の中身を走査し、返すパスはリンクのパスを前に付けた形になる。
///
/// # Errors
///
/// 根か途中のディレクトリを読めない・その中身の種類を取れないとき
/// （[`CodebaseError::DirectoryUnreadable`]）。根が無い・ディレクトリでないときも、
/// `directory` に根を入れてこのエラーになる。
pub fn typescript_paths_of(root: &Path) -> Result<Vec<PathBuf>, CodebaseError> {
    let mut paths = Vec::new();
    let mut pending = vec![root.to_path_buf()];

    while let Some(directory) = pending.pop() {
        for (path, file_type) in entries_of(&directory)? {
            if file_type.is_dir() {
                pending.push(path);
                continue;
            }

            let is_typescript_file = file_type.is_file() && has_typescript_extension(&path);
            if is_typescript_file {
                paths.push(path);
            }
        }
    }

    Ok(paths)
}

/// そのパスの拡張子が、集める TypeScript の拡張子のどれかか。
fn has_typescript_extension(path: &Path) -> bool {
    path.extension()
        .and_then(OsStr::to_str)
        .is_some_and(|extension| TYPESCRIPT_EXTENSIONS.contains(&extension))
}

/// そのディレクトリの中身の、パスとリンクを辿らない種類の組。
///
/// # Errors
///
/// ディレクトリを読めない・中身の種類を取れないとき。どのディレクトリで失敗したかを持つ。
fn entries_of(directory: &Path) -> Result<Vec<(PathBuf, FileType)>, CodebaseError> {
    let unreadable = |cause: io::Error| CodebaseError::DirectoryUnreadable {
        directory: directory.to_path_buf(),
        cause,
    };

    fs::read_dir(directory)
        .map_err(unreadable)?
        .map(|entry| {
            let entry = entry?;
            Ok((entry.path(), entry.file_type()?))
        })
        .collect::<Result<Vec<(PathBuf, FileType)>, io::Error>>()
        .map_err(unreadable)
}

/// コードベースを走査できなかった理由。
#[derive(Debug)]
pub enum CodebaseError {
    /// ディレクトリを読めなかった。
    DirectoryUnreadable {
        /// 読めなかったディレクトリ。
        directory: PathBuf,
        /// 読もうとして返ったエラー。
        cause: io::Error,
    },
}

impl fmt::Display for CodebaseError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::DirectoryUnreadable { directory, cause } => {
                write!(formatter, "{} を読めません: {cause}", directory.display())
            }
        }
    }
}

impl Error for CodebaseError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::DirectoryUnreadable { cause, .. } => Some(cause),
        }
    }
}

#[cfg(test)]
mod tests;
