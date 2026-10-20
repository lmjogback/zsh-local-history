# zsh-local-history

Local history search for
[zsh-history-substring-search](https://github.com/zsh-users/zsh-history-substring-search).

With `SHARE_HISTORY`, every shell sees the commands other shells run as soon
as they are added. That is useful for finding something you ran elsewhere,
but it means Up recalls commands from other windows, not the one you are in.
This plugin adds two widgets that search only the local history, so Up and
Down can stay in the current shell while another key searches everything:

| Widget | Searches |
|---|---|
| `local-history-substring-search-up` | Local history, backwards |
| `local-history-substring-search-down` | Local history, forwards |
| `history-substring-search-up` | All history (from zsh-history-substring-search) |
| `history-substring-search-down` | All history (from zsh-history-substring-search) |

The idea comes from [zsh4humans](https://github.com/romkatv/zsh4humans).

## What "local" means

Local history is what Zsh itself calls local (`fc -L`, `set-local-history`):
everything the shell read from `$HISTFILE` at startup, plus the commands run
in this shell. Lines that other shells add later, and that `SHARE_HISTORY`
imports, are foreign. A new shell therefore starts with the full history; it
just stops seeing what the others do after that.

Without `SHARE_HISTORY` nothing is imported, and local and global search are
the same.

## Installation

Requires Zsh 5.8 or newer (tested with 5.9) and
zsh-history-substring-search. Load this plugin from `.zshrc`, not later (see
[Limitations](#limitations)), before or after zsh-history-substring-search.
With zinit:

```zsh
zinit light zsh-users/zsh-history-substring-search
zinit light lmjogback/zsh-local-history
```

Or source `zsh-local-history.plugin.zsh` directly.

The plugin binds no keys. For example, local search on Up and Down and global
search on Ctrl+Up and Ctrl+Down:

```zsh
bindkey '^[[A'    local-history-substring-search-up
bindkey '^[[B'    local-history-substring-search-down
bindkey '^[[1;5A' history-substring-search-up
bindkey '^[[1;5B' history-substring-search-down
```

Terminals in application cursor mode send `^[OA` and `^[OB` for Up and Down;
bind those too, or use `$terminfo[kcuu1]` and `$terminfo[kcud1]`.

On macOS, Ctrl+Up and Ctrl+Down open Mission Control and App Exposé by
default. Turn those shortcuts off in System Settings → Keyboard → Keyboard
Shortcuts → Mission Control, or the terminal never receives the keys.

## Behavior

- On an empty line, the local widgets browse the history like Up and Down
  do, skipping foreign lines.
- With text on the line, they search for it like zsh-history-substring-search,
  with its settings (`HISTORY_SUBSTRING_SEARCH_*`) and highlighting, among
  local lines only.
- Switching between local and global search in the middle of a search starts
  a new search for the same text, from the most recent match.

If zsh-history-substring-search is not loaded, the local widgets show a
message and do nothing.

With [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions),
the local widgets clear the suggestion like zsh-history-substring-search's
own widgets do: the plugin adds them to `ZSH_AUTOSUGGEST_CLEAR_WIDGETS`,
whether zsh-autosuggestions is loaded before or after it.

## How it works

zsh-history-substring-search finds matches in the `$history` parameter,
which includes foreign lines, so `set-local-history` alone does not make its
search local. `fc -L` can tell local from foreign lines, but `fc` cannot run
inside the line editor. Before each prompt, the plugin therefore runs `fc -L`
on each history entry added since the previous prompt and remembers the
foreign ones. `SHARE_HISTORY` imports lines only when a command line is
added, so that list is complete while you edit. A local search removes the
foreign entries from zsh-history-substring-search's matches, and turns on
`set-local-history` for browsing on an empty line.

The plugin replaces zsh-history-substring-search's internal function
`_history-substring-search-begin` with a wrapper. If a new version of
zsh-history-substring-search renames it or changes how it collects matches,
the local widgets may stop working; the tests run against its current
`master`.

## Limitations

- History read at startup counts as local without being checked. If the
  plugin is loaded after the first prompt (e.g. with zinit's `wait`, or by
  sourcing it by hand), lines other shells added before that are treated as
  local too.
- If you type exactly the text of a search that ran out of matches, on a
  later line, zsh-history-substring-search continues that search instead of
  starting over, and finds nothing. That happens with its own widgets too.

## Tests

```sh
HSS_PLUGIN=/path/to/zsh-history-substring-search.zsh \
ZSA_PLUGIN=/path/to/zsh-autosuggestions.zsh ./tests/run.sh
```

`ZSA_PLUGIN` is optional; without it, the zsh-autosuggestions tests are
skipped.

The tests drive interactive shells in a pseudo-terminal (`zsh/zpty`), with a
temporary history file that the test appends to as another shell would.

## License

MIT. See [LICENSE](LICENSE).
