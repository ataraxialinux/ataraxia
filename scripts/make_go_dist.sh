#!/bin/sh
#
# Simple script to build Go binaries
#
# Copyright 2019 protonesso <nagakamira@gmail.com>
#

GOVER=1.12.4
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
		aarch64)
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
		mips64)
			export GOARCH="mips64"
			export GOMIPS64=softfloat
			;;
		mips64el)
			export GOARCH="mips64le"
			export GOMIPS64=softfloat
			;;
		mips)
			export GOARCH="mips"
			export GOMIPS=softfloat
			;;
		mipsel)
			export GOARCH="mipsle"
			export GOMIPS=softfloat
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
	rm -rf go*
	curl -C - -L -O $GOURL
	tar -xvf $GOTAR
}

build_go() {
	msg "Building Go for '"$BARCH"' platform"
	cd $SRC/go/src

	case $BARCH in
		armv7l|armv5tel)
			GOOS=linux GOARCH=$GOARCH GOARM=$GOARM ./bootstrap.bash
			;;
		mips64|mips64el)
			GOOS=linux GOARCH=$GOARCH GOMIPS64=$GOMIPS64 ./bootstrap.bash
			;;
		mips|mipsel)
			GOOS=linux GOARCH=$GOARCH GOMIPS=$GOMIPS ./bootstrap.bash
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

