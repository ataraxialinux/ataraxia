#!/bin/bash
#
# Build minimal Janus Linux filesystem.

JOB_FACTOR=1
NUM_CORES=$(grep ^processor /proc/cpuinfo | wc -l)
NUM_JOBS=$((NUM_CORES * JOB_FACTOR))

srcdir=$(pwd)/work/sources
pkgdir=$(pwd)/work/rootfs
isodir=$(pwd)/work/rootcd
stuffdir=$(pwd)/work/stuff

buildhost="$(uname -p)-janus-linux-gnu"
xflags="-g0 -Os -s -fno-stack-protector -U_FORTIFY_SOURCE"
default_configure="--build="${buildhost}" --prefix=/usr --sysconfdir=/etc --sbindir=/sbin --localstatedir=/var --infodir=/usr/share/info --mandir=/usr/share/man --libdir=/usr/lib"

kernelhost="janus"
kernelver="4.11.3"

just_prepare() {
    mkdir -p ${srcdir} ${pkgdir} ${isodir} ${stuffdir}
}

prepare_filesystem() {
    install -d ${pkgdir}/bin
    install -d ${pkgdir}/sbin
    install -d ${pkgdir}/boot
    install -d ${pkgdir}/dev
    install -d ${pkgdir}/dev/{pts,shm}
    install -d ${pkgdir}/proc
    install -d ${pkgdir}/sys
    install -d ${pkgdir}/etc
    install -d ${pkgdir}/mnt
    install -d ${pkgdir}/run
    install -d ${pkgdir}/lib
    install -d ${pkgdir}/opt
    install -d ${pkgdir}/usr
    install -d ${pkgdir}/usr/{bin,include,lib,sbin,share,src}
    install -d -p ${pkgdir}/usr/share/{man,info}
    ln -s ../var ${pkgdir}/usr/var
    install -d ${pkgdir}/var
    install -d ${pkgdir}/var/cache
    install -d ${pkgdir}/var/lib
    install -d ${pkgdir}/var/log
    install -d ${pkgdir}/var/log/old
    install -d ${pkgdir}/var/run
    install -d ${pkgdir}/var/spool
    install -d ${pkgdir}/var/ftp
    install -d ${pkgdir}/var/www
    install -d ${pkgdir}/var/empty
    ln -s spool/mail ${pkgdir}/var/mail
    install -d ${pkgdir}/home
    install -d -m 1777 ${pkgdir}/tmp
    install -d -m 0750 ${pkgdir}/root
    install -d -m 1777 ${pkgdir}/var/lock
    install -d -m 1777 ${pkgdir}/var/spool/mail
    install -d -m 1777 ${pkgdir}/var/tmp
}

build_linux() {
    cd ${srcdir}
    wget http://linux-libre.fsfla.org/pub/linux-libre/releases/${kernelver}-gnu/linux-libre-${kernelver}-gnu.tar.xz
    tar -xf linux-libre-${kernelver}-gnu.tar.xz
    cd linux-${kernelver}
	make mrproper -j $NUM_JOBS
	make defconfig -j $NUM_JOBS
	sed -i "s/.*CONFIG_DEFAULT_HOSTNAME.*/CONFIG_DEFAULT_HOSTNAME=\"${kernelhost}\"/" .config
	sed -i "s/.*\\(CONFIG_KERNEL_.*\\)=y/\\#\\ \\1 is not set/" .config 
	sed -i "s/.*CONFIG_KERNEL_XZ.*/CONFIG_KERNEL_XZ=y/" .config
	sed -i "s/^CONFIG_DEBUG_KERNEL.*/\\# CONFIG_DEBUG_KERNEL is not set/" .config
	sed -i "s/.*CONFIG_EFI_STUB.*/CONFIG_EFI_STUB=y/" .config
	grep -q "CONFIG_X86_32=y" .config
	if [ $? = 1 ] ; then
		echo "CONFIG_EFI_MIXED=y" >> .config
	fi
	make CFLAGS="${xflags}" -j $NUM_JOBS
	cp arch/x86/boot/bzImage ${pkgdir}/boot/vmlinuz-${kernelver}-${kernelhost}
	cp .config ${pkgdir}/boot/config-${kernelver}-${kernelhost}
	make INSTALL_MOD_PATH=${pkgdir} modules_install -j $NUM_JOBS
	make INSTALL_FW_PATH=${pkgdir}/lib/firmware firmware_install -j $NUM_JOBS
	make INSTALL_HDR_PATH=${pkgdir}/usr headers_install -j $NUM_JOBS
}

