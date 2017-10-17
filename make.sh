#!/bin/bash -e
#

product_name="Janus Linux"
product_version="0.1"
product_id="janus"
product_bug_url="https://github.com/protonesso/janus/issues"
product_url="januslinux.github.io"

JOB_FACTOR=1
NUM_CORES=$(grep ^processor /proc/cpuinfo | wc -l)
NUM_JOBS=$((NUM_CORES * JOB_FACTOR))

srcdir=$(pwd)/work/sources
pkgdir=$(pwd)/work/rootfs
isodir=$(pwd)/work/rootcd
stuffdir=$(pwd)/stuff

xflags="-g0 -Os -s -fno-stack-protector -U_FORTIFY_SOURCE"
default_configure="--prefix=/usr --libdir=/usr/lib --libexecdir=/usr/libexec --sysconfdir=/etc --sbindir=/sbin --localstatedir=/var"

kernelhost="janus"
kernelver="4.13.7"

just_prepare() {
    mkdir -p ${srcdir} ${pkgdir} ${isodir} ${stuffdir}
}

prepare_filesystem() {
    cd ${pkgdir}

    for _d in boot bin dev etc home sbin usr var run/lock janus; do
            install -d -m755 ${_d}
    done

    for _d in bin include lib share/misc sbin; do
        install -d -m755 usr/${_d}
    done
    
    for _d in $(seq 8); do
        install -d -m755 usr/share/man/man${_d}
    done
    
    for _d in bin lib sbin; do
        install -d -m755 janus/${_d}
    done
    
    for _d in skel rc.d; do
        install -d -m755 etc/${_d}
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
    
    for f in fstab group host.conf hosts passwd profile resolv.conf securetty shells adduser.conf busybox.conf services protocols rc.conf; do
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
	make menuconfig -j $NUM_JOBS
	sed -i "s/.*CONFIG_DEFAULT_HOSTNAME.*/CONFIG_DEFAULT_HOSTNAME=\"${kernelhost}\"/" .config
	echo "CONFIG_OVERLAY_FS_REDIRECT_DIR=y" >> .config
	echo "CONFIG_OVERLAY_FS_INDEX=y" >> .config
	sed -i "s/.*\\(CONFIG_KERNEL_.*\\)=y/\\#\\ \\1 is not set/" .config  
	sed -i "s/.*CONFIG_KERNEL_XZ.*/CONFIG_KERNEL_XZ=y/" .config
	sed -i "s/.*CONFIG_FB_VESA.*/CONFIG_FB_VESA=y/" .config
	sed -i "s/.*CONFIG_LOGO_LINUX_CLUT224.*/CONFIG_LOGO_LINUX_CLUT224=y/" .config
	sed -i "s/^CONFIG_DEBUG_KERNEL.*/\\# CONFIG_DEBUG_KERNEL is not set/" .config
	sed -i "s/.*CONFIG_EFI_STUB.*/CONFIG_EFI_STUB=y/" .config
	echo "CONFIG_APPLE_PROPERTIES=n" >> .config
	rep -q "CONFIG_X86_32=y" .config
	if [ $? = 1 ] ; then
		echo "CONFIG_EFI_MIXED=y" >> .config
	fi
	make -j $NUM_JOBS
	make INSTALL_MOD_PATH=${pkgdir} modules_install -j $NUM_JOBS
	make INSTALL_FW_PATH=${pkgdir}/lib/firmware firmware_install -j $NUM_JOBS
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
		--enable-optimize=size
	make -j $NUM_JOBS
	make DESTDIR=${pkgdir} install -j $NUM_JOBS
}

build_busybox() {
	cd ${srcdir}
	wget http://busybox.net/downloads/busybox-1.27.2.tar.bz2
	tar -xf busybox-1.27.2.tar.bz2
	cd busybox-1.27.2
	make distclean -j $NUM_JOBS
	make defconfig -j $NUM_JOBS
	sed -i "s/.*CONFIG_STATIC.*/CONFIG_STATIC=y/" .config
	make -j $NUM_JOBS
	make CONFIG_PREFIX=${pkgdir} install -j $NUM_JOBS
	mkdir ${pkgdir}/usr/share/udhcpc
	cp examples/udhcp/simple.script ${pkgdir}/usr/share/udhcpc/default.script
	chmod +x ${pkgdir}/usr/share/udhcpc/default.script
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

just_prepare
prepare_filesystem
build_linux
build_musl
build_busybox
strip_fs
make_iso

exit 0
