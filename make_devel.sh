#!/bin/bash

JOB_FACTOR=1
NUM_CORES=$(grep ^processor /proc/cpuinfo | wc -l)
NUM_JOBS=$((NUM_CORES * JOB_FACTOR))

srcdir=$(pwd)/work/sources
pkgdir=$(pwd)/work/rootfs
isodir=$(pwd)/work/rootcd
stuffdir=$(pwd)/stuff

buildhost="$(uname -p)-janus-linux-gnu"
xflags="-g0 -Os -s -fno-stack-protector -U_FORTIFY_SOURCE"
default_configure="--build="${buildhost}" --prefix=/usr --sysconfdir=/etc --sbindir=/sbin --localstatedir=/var --infodir=/usr/share/info --mandir=/usr/share/man --libdir=/usr/lib"

gcc_langs="c,c++,objc,obj-c++,fortran,ada,brig,go,lto"

pkg_vers="Janus Linux $(uname -p)"

just_prepare() {
    mkdir -p ${srcdir} ${pkgdir} ${isodir} ${stuffdir}
}

strip_fs() {
    echo "!Striping filesystem!"
	for dir in ${pkgdir}/bin ${pkgdir}/sbin ${pkgdir}/usr/bin ${pkgdir}/usr/sbin ${pkgdir}/usr/games
	do
		if [ -d "$dir" ]; then
			find $dir -type f -exec strip -s '{}' 2>/dev/null \;
		fi
	done
	find ${pkgdir} -name "*.so*" -exec $STRIP -s '{}' 2>/dev/null \;
	find ${pkgdir} -name "*.a" -exec $STRIP --strip-debug '{}' 2>/dev/null \;
    find ${pkgdir} -type f -name "*.pyc" -delete 2>/dev/null
    find ${pkgdir} -type f -name "*.pyo" -delete 2>/dev/null
    find ${pkgdir} -type f -name "perllocal.pod" -delete 2>/dev/null
    find ${pkgdir} -type f -name ".packlist" -delete 2>/dev/null
}

build_autoconf() {
	cd ${srcdir}
	wget https://ftp.gnu.org/pub/gnu/autoconf/autoconf-2.69.tar.xz
	tar -xf autoconf-2.69.tar.xz
	cd autoconf-2.69
	./configure \
		${default_configure} \
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_automake() {
	cd ${srcdir}
	wget https://ftp.gnu.org/pub/gnu/automake/automake-1.15.tar.xz
	tar -xf automake-1.15.tar.xz
	cd automake-1.15
	./configure \
		${default_configure} \
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_binutils() {
	cd ${srcdir}
	wget https://ftp.gnu.org/pub/gnu/binutils/binutils-2.28.tar.bz2
	tar -xf binutils-2.28.tar.bz2
	cd binutils-2.28
	mkdir build
	cd build
	../configure \
		${default_configure} \
		--disable-gdb    \
		--disable-werror \
		--enable-shared  \
		--enable-threads \
		--enable-gold    \
		--enable-plugins \
		--enable-install-libiberty \
		--enable-nls \
        	CFLAGS="${xflags}"
	make tooldir=/usr -j $NUM_JOBS
	make tooldir=/usr DESTDIR=${pkgdir} install install-info -j $NUM_JOBS
}

build_bison() {
	cd ${srcdir}
	wget https://ftp.gnu.org/pub/gnu/bison/bison-3.0.4.tar.xz
	tar -xf bison-3.0.4.tar.xz
	cd bison-3.0.4
	./configure \
		${default_configure} \
		--enable-threads=posix \
     		--enable-nls \
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_file() {
	cd ${srcdir}
	wget ftp://ftp.astron.com/pub/file/file-5.31.tar.gz
	tar -xf file-5.31.tar.gz
	cd file-5.31
	./configure \
		${default_configure} \
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_flex() {
	cd ${srcdir}
	wget https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz
	tar -xf flex-2.6.4.tar.gz
	cd flex-2.6.4
	./configure \
		${default_configure} \
		--enable-static \
     		--enable-shared \
     		--enable-nls \
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_gcc() {
	cd ${srcdir}
	wget https://ftp.gnu.org/pub/gnu/gcc/gcc-7.1.0/gcc-7.1.0.tar.bz2
	tar -xf gcc-7.1.0.tar.bz2
	cd gcc-7.1.0
	mkdir build
	cd build
	../configure \
		${default_configure} \
		--libexecdir=/usr/lib \
		--enable-multilib \
		--enable-bootstrap \
		--enable-languages=${gcc_langs} \
		--enable-clocale=generic \
		--enable-threads=posix \
		--enable-tls \
		--enable-nls \
		--enable-lto \
		--enable-shared \
		--enable-libstdcxx-time \
		--enable-checking=release \
		--disable-libitm \
		--disable-gnu-indirect-function \
		--disable-libstdcxx-pch \
		--disable-libmudflap \
		--disable-libsanitizer \
		--disable-libmpx \
		--disable-libcilkrts \
		--with-multilib-list=m64 \
		--with-system-zlib \
		--with-pkgversion="${pkg_vers}"
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_gperf() {
	cd ${srcdir}
	wget https://ftp.gnu.org/pub/gnu/gperf/gperf-3.1.tar.gz
	tar -xf gperf-3.1.tar.gz
	cd gperf-3.1
	./configure \
		${default_configure} \
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_grep() {
	cd ${srcdir}
	wget https://ftp.gnu.org/pub/gnu/grep/grep-3.0.tar.xz
	tar -xf grep-3.0.tar.xz
	cd grep-3.0
	./configure \
		${default_configure} \
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_groff() {
	cd ${srcdir}
	wget https://ftp.gnu.org/pub/gnu/groff/groff-1.22.3.tar.gz
	tar -xf groff-1.22.3.tar.gz
	cd groff-1.22.3
	./configure \
		${default_configure} \
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_libtool() {
	cd ${srcdir}
	wget https://ftp.gnu.org/pub/gnu/libtool/libtool-2.4.6.tar.xz
	tar -xf libtool-2.4.6.tar.xz
	cd libtool-2.4.6
	./configure \
		${default_configure} \
		--enable-static \
		--enable-shared \
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_m4() {
	cd ${srcdir}
	wget https://ftp.gnu.org/pub/gnu/m4/m4-1.4.18.tar.xz
	tar -xf m4-1.4.18.tar.xz
	cd m4-1.4.18
	./configure \
		${default_configure} \
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_make() {
	cd ${srcdir}
	wget https://ftp.gnu.org/pub/gnu/make/make-4.2.1.tar.bz2
	tar -xf make-4.2.1.tar.bz2
	cd make-4.2.1
	./configure \
		${default_configure} \
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_patch() {
	cd ${srcdir}
	wget https://ftp.gnu.org/pub/gnu/patch/patch-2.7.5.tar.xz
	tar -xf patch-2.7.5.tar.xz
	cd patch-2.7.5
	./configure \
		${default_configure} \
        	CFLAGS="${xflags}"
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

just_prepare
build_autoconf
build_automake
build_binutils
build_bison
build_file
build_flex
build_gcc
build_gperf
build_grep
build_groff
build_libtool
build_m4
build_make
build_patch
strip_fs

exit 0
