#!/bin/bash
#
# Simple script to build Go binaries
#
# Copyright 2019 protonesso <nagakamira@gmail.com>
#

GOVER=1.11.4
GOTAR="go$GOVER.src.tar.gz"
GOURL="https://dl.google.com/go/$GOTAR"
BARCH="$1"

set -e

msg() {
	local msg=$(echo $1 | tr -s / /)
	printf "\e[1m\e[32m==>\e[0m $msg\n"
}

die() {
	local msg=$(echo $1 | tr -s / /)
	printf "\e[1m\e[31m==!\e[0m $msg\n"
	exit 1
}

setup_architecture() {
	case $BARCH in
		x86_64)
			export GOARCH="amd64"
			;;
		x86)
			export GOARCH="386"
			;;
		arm64)
			export GOARCH="arm64"
			;;
		armv7l)
			export GOARCH="arm"
			export GOARM="7"
			;;
		armv5tel)
			export GOARCH="arm"
			export GOARM="5"
			;;
		ppc64le)
			export GOARCH="ppc64le"
			;;
		ppc64)
			export GOARCH="ppc64"
			;;
		*)
			die "Architecture is not set or is not supported by 'bootstrap' script"
	esac

	msg "Using configuration for '"$BARCH"' platform"

	export BUILD="$(pwd)/OUT.$BARCH"
	export SRC="$BUILD/sources"

	mkdir -p $SRC
}

get_go_src() {
	msg "Getting Go sources"

	cd $SRC
	curl -C - -L -O $GOURL
	rm -rf go
	tar -xvf $GOTAR
}

build_go() {
	msg "Building Go for '"$BARCH"' platform"
	cd $SRC/go/src

	case $BARCH in
		armv7l|armv5tel)
			GOOS=linux GOARCH=$GOARCH GOARM=$GOARM ./bootstrap.bash
			;;
		*)
			GOOS=linux GOARCH=$GOARCH ./bootstrap.bash
	esac

	msg "Finished building Go for '"$BARCH"' platform"
}

setup_architecture
get_go_src
build_go

exit 0

