#!/bin/bash
# Multi-line status line, read entirely from the session transcript (no saved state):
#   [name] · model · context % · cost
#   Started: first prompt the user typed; when too long for one row, a Haiku
#            summary (italic), generated once in the background and cached in $TMPDIR
#   Now:     latest prompt the user typed (omitted when same as Started)
#   Doing:   current step from the transcript tail, with elapsed time
input=$(cat)
name=$(jq -r '.session_name // empty' <<<"$input")
model=$(jq -r '.model.display_name // empty' <<<"$input")
pct=$(jq -r '.context_window.used_percentage // 0' <<<"$input" | cut -d. -f1)
cost=$(jq -r '.cost.total_cost_usd // 0' <<<"$input")
transcript=$(jq -r '.transcript_path // empty' <<<"$input")
sid=$(jq -r '.session_id // empty' <<<"$input")

# Prompts the user typed: human-origin messages (prefiltered with perl, which is
# ~10x faster than macOS grep on large transcripts). Skill calls are stored as
# <command-name>/x</command-name><command-args>...</command-args> tags; these are
# unwrapped to "/x ..." wherever they appear. Dropped: injected tags, settings
# commands (/rename, /model...) and pure acknowledgements ("yes", "ok go ahead").
ACK='^[[:space:]]*(y|ya|yes|yep|yeah|yup|ok|okay|k|sure|go|go ahead|go for it|do it|done|continue|proceed|next|thanks|thank you|thx|ty|lgtm|sgtm|sounds good|looks good|perfect|great|nice|cool|good|approved|agreed|right|correct|no|nope|stop|wait|try again|retry|again)([[:space:].!,]+(y|ya|yes|yep|yeah|yup|ok|okay|k|sure|go|go ahead|go for it|do it|done|continue|proceed|next|thanks|thank you|thx|ty|lgtm|sgtm|sounds good|looks good|perfect|great|nice|cool|good|approved|agreed|right|correct|no|nope|stop|wait|try again|retry|again))*[[:space:].!,]*$'
SETTINGS_CMDS='^/(rename|model|effort|theme|resume|add-dir|output-style|config|permissions|login|logout|exit|clear|compact|fast|vim|color|statusline)( |$)'
human_prompts() {
  perl -ne 'print if index($_, q("kind":"human")) >= 0' "$transcript" 2>/dev/null | jq -r --arg ack "$ACK" --arg cmds "$SETTINGS_CMDS" '
    select(.type=="user" and .origin.kind=="human")
    | (.message.content // "") | if type=="string" then . elif type=="array" then (map(select(.type=="text").text) | join(" ")) else "" end
    | gsub("<command-message>[^<]*</command-message>"; "")
    | gsub("<command-name>(?<n>[^<]*)</command-name>\\s*(<command-args>(?<a>[\\s\\S]*?)</command-args>)?"; "\(.n) \(.a // "")")
    | gsub("\n"; " ") | gsub("^\\s+|\\s+$"; "")
    | select(. != "") | select(startswith("<") | not)
    | select(test($cmds) | not) | select(test($ack; "i") | not)' 2>/dev/null
}

# Doing: the last turn-relevant entry in the transcript tail.
doing_line() {
  tail -n 80 "$transcript" 2>/dev/null | jq -rs '
    def tool_label: .name as $t | (.input // {}) as $i |
      if $t=="Bash" then ($i.description // $i.command)
      elif ($t=="Read" or $t=="Edit" or $t=="Write" or $t=="NotebookEdit") then "\($t) \($i.file_path // $i.notebook_path // "" | split("/") | last)"
      elif ($t=="Grep" or $t=="Glob") then "Search \($i.pattern)"
      elif $t=="WebSearch" then "Web search: \($i.query)"
      elif $t=="WebFetch" then "Fetch \($i.url)"
      elif ($t=="Agent" or $t=="Task") then "Subagent: \($i.description // "")"
      elif $t=="TodoWrite" then "Update task list"
      else ($i.description // ($t | sub("^mcp__"; "") | gsub("__"; ": ")))
      end;
    def epoch: (.timestamp // "") | sub("\\.[0-9]+Z$"; "Z") | (try fromdateiso8601 catch 0);
    [ .[] | select(.type=="assistant"
                   or (.type=="user" and (.isMeta | not))
                   or (.type=="system" and .subtype=="turn_duration")) ] | last
    | if . == null then empty
      elif .type=="system" then "Waiting for you\t\(epoch)"
      elif .type=="assistant" then
        ([.message.content[]? | select(.type=="tool_use")] | last) as $tu
        | if .message.stop_reason=="end_turn" then "Waiting for you\t\(epoch)"
          elif $tu then "\($tu | tool_label | gsub("\n"; " "))\t\(epoch)"
          else "Thinking\t\(epoch)" end
      else
        (.message.content | if type=="string" then . else ([.[]? | select(.type=="text").text] | join(" ")) end) as $txt
        | if ($txt | startswith("[Request interrupted")) then "Waiting for you\t\(epoch)"
          else "Thinking\t\(epoch)" end
      end' 2>/dev/null
}

started=""; now=""; doing=""; since=""
if [ -f "$transcript" ]; then
  prompts=$(human_prompts)
  started=$(head -1 <<<"$prompts")
  now=$(tail -1 <<<"$prompts")
  IFS=$'\t' read -r doing since <<<"$(doing_line)"
fi

max=110

# Long Started: show a cached Haiku summary; if none yet, start one in the background
# (detached via setsid so it survives this script being cancelled) and show the
# truncated text meanwhile. A lock prevents duplicate calls; retried after 5 min.
started_display=$(perl -pe 's/<pasted_content[^>]*>.*?<\/pasted_content>/[pasted text]/gs' <<<"$started")
summary=""
if [ ${#started_display} -gt $max ] && [ -n "$sid" ]; then
  cache="${TMPDIR:-/tmp}/claude-statusline"; mkdir -p "$cache"
  sfile="$cache/$sid.summary"; lock="$cache/$sid.lock"
  if [ -s "$sfile" ]; then
    summary=$(cat "$sfile")
  elif [ ! -f "$lock" ] || [ $(( $(date +%s) - $(stat -f %m "$lock") )) -gt 300 ]; then
    touch "$lock"
    claude_bin=$(command -v claude || echo "$HOME/.local/bin/claude")
    printf '%s' "$started" > "$cache/$sid.input"
    ( cd "$cache" && perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' sh -c '
        "$0" -p --model haiku --no-session-persistence --tools "" --strict-mcp-config --setting-sources "" \
          --system-prompt "Summarize the user request to a coding agent in one line of at most 90 characters. Describe the task, not any pasted content. Output only the summary." \
          < "$1.input" 2>/dev/null | tr "\n" " " | sed "s/ *$//" > "$1.summary.tmp" \
        && [ -s "$1.summary.tmp" ] && mv "$1.summary.tmp" "$1.summary"
        rm -f "$1.input" "$1.summary.tmp"' "$claude_bin" "$cache/$sid" >/dev/null 2>&1 & )
  fi
fi
trim() { local s="$1"; [ ${#s} -gt $max ] && s="${s:0:$((max-1))}…"; printf '%s' "$s"; }

head="${model:+\033[2m$model\033[0m · }${pct}% ctx · \$$(printf '%.2f' "$cost")"
[ -n "$name" ] && head="\033[1;36m[$name]\033[0m · $head"
printf '%b\n' "$head"
if [ -n "$summary" ]; then printf '%b%s%b\n' "\033[33mStarted:\033[0m \033[3m" "$(trim "$summary")" "\033[0m"
elif [ -n "$started" ]; then printf '%b%s\n' "\033[33mStarted:\033[0m " "$(trim "$started_display")"; fi
[ -n "$now" ] && [ "$now" != "$started" ] && printf '%b%s\n' "\033[32mNow:\033[0m     " "$(trim "$now")"
if [ -n "$doing" ]; then
  el=$(( $(date +%s) - ${since:-0} ))
  if [ "$el" -lt 0 ] || [ "$el" -gt 864000 ]; then ago=""
  elif [ "$el" -lt 60 ]; then ago=" (${el}s)"
  elif [ "$el" -lt 3600 ]; then ago=" ($((el/60))m)"
  else ago=" ($((el/3600))h $((el%3600/60))m)"; fi
  printf '%b%s\n' "\033[35mDoing:\033[0m   " "$(trim "$doing")$ago"
fi
exit 0
