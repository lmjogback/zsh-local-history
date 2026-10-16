# zsh-local-history: zsh-history-substring-search widgets that search only
# the local history: what this shell read at startup and the commands it ran,
# not lines other shells added later through SHARE_HISTORY.
#
# zle's set-local-history makes up-history and its relatives skip those
# foreign lines, but history-substring-search searches the $history
# parameter, which includes them. fc -L lists only local events, but fc
# cannot run inside zle, so the entries added since the last prompt are
# classified before each prompt. Shared history is only imported when a
# command line is added, so the classification is complete while a line is
# edited.

typeset -gA _local_history_foreign      # history numbers of foreign entries
typeset -gi _local_history_checked=-1   # entries up to here are classified
typeset -gi _local_history_mode=0       # 1 while a local widget runs
typeset -gi _local_history_last_mode=0  # mode of the current search

_local_history_precmd() {
  emulate -L zsh
  # History read at startup is local; nothing has been imported yet.
  if (( _local_history_checked < 0 )); then
    _local_history_checked=HISTCMD-1
    return
  fi
  # Start at the last classified number: with HIST_IGNORE_SPACE, the next
  # command line replaces the last entry and reuses its number.
  local -i n
  for (( n = _local_history_checked > 1 ? _local_history_checked : 1; n < HISTCMD; n++ )); do
    if (( $+history[$n] )) && ! fc -lL $n $n >/dev/null 2>&1; then
      _local_history_foreign[$n]=1
    else
      unset "_local_history_foreign[$n]"
    fi
  done
  _local_history_checked=HISTCMD-1
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _local_history_precmd

# Replaces _history-substring-search-begin, which starts or continues a
# search and collects the raw matches from $history.
_local_history_begin() {
  # Switching between local and global search in the middle of a search
  # starts a new search with the same query.
  if (( _local_history_mode != _local_history_last_mode )) &&
     [[ -n $_history_substring_search_query &&
        $BUFFER == ${_history_substring_search_result-} ]]; then
    BUFFER=$_history_substring_search_query
    _history_substring_search_result=
  fi
  _local_history_last_mode=_local_history_mode
  _local_history_orig_begin "$@" || return
  # A new search has processed no raw matches yet.
  if (( _local_history_mode && _history_substring_search_raw_match_index == 0 )); then
    local -a foreign=( ${(k)_local_history_foreign} )
    _history_substring_search_raw_matches=( ${_history_substring_search_raw_matches:|foreign} )
  fi
}

# Install _local_history_begin, again if history-substring-search has been
# sourced again since.
_local_history_wrap() {
  [[ $functions[_history-substring-search-begin] == $functions[_local_history_begin] ]] && return
  (( $+functions[_history-substring-search-begin] )) || return 1
  functions -c _history-substring-search-begin _local_history_orig_begin
  functions -c _local_history_begin _history-substring-search-begin
}

_local_history_widget() {
  if ! _local_history_wrap; then
    zle -M 'zsh-local-history: zsh-history-substring-search is not loaded'
    return 1
  fi
  _local_history_mode=1
  zle .set-local-history -n 1
  {
    zle $1 -- "${@:2}"
  } always {
    zle .set-local-history -n 0
    _local_history_mode=0
  }
}

local-history-substring-search-up()   { _local_history_widget history-substring-search-up "$@" }
local-history-substring-search-down() { _local_history_widget history-substring-search-down "$@" }
zle -N local-history-substring-search-up
zle -N local-history-substring-search-down

# Without history-substring-search yet, the first widget call installs it.
_local_history_wrap || :
