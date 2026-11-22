//! 走査の根に置く `tightrope.toml` を読む。
//!
//! ファイルを読む [`config_text_of`] と、読んだ文字列を解釈する
//! [`WrittenThresholds::from_config_text`] を分け、解釈の側には I/O を持ち込まない。

use std::fs;
use std::io;
use std::path::Path;

const CONFIG_FILE_NAME: &str = "tightrope.toml";
const THRESHOLDS_TABLE: &str = "thresholds";

/// `[thresholds]` の 4 キーそれぞれについて、書かれていたかどうかと書かれていた値。
///
/// `None` は書かれていないこと、`Some` は書かれていた値を解釈せずに `toml::Value` のまま持つ。
/// 既定値は持たない。
#[derive(Debug, PartialEq)]
pub struct WrittenThresholds {
    pub strong_from: Option<toml::Value>,
    pub far_from: Option<toml::Value>,
    pub volatility_window_days: Option<toml::Value>,
    pub volatile_from_commits: Option<toml::Value>,
}

impl WrittenThresholds {
    /// `tightrope.toml` の中身を解釈し、`[thresholds]` に書かれていたキーを拾う。
    ///
    /// `config_text` は [`config_text_of`] が返した中身で、`None` はファイルが無いことを表す。
    /// ファイルが無い・空・`[thresholds]` が無いときは、4 キーとも書かれていないとして返す。
    ///
    /// 知らないキーと、`thresholds` がテーブルでない形は、書かれていないとして扱う
    /// (`docs/report/cli-spec.md` はこれらをエラーにするので、仕様とは扱いが違う)。
    ///
    /// # Errors
    ///
    /// `config_text` が TOML として読めないときに `Err` を返す。
    pub fn from_config_text(config_text: Option<&str>) -> Result<Self, toml::de::Error> {
        let table = match config_text {
            Some(config_text) => config_text.parse::<toml::Table>()?,
            None => toml::Table::new(),
        };

        let thresholds = table.get(THRESHOLDS_TABLE).and_then(toml::Value::as_table);
        let written = |key: &str| {
            thresholds
                .and_then(|thresholds| thresholds.get(key))
                .cloned()
        };

        Ok(Self {
            strong_from: written("strong_from"),
            far_from: written("far_from"),
            volatility_window_days: written("volatility_window_days"),
            volatile_from_commits: written("volatile_from_commits"),
        })
    }
}

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

#[cfg(test)]
mod tests;
