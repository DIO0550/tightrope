//! tightrope のバイナリが呼ぶ入口。`main.rs` は引数を受けてここを呼ぶだけにする
//! (rules/architecture.md「lib と bin を分ける」)。

pub use presentation::controller::cli;
