#!/bin/sh

set -e

export TOPDIR=$(pwd)

. $TOPDIR/config

export UTILS="$TOPDIR/utils"
export REPO="$TOPDIR/packages"
export BUILD="$TOPDIR/build"

export LC_ALL=POSIX

export XJOBS="$(expr $(nproc) + 1)"

. $UTILS/build-toolchain.sh
. $UTILS/setup_rootfs.sh

export STG0DIR="$ROOTFS/tools"
mkdir -p $STG0DIR

echo "Compiler is $CC"

exit 0

