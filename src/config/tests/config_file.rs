use crate::config::*;
use std::path::PathBuf;

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/config")
        .join(name)
}

#[test]
fn test_config_text_of_absent_file_reads_no_keys_written() {
    let text = config_text_of(&fixture("absent")).expect("absent config should not be an error");
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
