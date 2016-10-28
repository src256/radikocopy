#!/bin/sh
export ANYENV_ROOT="$HOME/.anyenv"
if [ -d "$ANYENV_ROOT" ]; then
    export PATH="$HOME/.anyenv/bin:/usr/local/bin:$PATH"
    eval "$(anyenv init -)"
fi
cd `dirname $0`
echo "########################################################"
radicocopy "$@"


