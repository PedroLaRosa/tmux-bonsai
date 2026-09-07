#!/usr/bin/env bash
# A single pane/process snapshot per refresh; no daemon.
set -uo pipefail
umask 077
. "$(dirname "$0")/_lib.sh"
us=$'\037'
options=$(tmx display-message -p "#{@bonsai-board-show-shells}$us#{@bonsai-board-sort}$us#{@bonsai-state-dir}$us#{@bonsai-idle-after}$us#{@bonsai-stale-after}$us#{@bonsai-glyphs}" 2>/dev/null) || options=''
IFS="$us" read -r all sort state_root idle_setting stale_setting glyph_setting <<< "$options"
mode=table all=${all:-off} sort=${sort:-state} compact=off
state_root=${state_root:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-bonsai}
state_filter='' branch_filter=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --compact) compact=on;; --json) mode=json;; --rows) mode=rows;; --counts) mode=counts;; --all) all=on;;
    --sort|--state|--branch)
      [ "$#" -ge 2 ] || { echo "bonsai list: $1 needs a value" >&2; exit 2; }
      case "$1" in --sort) sort=$2;; --state) state_filter=$2;; --branch) branch_filter=$2;; esac; shift;;
    *) echo "bonsai list: unknown option $1" >&2; exit 2;;
  esac; shift
done
command -v jq >/dev/null || { echo 'bonsai list requires jq' >&2; exit 1; }
cache="$state_root/cache"
known_cache="$cache/agent-pids-$(bonsai_server_key)"
mkdir -p "$cache"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/bonsai-list.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
# Sanitize option controls before adding record separators.
fmt='#{pane_id}'
# Enumerate bytes: control-character ranges depend on the tmux server locale
# and libc regex collation. An explicit class behaves the same on BSD/glibc.
controls=$'\001\002\003\004\005\006\007\010\011\012\013\014\015\016\017\020\021\022\023\024\025\026\027\030\031\032\033\034\035\036\037\177'
for field in session_name session_id window_name window_id pane_index pane_current_path pane_pid pane_current_command @agent_type @agent_state @agent_state_ts @agent_updated_ts @agent_seen_ts @agent_prompt @agent_msg @agent_ask @agent_tool @agent_session @agent_children @agent_model @agent_ctx pane_dead @agent_hook_ts window_index @agent_launch_ts; do
  fmt="$fmt$us#{s|[$controls]| |:$field}"
done
tmx list-panes -a -F "$fmt" > "$tmp/panes" 2>/dev/null || :
# A framing error must be visible; silently dropping a fragment hides agents.
# Validate before indexing metadata maps so errors identify the broken snapshot.
awk -F "$us" '
 NF!=26 || $1!~/^%[0-9]+$/ {
  printf "bonsai list: invalid pane snapshot at record %d (expected 26 fields; got %d)\n", NR, NF > "/dev/stderr"; exit 1
 }' "$tmp/panes" || exit 1
