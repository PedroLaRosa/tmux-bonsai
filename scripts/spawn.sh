#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "$0")/_lib.sh"
branch='' branches='' agent=$(wt_agent) prompt='' prompt_file='' window=off yes=off fanout=off
[ "${1:-}" != --fanout ] || { fanout=on; shift; }
while [ "$#" -gt 0 ]; do
 case "$1" in
  --branch|--branches|--agent|--prompt|--prompt-file)
   [ "$#" -ge 2 ] || { echo "$1 needs a value" >&2; exit 2; }
   case "$1" in --branch) branch=$2;; --branches) branches=$2; fanout=on;; --agent) agent=$2;; --prompt) prompt=$2;; --prompt-file) prompt_file=$2;; esac; shift;;
  --window) window=on;; --yes) yes=on;; *) echo "unknown spawn option: $1" >&2; exit 2;;
 esac; shift
done
if [ -n "$prompt_file" ]; then
 [ -z "$prompt" ] || { echo 'Use --prompt or --prompt-file, not both.' >&2; exit 2; }
 prompt=$(cat "$prompt_file") || exit 1
fi
if [ "$fanout" = on ]; then
 [ -n "$branches" ] || { echo 'fanout requires --branches a,b,c' >&2; exit 2; }
 # Resolve confirmations before creating worktrees and starting any agent.
 if [ "$yes" != on ] && [ -n "$prompt" ]; then
  printf 'Create agents for %s and send:\n%s\nConfirm [y/N]: ' "$branches" "$prompt"
  IFS='' read -r answer || exit 1; case "$answer" in y|Y|yes) :;; *) exit 1;; esac
 fi
 IFS=, read -r -a targets <<< "$branches"
 for branch in "${targets[@]}"; do
  args=(--branch "$branch" --agent "$agent" --yes)
  [ "$window" = off ] || args+=(--window)
  [ -z "$prompt" ] || args+=(--prompt "$prompt")
  "$BONSAI_SCRIPTS/spawn.sh" "${args[@]}" || exit 1
 done; exit
fi
[ -n "$branch" ] || { echo 'usage: bonsai spawn --branch NAME [--window] [--agent CLI] [--prompt TEXT|--prompt-file FILE] [--yes]' >&2; exit 2; }
git check-ref-format --branch "$branch" >/dev/null || exit 2
command -v "$agent" >/dev/null || { echo "Agent executable not found: $agent" >&2; exit 1; }
if [ "$yes" != on ] && [ -n "$prompt" ]; then
 printf 'Create %s on %s and send:\n%s\nConfirm [y/N]: ' "$agent" "$branch" "$prompt"
 IFS='' read -r answer || exit 1; case "$answer" in y|Y|yes) :;; *) exit 1;; esac
fi
path=$(wt_path_of "$branch")
if [ -z "$path" ]; then
 if git show-ref --verify --quiet "refs/heads/$branch"; then wt switch --no-hooks --no-cd "$branch" >&2
 else wt switch --create --no-hooks --no-cd "$branch" >&2; fi || exit 1
 path=$(wt_path_of "$branch"); wt_copy_ignored "$path"
fi
[ -n "$path" ] || { echo 'Could not resolve the worktree path.' >&2; exit 1; }
printf -v launch '%q' "$agent"
printf -v shell_command '%q' "${SHELL:-/bin/bash}"
launch="$launch; exec $shell_command"
name=$(wt_sanitize "$branch")
if [ "$window" = on ]; then
 pane=$(tmx new-window -d -P -F '#{pane_id}' -c "$path" -n "$name" "$launch") || exit 1
else
 if tmx has-session -t "=$name" 2>/dev/null; then
  pane=$(tmx new-window -d -P -F '#{pane_id}' -t "$name:" -c "$path" -n "$agent" "$launch") || exit 1
 else pane=$(tmx new-session -d -P -F '#{pane_id}' -s "$name" -c "$path" "$launch") || exit 1; fi
fi
# Set startup evidence only while no hook has claimed the pane. The tmux
# condition and option writes execute together, avoiding a first-hook overwrite.
agent_type=${agent##*/}
launch_ts=$(date +%s)
tracking="set-option -p -t $pane @agent_type $(bonsai_shell_quote "$agent_type"); set-option -p -t $pane @agent_state unknown; set-option -p -t $pane @agent_launch_ts $launch_ts"
tmx if-shell -F -t "$pane" '#{==:#{@agent_type},}' "$tracking"
printf '%s\n' "$pane"
if [ -n "$prompt" ]; then
 start=$SECONDS
 while :; do
  ready=$(tmx show-option -pqv -t "$pane" @agent_state 2>/dev/null) || {
   echo "Agent in $pane exited before becoming ready; prompt was not sent." >&2; exit 1;
  }
  case "$ready" in idle|done|waiting) break;; exited|error) echo "Agent in $pane failed before becoming ready; prompt was not sent." >&2; exit 1;; esac
  if [ "$((SECONDS-start))" -ge 30 ]; then
   echo "No ready hook/title from $pane within 30s; prompt was not sent. Use bonsai reply when ready." >&2; exit 124
  fi
  sleep 0.2
 done
 "$BONSAI_SCRIPTS/reply.sh" "$pane" --yes -- "$prompt"
fi
