#!/bin/sh
#
# Simple script to build Rust binaries
#
# Copyright 2019 protonesso <nagakamira@gmail.com>
#

RUSTVER=1.34.0
RUSTTAR="rustc-$RUSTVER-src.tar.gz"
RUSTURL="https://static.rust-lang.org/dist/$RUSTTAR"
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
			export TRIPLET="x86_64-unknown-linux-musl"
			;;
		aarch64)
			export TRIPLET="aarch64-unknown-linux-musl"
			;;
		armv7l)
			export TRIPLET="armv7-unknown-linux-musleabihf"
			;;
		ppc64le)
			export TRIPLET="powerpc64le-unknown-linux-musl"
			;;
		ppc64)
			export TRIPLET="powerpc64-unknown-linux-musl"
			;;
		ppc)
			export TRIPLET="powerpc-unknown-linux-musl"
			;;
		mips)
			export TRIPLET="mips-unknown-linux-musl"
			;;
		mipsel)
			export TRIPLET="mipsel-unknown-linux-musl"
			;;
		*)
			die "Architecture is not set or is not supported by 'bootstrap' script"
	esac

	msg "Using configuration for '"$BARCH"' platform"

	export BUILD="$(pwd)/OUT.$BARCH"
	export SRC="$BUILD/sources"

	mkdir -p $SRC
}

get_rust_src() {
	msg "Getting Go sources"

	cd $SRC
	rm -rf rustc*
	curl -C - -L -O $RUSTURL
	tar -xvf $RUSTTAR
}

build_rust() {
	msg "Building Go for '"$BARCH"' platform"
	msg "Finished building Go for '"$BARCH"' platform"
}

setup_architecture
get_rust_src
build_rust

exit 0

