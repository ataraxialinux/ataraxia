#!/bin/sh

export OUT="$BPKGS/pkg-$PKG-$VER"

pkgprep() {
	rm -rf $OUT
	mkdir -p $OUT
}

tarxf() {
	cd $SRC
	[ -f $2$3 ] || wget -c $1$2$3
	rm -rf ${4:-$2}
	tar -xf $2$3
	cd ${4:-$2}
}

packpkg() {
	cd $OUT
	tar czvf $PKGS/$PKG-$VER.tgz .
}

installpkg() {
	fbpkg install $PKGS/$PKG-$VER.tgz
}

installhostpkg() {
        ./$KEEP/fbpkg install $PKGS/$PKG-$VER.tgz
}
