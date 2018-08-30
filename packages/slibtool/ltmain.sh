#!/bin/sh

set -e
set -u
set -f

exec slibtool-static "$@" <&0
