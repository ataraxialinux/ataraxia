#!/bin/sh

set -e
set -u
set -f

exec slibtool "$@" <&0
