//! tightrope の本体。`src/main.rs` は引数を受けてここを呼ぶだけにする
//! (rules/architecture.md「lib と bin を分ける」)。

pub mod cli;
pub mod config;
pub mod distance;
pub mod strength;
