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
/// `None` は書かれていないこと、`Some` は書かれていた値を解釈せずに持つ。
/// 既定値はここでは持たない。
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
    /// `text` は [`config_text_of`] が返した中身で、`None` はファイルが無いことを表す。
    /// ファイルが無い・空・`[thresholds]` が無いときは、4 キーとも書かれていないとして返す。
    /// 知らないキーと、`thresholds` がテーブルでない形はまだ見ず、書かれていないとして扱う。
    ///
    /// # Errors
    ///
    /// `text` が TOML として読めないときに `Err` を返す。
    pub fn from_config_text(text: Option<&str>) -> Result<Self, toml::de::Error> {
        let table = match text {
            Some(text) => text.parse::<toml::Table>()?,
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
/// `root` は存在するディレクトリであることを前提にする。根が無くてもファイルが無いときと
/// 同じ `NotFound` になり、設定が無いことと区別できないため。
///
/// ファイルが無いときは `Ok(None)` を返す。
///
/// # Errors
///
/// ファイルはあるが読めないとき(ディレクトリである・権限が無い・UTF-8 でない等)に `Err` を返す。
pub fn config_text_of(root: &Path) -> io::Result<Option<String>> {
    match fs::read_to_string(root.join(CONFIG_FILE_NAME)) {
        Ok(text) => Ok(Some(text)),
        // 置かないのは仕様上「何も書かれていない」なので `None` にする。NotFound 以外は
        // 書いたのに読めなかった設定なので、無いとして既定値へ流さずに返す。
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(error) => Err(error),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn fixture(name: &str) -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/config")
            .join(name)
    }

    #[test]
    fn test_config_text_of_absent_file_reads_no_keys_written() {
        let text =
            config_text_of(&fixture("absent")).expect("absent config should not be an error");
        assert_eq!(text, None);
        let written = WrittenThresholds::from_config_text(text.as_deref())
            .expect("absent config should be interpretable");
        assert_eq!(
            written,
            WrittenThresholds {
                strong_from: None,
                far_from: None,
                volatility_window_days: None,
                volatile_from_commits: None,
            }
        );
    }

    #[test]
    fn test_config_text_of_empty_file_reads_no_keys_written() {
        let text = config_text_of(&fixture("empty")).expect("empty config should be readable");
        assert_eq!(text.as_deref(), Some(""));
        let written = WrittenThresholds::from_config_text(text.as_deref())
            .expect("empty config should be interpretable");
        assert_eq!(
            written,
            WrittenThresholds {
                strong_from: None,
                far_from: None,
                volatility_window_days: None,
                volatile_from_commits: None,
            }
        );
    }

    #[test]
    fn test_config_text_of_unreadable_file_is_error_not_absent() {
        let result = config_text_of(&fixture("directory"));
        assert!(result.is_err(), "expected Err, got {result:?}");
    }

    #[test]
    fn test_config_text_of_written_key_is_read_as_written() {
        let text = config_text_of(&fixture("written")).expect("written config should be readable");
        let written = WrittenThresholds::from_config_text(text.as_deref())
            .expect("written config should be interpretable");
        assert_eq!(
            written,
            WrittenThresholds {
                strong_from: Some(toml::Value::String("model".to_owned())),
                far_from: None,
                volatility_window_days: None,
                volatile_from_commits: None,
            }
        );
    }

    #[test]
    fn test_from_config_text_four_keys_each_hold_own_value() {
        let text = r#"
[thresholds]
strong_from = "functional"
far_from = "other-directory"
volatility_window_days = 180
volatile_from_commits = 5
"#;
        let written = WrittenThresholds::from_config_text(Some(text))
            .expect("four keys should be interpretable");
        assert_eq!(
            written,
            WrittenThresholds {
                strong_from: Some(toml::Value::String("functional".to_owned())),
                far_from: Some(toml::Value::String("other-directory".to_owned())),
                volatility_window_days: Some(toml::Value::Integer(180)),
                volatile_from_commits: Some(toml::Value::Integer(5)),
            }
        );
    }

    #[test]
    fn test_from_config_text_unclosed_table_header_is_error() {
        let result = WrittenThresholds::from_config_text(Some("[thresholds\n"));
        assert!(result.is_err(), "expected Err, got {result:?}");
    }

    #[test]
    fn test_from_config_text_thresholds_header_only_reads_no_keys_written() {
        let written = WrittenThresholds::from_config_text(Some("[thresholds]\n"))
            .expect("header-only config should be interpretable");
        assert_eq!(
            written,
            WrittenThresholds {
                strong_from: None,
                far_from: None,
                volatility_window_days: None,
                volatile_from_commits: None,
            }
        );
    }
}
