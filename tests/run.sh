#!/bin/sh
set -eu
exec zsh "$(dirname "$0")/local-history.zsh"
