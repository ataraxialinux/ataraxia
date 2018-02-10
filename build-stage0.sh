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
. $UTILS/setup-rootfs.sh

export STG0DIR="$ROOTFS/tools"
mkdir -p $STG0DIR

. $UTILS/generate-makepkg.sh

set_env() {
	CC="$XTARGET-gcc -static --static"
	CXX="$XTARGET-g++ -static --static"
	AR="$XTARGET-ar"
	AS="$XTARGET-as"
	LD="$XTARGET-ld"
	RANLIB="$XTARGET-ranlib"
	READELF="$XTARGET-readelf"
	STRIP="$XTARGET-strip"
}

build() {
	cd $SOURCES
	wget -c https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.15.2.tar.xz
	tar -xf linux-4.15.2.tar.xz
	cd linux-4.15.2
	make mrproper
	make ARCH=$XKARCH INSTALL_HDR_PATH=$STG0DIR headers_install
	find $STG0DIR/include -name .install -or -name ..install.cmd | xargs rm -fv

	cd $SOURCES
	wget -c http://www.musl-libc.org/releases/musl-1.1.18.tar.gz
	tar -xf musl-1.1.18.tar.gz
	cd musl-1.1.18
	./configure \
		--build=$XHOST \
		--host=$XTARGET \
		--prefix= \
		--enable-optimize
	make -j$XJOBS
	make DESTDIR=$STG0DIR install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/binutils/binutils-2.30.tar.xz
	tar -xf binutils-2.30.tar.xz
	cd binutils-2.30
	mkdir build
	cd build
	../configure \
		--build=$XHOST \
		--host=$XTARGET \
		--target=$XTARGET \
		--prefix=$STG0DIR \
		--libdir=$STG0DIR/lib \
		--with-lib-path=$STG0DIR/lib \
		--enable-deterministic-archives \
		--disable-cloog-version-check \
		--disable-compressed-debug-sections \
		--disable-multilib \
		--disable-nls \
		--disable-ppl-version-check \
		--disable-werror
	make -j$XJOBS
	make install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/gcc/gcc-7.3.0/gcc-7.3.0.tar.xz
	wget -c http://ftp.gnu.org/gnu/gmp/gmp-6.1.2.tar.xz
	wget -c http://ftp.gnu.org/gnu/mpfr/mpfr-4.0.0.tar.xz
	wget -c http://ftp.gnu.org/gnu/mpc/mpc-1.1.0.tar.gz
	tar -xf gcc-7.3.0.tar.xz
	cd gcc-7.3.0
for file in \
 gcc/config/linux.h gcc/config/i386/linux.h gcc/config/i386/linux64.h \
 gcc/config/arm/linux-eabi.h gcc/config/arm/linux-elf.h \
 gcc/config/mips/linux.h \
 gcc/config/rs6000/linux64.h gcc/config/rs6000/sysv4.h \
 gcc/config/aarch64/aarch64-linux.h \
 gcc/config/microblaze/linux.h \
 gcc/config/sh/linux.h ; \
do
    if test ! -f "$file"
    then
        echo "WARNING: ${0}: Non-existent file: $file" 1>&2
        continue;
    fi
    sed -i \
     -e 's@/lib\(64\)\{0,1\}\(32\)\{0,1\}/ld@$STG0DIR&@g' \
     -e 's@/usr@$STG0DIR@g' "$file"
    echo '
#undef STANDARD_STARTFILE_PREFIX_1
#undef STANDARD_STARTFILE_PREFIX_2
#define STANDARD_STARTFILE_PREFIX_1 "$STG0DIR/lib/"
#define STANDARD_STARTFILE_PREFIX_2 ""' >> "$file"
done
	tar xf ../mpfr-4.0.0.tar.xz
	mv mpfr-4.0.0 mpfr
	tar xf ../gmp-6.1.2.tar.xz
	mv gmp-6.1.2 gmp
	tar xf ../mpc-1.1.0.tar.gz
	mv mpc-1.1.0 mpc
	mkdir build
	cd build
	../configure \
		--build=$XHOST \
		--host=$XTARGET \
		--target=$XTARGET \
		--prefix=$STG0DIR \
		--libdir=$STG0DIR/lib \
		--enable-clocale=generic \
		--enable-fully-dynamic-string \
		--enable-install-libiberty \
		--enable-languages=c,c++ \
		--enable-libstdcxx-time \
		--enable-tls \
		--with-local-prefix=$STG0DIR \
		--with-native-system-header-dir=$STG0DIR/include \
		--disable-bootstrap \
		--disable-gnu-indirect-function \
		--disable-libmpx \
		--disable-libmudflap \
		--disable-libsanitizer \
		--disable-libstdcxx-pch \
		--disable-multilib \
		--disable-nls \
		--disable-symvers \
		$GCCOPTS
	make AS_FOR_TARGET="$AS" LD_FOR_TARGET="$LD" -j$XJOBS
	make install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/make/make-4.2.1.tar.bz2
	tar -xf make-4.2.1.tar.bz2
	cd make-4.2.1
	./configure \
		--build=$XHOST \
		--host=$XTARGET \
		--prefix=$STG0DIR \
		--without-guile \
		--disable-nls
	make -j$XJOBS
	make install

	cd $SOURCES
	wget -c http://ftp.gnu.org/gnu/patch/patch-2.7.5.tar.xz
	tar -xf patch-2.7.5.tar.xz
	cd patch-2.7.5
	./configure \
		--build=$XHOST \
		--host=$XTARGET \
		--prefix=$STG0DIR
	make -j$XJOBS
	make install

	cd $SOURCES
	wget -c http://busybox.net/downloads/busybox-1.28.0.tar.bz2
	tar -xf busybox-1.28.0.tar.bz2
	cd busybox-1.28.0
	make ARCH=$XKARCH CROSS_COMPILE==$XTARGET- defconfig
	make ARCH=$XKARCH CROSS_COMPILE==$XTARGET- -j$XJOBS
	make ARCH=$XKARCH CROSS_COMPILE==$XTARGET- CONFIG_PREFIX=$STG0DIR install
}

symlinks() {
for file in cat echo env pwd sh stty
do
    ln -sf "$STG0DIR/bin/${file}" "$ROOTFS/bin"
done
ln -sf gcc $STG0DIR/bin/cc
ln -sf $STG0DIR/lib/libgcc_s.so   "$ROOTFS/usr/lib"
ln -sf $STG0DIR/lib/libgcc_s.so.1 "$ROOTFS/usr/lib"
ln -sf $STG0DIR/lib/libstdc++.so   "$ROOTFS/usr/lib"
ln -sf $STG0DIR/lib/libstdc++.so.6 "$ROOTFS/usr/lib"
ln -sf $STG0DIR/lib/libstdc++.a "$ROOTFS/usr/lib"
sed -e 's/tools/usr/' $STG0DIR/lib/libstdc++.la \
 > "$ROOTFS/usr/lib/libstdc++.la"
}

set_env
build
symlinks

exit 0

