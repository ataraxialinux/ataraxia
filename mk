#!/bin/sh

set -e

usage() {
	cat <<EOF
mk - the JanusLinux build tool.

Usage: sudo BARCH=[supported architecture] ./mk [one of following option]

	clean		Clean from previous build
	toolchain	Build a cross-toolchain
	image		Build a bootable *.iso image
	container	Build a docker container
	all		Build a full JanusLinux system

EOF
	exit 0
}

case "$1" in
	something)
		something
		;;
	usage|*)
		usage
esac

exit 0

