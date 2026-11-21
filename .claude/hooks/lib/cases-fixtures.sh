#!/usr/bin/env bash
#
# フックの判定表(`*-cases.sh`)が共有する、ケースの前提の置き方。落ちる検出器・起動できない python3・
# 失敗する awk・本体が同じテストヘルパーを渡されたパスへ置くものと、サブエージェントの中の呼び出しの入力を組むもの、
# 使い捨ての git リポジトリを外の git の環境から切り離して入るもの、偽の sparse index に版を置くもの。
#
# 使う側: lib/verification-agent-cases.sh / lib/parent-session-edit-cases.sh /
# harness/githooks/lib/test-placement-cases.sh / harness/githooks/lib/test-file-length-cases.sh /
# .github/scripts/red-commits-cases.sh / .github/scripts/lock-publish-age-cases.sh /
# harness/deps/tool-cooldown-cases.sh
#
# 終了コードと出力の組を実物の検出器から決まった形で作れないので、判定表は検出器をスタブで作る
# (ここに置くのは判定表どうしが共有する落ちる側。報告の行を出すスタブは報告の綴りが違うので各判定表が持つ)。
#
# 起動できない python3 は、起動すると 127 で落ちる。`command -v python3` で疎通を見る実装は
# これを見つけてしまい、検出器を走らせて「落ちた」と読む(起動して見る `python3_usable` は
# 無いものと扱う)。

# サブエージェントの中の PreToolUse で、session_id と tool_input の間に挟むフィールドを出す(`,` で終わる)。
# サブエージェントの中の呼び出しは、入力に `agent_id` / `agent_type` が載る(並びは実物の入力に合わせた)。
#
# $1 ツール名
subagent_call_fields() {
  printf '"agent_id":"ab90e859b438c06a1","agent_type":"implementer","hook_event_name":"PreToolUse","tool_name":"%s",' "$1"
}

# 起動するとすぐ落ちる検出器のスタブを置く。どれも報告の行を出さない。
#
# $1 落ち方(`crash` は traceback、`summary-exit1` は要約の行だけを出して exit 1、
#    `usage` は使い方を出して exit 2)
# $2 スタブを書くパス
place_failing_detector() {
  local failure="$1" target="$2"
  case "$failure" in
    crash) printf 'raise RuntimeError("判定表: 検出器が途中で落ちる")\n' >"$target" ;;
    summary-exit1) printf 'import sys\nprint("違反は 0 件")\nsys.exit(1)\n' >"$target" ;;
    usage) printf 'import sys\nprint("使い方: 検査する対象を渡す")\nsys.exit(2)\n' >"$target" ;;
  esac
}

# 起動すると 127 で落ちる python3 を置き、PATH の先頭に足す値を返す。`broken` 以外なら空。
#
# $1 `broken` なら置く
# $2 置き場のディレクトリ(その下の `broken-bin/` に置く。後ろのケースへ残さないよう呼び出し側が消す)
python3_path_prefix() {
  [ "$1" = "broken" ] || return 0
  mkdir -p "$2/broken-bin"
  printf '#!/usr/bin/env bash\nexit 127\n' >"$2/broken-bin/python3"
  chmod +x "$2/broken-bin/python3"
  printf '%s:' "$2/broken-bin"
}

# 起動すると読めなかったと言って 2 で落ちる awk を置き、PATH の先頭に足す値を返す。
#
# Why(awk を差し替える): 走査の失敗を作りたいが、root で走るとパーミッションでファイルを読めなくできない。
#
# $1 置き場のディレクトリ(その下の `failing-bin/` に置く)
failing_awk_path_prefix() {
  mkdir -p "$1/failing-bin"
  printf '#!/bin/sh\necho "awk: cannot open" >&2\nexit 2\n' >"$1/failing-bin/awk"
  chmod +x "$1/failing-bin/awk"
  printf '%s:' "$1/failing-bin"
}

# 深さの違う 2 つの `__tests__/`(`a/__tests__/` と `b/c/__tests__/`)の `setup.ts` に、本体が同じヘルパーを置く。
#
# $1 置き場のディレクトリ(`src` にあたるもの)
place_duplicate_helpers() {
  local folder
  for folder in "$1/a/__tests__" "$1/b/c/__tests__"; do
    mkdir -p "$folder"
    printf 'function openedAt(path: string) {\n  return OpenedDocument.create({ path, document: sampleDocument() });\n}\n' \
      >"$folder/setup.ts"
  done
}

# 外から受け継いだ git の環境を消し、使い捨てのリポジトリのコミットを決まった設定と名前で作らせる。
#
# Why: linked worktree から push すると pre-push に GIT_DIR が渡り、残すと使い捨てのリポジトリの代わりに
# 外側を読む。
isolate_git_env() {
  unset $(git rev-parse --local-env-vars)
  unset $(compgen -e | grep -E '^GIT_TRACE')
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=cases GIT_AUTHOR_EMAIL=cases@example.invalid
  export GIT_COMMITTER_NAME=cases GIT_COMMITTER_EMAIL=cases@example.invalid
}

# ディレクトリへ cd し、git がそのリポジトリを指していることを確かめる。指していなければ表ごと止める。
#
# Why: `--show-toplevel` だけでは足りない。GIT_DIR が漏れていても `$dir` を返し、`--absolute-git-dir`
# だけが外側を指す。`--show-toplevel` の比較は、GIT_WORK_TREE だけが漏れたときの分として残す。
#
# $1 使い捨てのリポジトリのディレクトリ
enter_repo() {
  local dir="$1" real git_dir top is_own_repo=no
  cd "$dir" || exit 1
  real="$(pwd -P)"
  git_dir="$(git rev-parse --absolute-git-dir)"
  top="$(git rev-parse --show-toplevel)"
  [ "$git_dir" = "$real/.git" ] && [ "$top" = "$real" ] && is_own_repo=yes
  [ "$is_own_repo" = yes ] && return 0
  printf 'NG   %s ではなく別のリポジトリを指している(git dir: %s / toplevel: %s)\n' "$dir" "$git_dir" "$top"
  exit 1
}

# 偽の sparse index の、そのパスに版を 1 行足す。
#
# $1 index の根のディレクトリ
# $2 index の根からのパス
# $3 版の一覧の 1 行(JSON)
put_index_line() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" >>"$1/$2"
}
