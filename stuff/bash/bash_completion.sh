if [ -f /usr/share/bash-completion/bash_completion ]; then
	if [ -n "${BASH_VERSION-}" -a -n "${PS1-}" -a -z "${BASH_COMPLETION_VERSINFO-}" ]; then
		if [ ${BASH_VERSINFO[0]} -gt 4 ] || \
			[ ${BASH_VERSINFO[0]} -eq 4 -a ${BASH_VERSINFO[1]} -ge 1 ]; then
			[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/bash_completion" ] && \
				. "${XDG_CONFIG_HOME:-$HOME/.config}/bash_completion"
			if shopt -q progcomp && [ -r /usr/share/bash-completion/bash_completion ]; then
				. /usr/share/bash-completion/bash_completion
			fi
		fi
	fi
else
	if shopt -q progcomp; then
		for script in /etc/bash_completion.d/* ; do
			if [ -r $script ] ; then
				. $script
			fi
		done
	fi
fi
