use crate::translation::config::*;

#[test]
fn test_from_config_text_four_keys_each_hold_own_value() {
    let text = r#"
[thresholds]
strong_from = "functional"
far_from = "other-directory"
volatility_window_days = 180
volatile_from_commits = 5
"#;
    let written =
        WrittenThresholds::from_config_text(Some(text)).expect("four keys should be interpretable");
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
