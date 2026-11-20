use crate::codebase::typescript_paths_of;
use std::fs;
use std::path::{Path, PathBuf};

/// `tests/fixtures/typescript-paths/` 配下のディレクトリ。マニフェストの位置から組み立てる。
pub(super) fn fixture(relative_path: &str) -> PathBuf {
    PathBuf::from(format!(
        "{}/tests/fixtures/typescript-paths/{relative_path}",
        env!("CARGO_MANIFEST_DIR")
    ))
}

/// 根の下の TypeScript のファイルのパスを並べ替えたもの。
pub(super) fn sorted_typescript_paths_of(root: &Path) -> Vec<PathBuf> {
    let mut paths = typescript_paths_of(root).expect("フィクスチャのディレクトリはある");
    paths.sort();
    paths
}

/// 根に相対パスを付けたパスを並べ替えたもの。
pub(super) fn sorted_paths_under(root: &Path, relative_paths: &[&str]) -> Vec<PathBuf> {
    let mut paths: Vec<PathBuf> = relative_paths
        .iter()
        .map(|relative_path| root.join(relative_path))
        .collect();
    paths.sort();
    paths
}

/// フィクスチャのそのパスがシンボリックリンクであることを表明する。
pub(super) fn assert_is_symlink(path: &Path) {
    let metadata = fs::symlink_metadata(path).expect("フィクスチャのリンクはある");
    assert!(
        metadata.file_type().is_symlink(),
        "フィクスチャがリンクとして展開されていない（core.symlinks を確かめる）: {}",
        path.display()
    );
}