build_busybox() {
    cd ${srcdir}
    wget http://busybox.net/downloads/busybox-1.26.2.tar.bz2
    tar -xf busybox-1.26.2.tar.bz2
    cd busybox-1.26.2
    make distclean -j $NUM_JOBS
    make defconfig -j $NUM_JOBS
	sed -i "s/.*CONFIG_INETD.*/CONFIG_INETD=n/" .config
	make EXTRA_CFLAGS="${xflags}" -j $NUM_JOBS
	make CONFIG_PREFIX=${pkgdir} install -j $NUM_JOBS
}

build_musl(){
    cd ${srcdir}
    wget http://www.musl-libc.org/releases/musl-1.1.16.tar.gz
    tar -xf musl-1.1.16.tar.gz
    cd musl-1.1.16
    ./configure \
        ${default_configure} \
        --syslibdir=/lib \
        --enable-shared \
        --enable-static \
        --enable-optimize=size \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_bc() {
    cd ${srcdir}
    wget http://ftp.gnu.org/gnu/bc/bc-1.07.1.tar.gz
    tar -xf bc-1.07.1.tar.gz
    cd bc-1.07.1
    ./configure \
        --prefix=/usr \
        --sysconfdir=/etc \
        --sbindir=/sbin \
        --localstatedir=/var \
        --infodir=/usr/share/info \
        --mandir=/usr/share/man \
        --libdir=/usr/lib \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_zlib() {
    cd ${srcdir}
    wget http://www.zlib.net/zlib-1.2.11.tar.xz
    tar -xf zlib-1.2.11.tar.xz
    cd zlib-1.2.11
    ./configure \
        ${default_configure} \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_pcre() {
    cd ${srcdir}
    wget https://ftp.pcre.org/pub/pcre/pcre-8.40.tar.bz2
    tar -xf pcre-8.40.tar.bz2
    cd pcre-8.40
    ./configure \
        ${default_configure} \
        --enable-jit \
        --enable-utf8 \
        --enable-pcre16 \
        --enable-pcre32 \
        --enable-pcregrep-libz \
        --enable-unicode-properties \
        --disable-static \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_e2fsprogs() {
    cd ${srcdir}
    wget http://prdownloads.sourceforge.net/e2fsprogs/e2fsprogs-1.43.4.tar.gz
    tar -xf e2fsprogs-1.43.4.tar.gz
    cd e2fsprogs-1.43.4
    ./configure \
        ${default_configure} \
        --enable-elf-shlibs \
	--enable-symlink-install \
	--disable-fsck \
	--disable-uuidd \
	--disable-libuuid \
	--disable-libblkid \
	--disable-tls \
	--disable-nls \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install install-libs -j $NUM_JOBS
}

build_sqlite() {
    cd ${srcdir}
    wget http://www.sqlite.org/2017/sqlite-autoconf-3190200.tar.gz
    tar -xf sqlite-autoconf-3190200.tar.gz
    cd sqlite-autoconf-3190200
    ./configure \
        ${default_configure} \
        --enable-threadsafe \
	--disable-static \
	--enable-readline \
	--enable-dynamic-extensions \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_cdrtools() {
    cd ${srcdir}
    wget http://downloads.sourceforge.net/cdrtools/cdrtools-3.01.tar.gz
    tar -xf cdrtools-3.01.tar.gz
    cd cdrtools-3.01
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_perl() {
    cd ${srcdir}
    wget http://www.cpan.org/src/5.0/perl-5.24.1.tar.gz
    tar -xf perl-5.24.1.tar.gz
    cd perl-5.24.1
    ./Configure -des \
		-Dcccdlflags='-fPIC' \
		-Dcccdlflags='-fPIC' \
		-Dccdlflags='-rdynamic' \
		-Dprefix=/usr \
		-Dvendorprefix=/usr \
		-Dvendorlib=/usr/share/perl5/vendor_perl \
		-Dvendorarch=/usr/lib/perl5/vendor_perl \
		-Dsiteprefix=/usr/local \
		-Dsitelib=/usr/local/share/perl5/site_perl \
		-Dsitearch=/usr/local/lib/perl5/site_perl \
		-Dlocincpth=' ' \
		-Doptimize="${xflags}" \
		-Duselargefiles \
		-Dusethreads \
		-Duseshrplib \
		-Dd_semctl_semun \
		-Dman1dir=/usr/share/man/man1 \
		-Dman3dir=/usr/share/man/man3 \
		-Dinstallman1dir=/usr/share/man/man1 \
		-Dinstallman3dir=/usr/share/man/man3 \
		-Dman1ext='1' \
		-Dman3ext='3pm' \
		-Ud_csh \
		-Dusenm
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_kmod() {
    cd ${srcdir}
    wget https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-24.tar.gz
    tar -xf kmod-24.tar.gz
    cd kmod-24
    ./configure \
        ${default_configure} \
        --disable-static \
        --enable-shared \
        --enable-tools \
        --with-rootlibdir=/usr/lib \
        --without-zlib \
        --without-xz \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_ncurses() {
    cd ${srcdir}
    wget http://ftp.gnu.org/gnu/ncurses/ncurses-6.0.tar.gz
    tar -xf ncurses-6.0.tar.gz
    cd ncurses-6.0
    ./configure \
        ${default_configure} \
        --with-shared \
        --without-debug \
        --without-normal \
        --enable-pc-files \
        --enable-widec \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_readline() {
    cd ${srcdir}
    wget http://ftp.gnu.org/gnu/readline/readline-7.0.tar.gz
    tar -xf readline-7.0.tar.gz
    cd readline-7.0
    ./configure \
        ${default_configure} \
        --enable-multibyte \
        --enable-static \
        --disable-shared \
        --with-curses \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_nano() {
    cd ${srcdir}
    wget https://www.nano-editor.org/dist/v2.8/nano-2.8.4.tar.gz
    tar -xf nano-2.8.4.tar.gz
    cd nano-2.8.4
    ./configure \
        ${default_configure} \
        --enable-utf8 \
        --disable-wrapping-as-root \
        --disable-glibtest \
        --with-wordbounds \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_bash() {
    cd ${srcdir}
    wget http://ftp.gnu.org/gnu/bash/bash-4.4.tar.gz
    tar -xf bash-4.4.tar.gz
    cd bash-4.4
    ./configure \
        ${default_configure} \
        --enable-static-link \
        --with-installed-readline \
        --with-curses \
        --without-bash-malloc \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_grub() {
    cd ${srcdir}
    wget http://ftp.gnu.org/gnu/grub/grub-2.02.tar.gz
    tar -xf grub-2.02.tar.gz
    cd grub-2.02
    ./configure \
        ${default_configure} \
        --disable-efiemu \
        --disable-werror \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_util_linux() {
    cd ${srcdir}
    wget https://www.kernel.org/pub/linux/utils/util-linux/v2.29/util-linux-2.29.2.tar.gz
    tar -xf util-linux-2.29.2.tar.gz
    cd util-linux-2.29.2
    ./configure \
        ${default_configure} \
        --enable-usrdir-path \
        --enable-static \
        --enable-shared \
        --enable-sulogin-emergency-mount \
        --enable-static-programs=nologin \
        --enable-use-tty-group \
        --enable-wall \
        --enable-write \
        --with-btrfs \
        --without-python \
        --without-systemd \
        --without-readline \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_eudev() {
    cd ${srcdir}
    wget http://dev.gentoo.org/~blueness/eudev/eudev-3.2.2.tar.gz
    tar -xf eudev-3.2.2.tar.gz
    cd eudev-3.2.2
    ./configure \
		${default_configure} \
		--with-rootprefix= \
		--with-rootrundir=/run \
		--with-rootlibexecdir=/lib/udev \
		--enable-split-usr \
		--enable-manpages \
		--disable-hwdb \
		--enable-kmod \
		--exec-prefix=/
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_openrc() {
    cd ${srcdir}
    wget https://github.com/OpenRC/openrc/archive/0.26.2.tar.gz
    tar -xf openrc-0.26.2.tar.gz
    cd openrc-0.26.2
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

etc_install() {
    echo "Avaliable soon!"
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

make_slax_module() {
    echo "Avaliable soon!"
}

just_prepare
prepare_filesystem
build_linux
build_busybox
build_musl
build_bc
build_zlib
build_pcre
build_e2fsprogs
build_sqlite
build_cdrtools
build_perl
build_kmod
build_ncurses
build_readline
build_nano
build_util_linux
build_bash
build_grub
build_util_linux
build_eudev
build_openrc
etc_install
strip_fs
make_slax_module

exit 0
