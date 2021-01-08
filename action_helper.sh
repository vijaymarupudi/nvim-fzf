#!/bin/sh

#1 directory to cd to
#2 registry id of the function to run
#3.. the fzf choices
cd "$1"
nvim --headless --clean --cmd "luafile ./action_helper.lua" "$@"
