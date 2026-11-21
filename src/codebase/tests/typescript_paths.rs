use super::fixture::{assert_is_symlink, fixture, sorted_paths_under, sorted_typescript_paths_of};

/// フィクスチャには対照の `script.js` / `data.json` も置いてある。
#[test]
fn test_typescript_paths_of_a_directory_with_js_and_json_returns_only_typescript_files() {
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

/// フィクスチャの `x.ts` はディレクトリ。
#[test]
fn test_typescript_paths_of_a_directory_named_like_a_typescript_file_returns_its_contents_only() {
    let root = fixture("directory-named-like-a-file");

    let paths = sorted_typescript_paths_of(&root);

    assert_eq!(paths, sorted_paths_under(&root, &["x.ts/inner.ts"]));
}

/// フィクスチャの `linked` は、対照の実体 `real/` へのリンク。
#[test]
fn test_typescript_paths_of_a_symlinked_directory_does_not_walk_into_it() {
    let root = fixture("symlinked-directory");
    assert_is_symlink(&root.join("linked"));

    let paths = sorted_typescript_paths_of(&root);

    assert_eq!(paths, sorted_paths_under(&root, &["real/x.ts"]));
}

/// フィクスチャの `alias.ts` は、対照の実体 `real.ts` へのリンク。
#[test]
fn test_typescript_paths_of_a_symlinked_file_leaves_it_out() {
    let root = fixture("symlinked-file");
    assert_is_symlink(&root.join("alias.ts"));

    let paths = sorted_typescript_paths_of(&root);

    assert_eq!(paths, sorted_paths_under(&root, &["real.ts"]));
}
