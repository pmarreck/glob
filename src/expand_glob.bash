#!/usr/bin/env bash

# Expand one pattern without depending on Bash's optional programmable-completion
# builtins. The subshell keeps `set` and `shopt` changes out of the caller.
expand_glob() {
	(
		set +f
		shopt -s nullglob
		local option
		for option in ${2:-}; do
			shopt -s "$option"
		done
		local IFS=
		# Intentional: unquoted expansion is the Bash pathname-expansion engine.
		# shellcheck disable=SC2206
		local matches=( $1 )
		(( ${#matches[@]} )) && printf '%s\n' "${matches[@]}"
	)
}
