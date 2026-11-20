use super::*;

/// `tests/fixtures/typescript-paths/` 配下のディレクトリ。
///
/// カレントディレクトリではなくマニフェストの位置から組み立てる
/// （テストの実行位置に依存させない）。
fn fixture(relative_path: &str) -> PathBuf {
    PathBuf::from(format!(
        "{}/tests/fixtures/typescript-paths/{relative_path}",
        env!("CARGO_MANIFEST_DIR")
    ))
}

/// 根の下の TypeScript のファイルのパスを並べ替えたもの。
///
/// 並びは決めない関数なので並べ替えて比べる。Why not（集合にして比べる）: 同じパスを
/// 2 回返しても 1 件に潰れて通る。
fn sorted_typescript_paths_of(root: &Path) -> Vec<PathBuf> {
    let mut paths = typescript_paths_of(root).expect("フィクスチャのディレクトリはある");
    paths.sort();
    paths
}

/// 根に相対パスを付けたパスを並べ替えたもの。
fn sorted_paths_under(root: &Path, relative_paths: &[&str]) -> Vec<PathBuf> {
    let mut paths: Vec<PathBuf> = relative_paths
        .iter()
        .map(|relative_path| root.join(relative_path))
        .collect();
    paths.sort();
    paths
}

/// フィクスチャのそのパスがシンボリックリンクであることを表明する。
///
/// Why: `core.symlinks=false` で展開するとリンクが通常ファイルになり、ディレクトリ側のテストは
/// リンクの分岐を通らずに通り、ファイル側のテストは理由の出ない比較で落ちる。
fn assert_is_symlink(path: &Path) {
    let metadata = fs::symlink_metadata(path).expect("フィクスチャのリンクはある");
    assert!(
        metadata.file_type().is_symlink(),
        "フィクスチャがリンクとして展開されていない（core.symlinks を確かめる）: {}",
        path.display()
    );
}

#[test]
fn test_typescript_paths_of_a_directory_with_js_and_json_returns_only_typescript_files() {
    // 対照は同じディレクトリの `script.js` / `data.json`
    let root = fixture("extensions");

    let paths = sorted_typescript_paths_of(&root);

    assert_eq!(
        paths,
        sorted_paths_under(&root, &["a.ts", "b.tsx", "c.mts", "d.cts", "e.d.ts"])
    );
}

#[test]
fn test_typescript_paths_of_nested_directories_returns_a_file_two_levels_down() {
    let root = fixture("nested");

    let paths = sorted_typescript_paths_of(&root);

    assert_eq!(paths, sorted_paths_under(&root, &["a/b/deep.ts"]));
}

#[test]
fn test_typescript_paths_of_a_directory_named_like_a_typescript_file_returns_its_contents_only() {
    // `x.ts` はディレクトリ。ディレクトリかどうかより先に拡張子で見ると、ディレクトリ自身が返る
    let root = fixture("directory-named-like-a-file");

    let paths = sorted_typescript_paths_of(&root);

    assert_eq!(paths, sorted_paths_under(&root, &["x.ts/inner.ts"]));
}

#[test]
fn test_typescript_paths_of_a_symlinked_directory_does_not_walk_into_it() {
    // 対照はリンク先の実体 `real/`。リンクを辿ると `linked/x.ts` でも同じファイルが返る
    let root = fixture("symlinked-directory");
    assert_is_symlink(&root.join("linked"));

    let paths = sorted_typescript_paths_of(&root);

    assert_eq!(paths, sorted_paths_under(&root, &["real/x.ts"]));
}

#[test]
fn test_typescript_paths_of_a_symlinked_file_leaves_it_out() {
    // 対照はリンク先の実体 `real.ts`。リンクを返すと同じファイルが `alias.ts` でも返る
    let root = fixture("symlinked-file");
    assert_is_symlink(&root.join("alias.ts"));

    let paths = sorted_typescript_paths_of(&root);

    assert_eq!(paths, sorted_paths_under(&root, &["real.ts"]));
}

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
