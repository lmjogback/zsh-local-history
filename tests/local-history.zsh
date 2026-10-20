#!/usr/bin/env zsh

# Drives interactive shells in a pseudo-terminal. Each shell shares a history
# file with SHARE_HISTORY; lines appended to the file from outside stand in
# for other shells and are imported, as foreign, when the next command line
# is added.

set -eu
zmodload zsh/zpty zsh/datetime

hss=${HSS_PLUGIN:-}
if [[ ! -r $hss ]]; then
  print -u2 -- 'Set HSS_PLUGIN to the path of zsh-history-substring-search.zsh.'
  exit 2
fi
# Optional: zsh-autosuggestions.zsh, for the tests that load it.
zsa=${ZSA_PLUGIN:-}
plugin=${0:A:h:h}/zsh-local-history.plugin.zsh

tmp=$(mktemp -d)
trap 'zpty -d 2>/dev/null; rm -rf -- $tmp' EXIT

typeset -gi tests=0 failed=0
typeset -g output suggestion

# Start a shell in a directory named $1. $2 lists what its .zshrc sources,
# in order: plugin, hss and zsa, separated by commas.
start() {
  local dir=$tmp/$1 f
  mkdir -p $dir
  printf ': 1:0;%s\n' 'echo old-alpha' 'echo old-beta' >$dir/history
  : >$dir/prompts >$dir/buffers
  {
    print -r -- "HISTFILE=${(q)dir}/history HISTSIZE=1000 SAVEHIST=1000"
    print -r -- 'setopt SHARE_HISTORY EXTENDED_HISTORY HIST_IGNORE_SPACE'
    print -r -- 'setopt HIST_IGNORE_DUPS HIST_FIND_NO_DUPS'
    print -r -- "PS1='> ' RPS1="
    print -r -- 'bindkey -e'
    for f in ${(s:,:)2}; do
      case $f in
        plugin) print -r -- "source ${(q)plugin}" ;;
        hss)    print -r -- "source ${(q)hss}" ;;
        # Synchronous, so a suggestion is in place when the buffer is dumped.
        zsa)    print -r -- "source ${(q)zsa}; unset ZSH_AUTOSUGGEST_USE_ASYNC" ;;
      esac
    done
    # After the plugin's hook, so a prompt means classification is done.
    print -r -- "_test_prompt() { print p >>${(q)dir}/prompts }"
    print -r -- 'precmd_functions+=(_test_prompt)'
    print -r -- "_test_dump() { print -r -- \"|\$BUFFER|\$POSTDISPLAY\" >>${(q)dir}/buffers }"
    print -r -- 'zle -N _test_dump; bindkey "^Xp" _test_dump'
    # zsh-autosuggestions would clear the suggestion before the dump.
    print -r -- 'ZSH_AUTOSUGGEST_IGNORE_WIDGETS+=(_test_dump)'
    print -r -- 'bindkey "^Xu" local-history-substring-search-up'
    print -r -- 'bindkey "^Xd" local-history-substring-search-down'
    print -r -- 'bindkey "^XU" history-substring-search-up'
    print -r -- 'bindkey "^XD" history-substring-search-down'
  } >$dir/.zshrc
  zpty -d 2>/dev/null || :
  output=
  # Skip /etc/zsh/zshrc and the like; on Ubuntu it runs compinit, which
  # can stop at a prompt about insecure directories.
  zpty s "env -u HISTFILE ZDOTDIR=${(q)dir} TERM=xterm zsh -o no_global_rcs -i"
  shell=$dir
  wait_lines $dir/prompts 1
}

drain() {
  local chunk
  while zpty -rt s chunk 2>/dev/null; do output+=$chunk; done
}

# Set REPLY to the number of lines in a file.
count() {
  local -a lines=( ${(f)"$(<$1)"} )
  REPLY=$#lines
}

wait_lines() {
  local file=$1 n=$2 deadline=$(( EPOCHREALTIME + 5 ))
  while count $file; (( REPLY < n )); do
    drain
    if (( EPOCHREALTIME > deadline )); then
      print -u2 -- "timeout waiting for $file to have $n lines; output:"
      print -u2 -r -- $output
      exit 1
    fi
    sleep 0.02
  done
  drain
}

# Run a command line on a new line and wait for the next prompt.
run() {
  new_line
  count $shell/prompts
  zpty -w s $1
  wait_lines $shell/prompts $(( REPLY + 1 ))
}

# What another shell does: append a line to the history file.
foreign() {
  print -r -- ": $EPOCHSECONDS:0;$1" >>$shell/history
}

# Send keys, then return the buffer in REPLY and the suggestion after it in
# $suggestion. The tests' buffers contain no |.
keys() {
  count $shell/buffers
  zpty -w -n s "$1"$'\C-Xp'
  wait_lines $shell/buffers $(( REPLY + 1 ))
  local -a lines=( ${(f)"$(<$shell/buffers)"} )
  local -a fields=( "${(@s:|:)lines[-1]}" )
  REPLY=$fields[2] suggestion=$fields[3]
}

