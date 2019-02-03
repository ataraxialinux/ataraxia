#!/bin/bash

if [ "$(id -gn)" = "$(id -un)" -a $EUID -gt 99 ] ; then
	umask 002
else
	umask 022
fi

alias ls='ls --color=auto'
alias grep='grep --color=auto'

if [ -z "$INPUTRC" -a ! -f "$HOME/.inputrc" ] ; then
	export INPUTRC=/etc/inputrc
fi

NORMAL="\[\e[0m\]"
RED="\[\e[1;31m\]"
GREEN="\[\e[1;32m\]"

if [[ $EUID == 0 ]] ; then
	export PS1="$RED\u [ $NORMAL\w$RED ]# $NORMAL"
else
	export PS1="$GREEN\u [ $NORMAL\w$GREEN ]\$ $NORMAL"
fi
