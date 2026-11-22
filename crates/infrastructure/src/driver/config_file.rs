//! 走査の根に置く `tightrope.toml` の中身を、解釈せずに文字列のまま読む。

use std::fs;
use std::io;
use std::path::Path;

const CONFIG_FILE_NAME: &str = "tightrope.toml";

/// 走査の根 `root` に置かれた `tightrope.toml` の中身を読む。
///
/// `root` は存在するディレクトリであること。根が無いときも、ファイルが無いときと同じ
/// `Ok(None)` になる。
///
/// ファイルが無いときは `Ok(None)` を返す。シンボリックリンクは辿って読み、リンク先が無い
/// 壊れたリンクも `NotFound` になるので無いとして扱う。
///
/// # Errors
///
/// ファイルはあるが読めないとき(ディレクトリである・権限が無い・UTF-8 でない等)に `Err` を返す。
pub fn config_text_of(root: &Path) -> io::Result<Option<String>> {
    match fs::read_to_string(root.join(CONFIG_FILE_NAME)) {
        Ok(text) => Ok(Some(text)),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}