check() {
  local name=$1 keys=$2 expected=$3
  keys $keys
  (( ++tests ))
  if [[ $REPLY != $expected ]]; then
    print -u2 -- "FAIL: $name: expected ${(qq)expected}, got ${(qq)REPLY}"
    (( ++failed ))
  fi
}

# Abort the command line with send-break and wait for the next prompt, so
# each check starts with an empty line and no search in progress.
new_line() {
  count $shell/prompts
  zpty -w -n s $'\C-G'
  wait_lines $shell/prompts $(( REPLY + 1 ))
}

up=$'\C-Xu' down=$'\C-Xd' gup=$'\C-XU' gdown=$'\C-XD'

# History: old-alpha old-beta (read at startup), alpha-local, alpha-foreign
# (from another shell), beta-local.
setup() {
  run 'echo alpha-local'
  foreign 'echo alpha-foreign'
  run 'echo beta-local'
}

start default hss,plugin
setup

new_line
check 'local search skips foreign lines' "alpha$up" 'echo alpha-local'
check 'local search reaches startup history' "$up" 'echo old-alpha'
check 'local search ends with the query' "$up" 'alpha'
new_line
check 'local search goes back down' "alph$up$up$down" 'echo alpha-local'

new_line
check 'global search includes foreign lines' "alpha$gup" 'echo alpha-foreign'
check 'global search continues' "$gup" 'echo alpha-local'
check 'global search goes back down' "$gdown" 'echo alpha-foreign'

new_line
check 'local then global restarts with the query' "alpha$up$gup" 'echo alpha-foreign'
check 'global then local restarts with the query' "$up" 'echo alpha-local'
new_line
check 'repeated global after local continues' "alpha$up$gup$gup" 'echo alpha-local'

new_line
check 'empty line: local browsing skips foreign lines' "$up$up" 'echo alpha-local'
check 'empty line: local browsing reaches startup history' "$up" 'echo old-beta'
new_line
check 'empty line: global browsing includes foreign lines' "$gup$gup" 'echo alpha-foreign'

# HIST_IGNORE_SPACE: the next command line replaces the hidden entry.
run ' echo gamma-hidden'
foreign 'echo gamma-foreign'
run 'echo gamma-local'
new_line
check 'hidden entry replaced: local' "gamma$up" 'echo gamma-local'
check 'hidden entry replaced: no more local matches' "$up" 'gamma'
new_line
check 'hidden entry replaced: global' "gamma$gup$gup" 'echo gamma-foreign'
run 'echo delta-local'
new_line
check 'later commands stay local' "delta$up" 'echo delta-local'
new_line
check 'earlier classification survives' "gamma$up$up" 'gamma'

# The plugin can be loaded before history-substring-search.
start before plugin,hss
setup
new_line
check 'loaded first: local search' "alpha$up" 'echo alpha-local'
new_line
check 'loaded first: global search' "alpha$gup" 'echo alpha-foreign'

# Without history-substring-search, the widgets report it.
start missing plugin
keys "alpha$up"
drain
(( ++tests ))
if [[ $REPLY != alpha || $output != *'zsh-history-substring-search is not loaded'* ]]; then
  print -u2 -- "FAIL: missing history-substring-search is reported (buffer ${(qq)REPLY})"
  (( ++failed ))
fi

# zsh-autosuggestions clears its suggestion after a local search, as it does
# after history-substring-search, whether it is loaded before or after. It
# does not suggest while more input is pending, so each argument after the
# expected buffer and suggestion is sent on its own, as if typed.
check_suggestion() {
  local name=$1 expected=$2 expected_suggestion=$3 chunk
  for chunk in "${@:4}"; do
    zpty -w -n s "$chunk"
    sleep 0.2
  done
  keys ''
  (( ++tests ))
  if [[ $REPLY != $expected || $suggestion != $expected_suggestion ]]; then
    print -u2 -- "FAIL: $name: expected ${(qq)expected} + ${(qq)expected_suggestion}," \
      "got ${(qq)REPLY} + ${(qq)suggestion}"
    (( ++failed ))
  fi
}

if [[ -r $zsa ]]; then
  for order in zsa,hss,plugin hss,plugin,zsa; do
    start ${order//,/-} $order
    run 'echo status'
    run 'echo status --short'
    new_line
    check_suggestion "$order: suggestion while typing" 'echo st' 'atus --short' 'echo st'
    new_line
    check_suggestion "$order: no suggestion after local search" 'echo status' '' \
      'echo st' $up $up
    new_line
    check_suggestion "$order: no suggestion after global search" 'echo status' '' \
      'echo st' $gup $gup
  done
else
  print -u2 -- 'Skipping zsh-autosuggestions tests: ZSA_PLUGIN is not set.'
fi

print -- "$tests tests, $failed failed"
(( failed == 0 ))