ps -eo pid=,ppid=,comm=,args='' > "$tmp/ps" 2>/dev/null || :
awk -v FS="$us" '
 NR==FNR {panes[$8]=1; next}
 {line=$0; gsub(/^[ \t]+/, "", line); n=split(line,a,/[ \t]+/); parent[a[1]]=a[2];
  command=a[3]; native_claude=(command ~ /\/claude\/versions\//); sub(/^.*\//,"",command); kind="";
  if(native_claude) kind="claude";
  if(command ~ /^(claude|codex|opencode|gemini|cursor-agent|copilot|droid|aider)$/) kind=command;
  if(command ~ /^(node|bun|python[0-9.]*)$/) {
   for(i=4;i<=n;i++) if(a[i] ~ /(^|\/)(claude|codex|opencode|gemini|cursor-agent|copilot|droid|aider)(\.[cm]?js)?$/) {
    kind=a[i]; sub(/^.*\//,"",kind); sub(/\.[cm]?js$/,"",kind); break
   }
  }
  if(kind!="") agents[a[1]]=kind
 }
 END {for(pid in agents) {p=pid; steps=0; while(p!="" && p!="0" && ++steps<100) {
  if(panes[p]) {if(!found[p]++) print p "\037" agents[pid]; break} p=parent[p]
 }}}' "$tmp/panes" "$tmp/ps" > "$tmp/processes"
# Cache resolved HEAD path: subsequent refreshes normally invoke no git.
awk -F "$us" '!seen[$7]++ {print $7}' "$tmp/panes" > "$tmp/paths"
: > "$tmp/branches"
while IFS='' read -r cwd; do
  [ -n "$cwd" ] || continue
  read -r key _ <<< "$(printf '%s' "$cwd" | cksum)"
  entry="$cache/branch-$key"
  head='' branch='' repo='' cached_cwd=''
  if [ -f "$entry" ]; then
    { IFS='' read -r cached_cwd; IFS='' read -r head; IFS='' read -r branch; IFS='' read -r repo; } < "$entry"
  fi
  if [ "$cached_cwd" != "$cwd" ] || [ -z "$head" ] || [ ! -e "$head" ] || [ "$head" -nt "$entry" ]; then
    info=$(git -C "$cwd" rev-parse --show-toplevel --git-path HEAD 2>/dev/null) || info=''
    repo=${info%%$'\n'*}; head=${info#*$'\n'}
    if [ -n "$info" ]; then
      case "$head" in /*) :;; *) head="$cwd/$head";; esac
      branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null) || branch='(detached)'
      printf '%s\n' "$cwd" "$head" "$branch" "$repo" > "$entry.$$"
      mv "$entry.$$" "$entry"
    else head='' repo='' branch=''; fi
  fi
  printf '%s\037%s\037%s\n' "$cwd" "$branch" "$repo" >> "$tmp/branches"
done < "$tmp/paths"
: > "$tmp/offline"
if [ "$all" = on ]; then
  git worktree list --porcelain 2>/dev/null | awk '
   /^worktree / {path=substr($0,10)} /^branch / {branch=substr($0,19); print path "\037" branch}
  ' > "$tmp/offline"
fi
: > "$tmp/known"
[ ! -f "$known_cache" ] || cat "$known_cache" > "$tmp/known"
now=$(date +%s)
jq -n --rawfile panes "$tmp/panes" --rawfile processes "$tmp/processes" \
 --rawfile branches "$tmp/branches" --rawfile offline "$tmp/offline" --rawfile known "$tmp/known" \
 --argjson now "$now" --arg idle_setting "${idle_setting:-30m}" --arg stale_setting "${stale_setting:-6h}" \
 --arg all "$all" --arg sort "$sort" --arg sf "$state_filter" --arg bf "$branch_filter" '
 def duration: capture("^(?<n>[0-9]+(?:\\.[0-9]+)?)(?<u>[smh]?)$") |
  (.n|tonumber) * (if .u=="h" then 3600 elif .u=="m" then 60 else 1 end);
 ($idle_setting|duration) as $idle | ($stale_setting|duration) as $stale |
 def lines: split("\n") | map(select(length>0)|split("\u001f"));
 def number: tonumber? // 0;
 ($known|split("\n")) as $known |
 ($processes|lines|map({key:.[0],value:.[1]})|from_entries) as $p |
 ($branches|lines|map({key:.[0],value:{branch:.[1],repo:.[2]}})|from_entries) as $b |
 ($panes|lines|map(
  {pane_id:.[0],session:.[1],session_id:.[2],window:.[3],window_id:.[4],pane_index:(.[5]|number),
   cwd:.[6],pid:.[7],command:.[8],agent:.[9],raw_state:.[10],state_ts:(.[11]|number),
   updated_ts:(.[12]|number),seen_ts:(.[13]|number),prompt:.[14],message:.[15],ask:.[16],
   tool:.[17],agent_session:.[18],children:(.[19]|number),model:.[20],context:.[21],
   dead:(.[22]=="1"),hook_ts:(.[23]|number),window_index:(.[24]|number),launch_ts:(.[25]|number)} |
  .updated_ts=([.updated_ts,.hook_ts,.state_ts]|max) |
  .branch=($b[.cwd].branch//"") | .repo=($b[.cwd].repo//"") |
  .alive=($p[.pid]!=null) |
  .raw_state=(if .agent!="" or .alive then .raw_state else "" end) |
  .agent=(if .agent!="" then .agent else $p[.pid]//"" end) |
  select(.agent!="" or .raw_state!="" or $all=="on") |
  .state=(if .raw_state!="" then .raw_state elif .alive then "unknown" else "shell" end) |
  .age=([$now-.state_ts,0]|max) |
  .starting=(.state=="unknown" and .launch_ts>0 and $now-.launch_ts<30) |
  (.pid) as $pid |
  (if .dead or (.alive==false and ($known|index($pid))!=null) or (.agent!="" and .alive==false and .state_ts>0 and .age>$stale) then .state="exited"
   elif .state=="done" and .age>$idle then .state="idle" else . end) |
  .unseen=(.state_ts>0 and .seen_ts<.state_ts) |
  .resumable=(.state=="exited" and .agent_session!="") |
  .location=(.session+":"+(.window_index|tostring)+"."+(.pane_index|tostring))
 )) as $live |
 ($live + (if $all=="on" then ($offline|lines|map(. as $w |
  select([$live[]|select(.cwd==$w[0])]|length==0) |
  {pane_id:("worktree:"+.[1]),branch:.[1],cwd:.[0],repo:"",agent:"worktree",state:"offline",
   raw_state:"offline",state_ts:0,age:0,unseen:false,alive:false,resumable:false,
   session:"",window:"",location:"offline worktree",prompt:"",message:"",ask:"",tool:""})) else [] end)) |
 map(select(($sf=="" or .state==$sf) and ($bf=="" or .branch==$bf)) |
  .rank=(if .state=="waiting" then 0 elif .state=="error" then 1 elif .state=="working" then 2
   elif .state=="done" and .unseen then 3 elif .state=="done" or .state=="idle" or .state=="stopped" then 4
   elif .state=="exited" then 5 elif .state=="unknown" then 6 else 7 end) |
  .sortkey=([.rank,(if .state=="waiting" then .state_ts else -.state_ts end)])) |
 sort_by(if $sort=="recent" then [-.state_ts] elif $sort=="age" then [.state_ts] else .sortkey end)
 ' > "$tmp/json" || exit 1
# Remember a detected live process until its pane disappears, so a surviving
# shell becomes exited immediately once its agent has actually been observed.
awk -F "$us" 'NR==FNR {panes[$8]=1; next} {if(panes[$1]) seen[$1]=1} END {for(pid in seen) print pid}' \
 "$tmp/panes" "$tmp/known" "$tmp/processes" > "$known_cache.$$"
mv "$known_cache.$$" "$known_cache"
case "$mode" in
 json) cat "$tmp/json";;
 counts) jq -r '[([.[]|select(.state=="waiting")]|length),([.[]|select(.state=="error")]|length),
  ([.[]|select(.state=="working")]|length),([.[]|select(.state=="done" and .unseen)]|length),
  ([.[]|select(.state=="done")]|length),([.[]|select(.state=="idle")]|length),
  ([.[]|select(.state=="exited")]|length),([.[]|select(.state=="unknown")]|length)]|join(" ")' "$tmp/json";;
 rows|table)
  BONSAI_GLYPHS=${glyph_setting:-unicode}
  export BONSAI_GLYPHS
  glyphs=$(for state in waiting working 'done' idle error stopped exited unknown; do printf '%s\037' "$state"; bonsai_glyph "$state"; printf '\n'; done)
  jq -r --arg glyphs "$glyphs" --arg mode "$mode" --arg compact "$compact" '
   def glyph: .state as $s | ($glyphs|split("\n")|map(split("\u001f")|{key:.[0],value:.[1]})|from_entries)[$s]//"·";
   def pad($width): . + (" " * ([$width-length,1]|max));
   def colour: if .state=="waiting" then "\u001b[33m" elif .state=="error" then "\u001b[31m"
    elif .state=="working" then "\u001b[36m" elif .state=="done" and .unseen then "\u001b[1;32m" else "\u001b[0m" end;
   def age: if .state_ts==0 then "—" elif .age<60 then "\(.age)s" elif .age<3600 then "\((.age/60)|floor)m"
    elif .age<86400 then "\((.age/3600)|floor)h" else "\((.age/86400)|floor)d" end;
   def preview: if .starting then "starting…" elif .state=="waiting" and .ask!="" then .ask elif .state=="working" and .tool!="" then "Using "+.tool
    elif .state=="working" and .prompt!="" then "You: "+.prompt elif .message!="" then .message
    elif .resumable then "exited · resumable" elif .state=="unknown" then "no hooks — run Setup" else .state end;
   .[] | if $mode=="rows" then [.pane_id,(.sortkey|tojson),((colour)+(((glyph)+" "+age)|pad(8))+"\u001b[0m"),(.agent|pad(10)),
    ((if $compact=="on" then .branch[-14:] else .branch end)|pad(16)),(.location|pad(14)),
    ((colour)+preview+(if $compact=="on" and (.branch|length)>14 then " · "+.branch else "" end)+"\u001b[0m"),(.unseen|tostring)]|join("\u001f")
   else [(glyph),age,.agent,.branch,.location,preview]|join("  ") end' "$tmp/json";;
esac
