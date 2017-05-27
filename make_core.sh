#!/bin/bash
#
# Build minimal Janus Linux filesystem.

product_name="Janus Linux"
product_version="0.1"
product_id="janus"
product_bug_url=""
product_url=""

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

kernelhost="janus"
kernelver="4.11.3"

grub_platform="pc,efi"

just_prepare() {
    mkdir -p ${srcdir} ${pkgdir} ${isodir} ${stuffdir}
}

prepare_filesystem() {
    cd ${pkgdir}

    for _d in boot bin dev etc/skel home sbin usr var run/lock; do
            install -d -m755 ${_d}
    done

    for _d in bin include lib share/misc src; do
        install -d -m755 usr/${_d}
    done
    
    for _d in $(seq 8); do
        install -d -m755 usr/share/man/man${_d}
    done

    install -d -m555 proc
    install -d -m555 sys
    install -d -m0750 root
    install -d -m1777 tmp

    install -d var/{cache/man,lib,log}
    install -d -m1777 var/{tmp,spool/{,mail,uucp}}
    ln -s spool/mail var/mail
    ln -s ../run var/run

    ln -s /proc/mounts etc/mtab
    
    for f in fstab group host.conf hosts passwd profile resolv.conf securetty shells adduser.conf busybox.conf services protocols; do
            install -m644 ${stuffdir}/${f} etc/
    done
    
    for f in gshadow shadow ; do
        install -m600 ${stuffdir}/${f} etc/
    done
    
cat >${pkgdir}/etc/os-release<<EOF
NAME="${product_name}"
ID=${product_id}
VERSION_ID=${product_version}
PRETTY_NAME="${product_name} ${product_version}"
HOME_URL="${product_url}"
BUG_REPORT_URL="${product_bug_url}"
EOF

cat >${pkgdir}/etc/issue<<EOF
${product_name} ${product_version} \r \l
EOF
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
        --infodir=/usr/share/info \
        --mandir=/usr/share/man \
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
        --shared \
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
        --with-platform=${grub_platform} \
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
        --without-readline \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_systemd() {
    cd ${srcdir}
    wget https://github.com/systemd/systemd/archive/v233.tar.gz
    tar -xf systemd-233.tar.gz
    cd systemd-233
    ./configure \
        ${default_configure} \
        --config-cache           \
        --with-rootprefix=       \
        --with-rootlibdir=/lib   \
        --enable-split-usr       \
        --disable-firstboot      \
        --disable-ldconfig       \
        --disable-sysusers       \
        --without-python         \
        --with-default-dnssec=no \
        CFLAGS="${xflags}"
    make -j $NUM_JOBS
    make DESTDIR=${pkgdir} install -j $NUM_JOBS
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

build_tzdata() {
    cd ${srcdir}
    wget https://www.iana.org/time-zones/repository/releases/tzdata2017b.tar.gz
    wget https://www.iana.org/time-zones/repository/releases/tzcode2017b.tar.gz
    tar -xf tzdata2017b.tar.gz
    tar -xf tzcode2017b.tar.gz
    make -j1 install \
        CFLAGS="${xflags}" \
        DESTDIR=${pkgdir} \
        TOPDIR=/usr \
        TZDIR=/usr/share/zoneinfo \
        ETCDIR=/usr/sbin \
        MANDIR=/usr/share/man
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
build_bash
build_grub
build_util_linux
build_systemd
build_tzdata
strip_fs

exit 0
