#!/bin/sh

mkdir -p $ROOTFS/{boot,dev,etc/skel,home,mnt,proc,sys}
mkdir -p $ROOTFS/var/{cache,lib,local,lock,log,opt,run,spool}
install -d -m 0750 $ROOTFS/root
install -d -m 1777 $ROOTFS/{var/,}tmp
mkdir -p $ROOTFS/usr/{,local/}{bin,include,lib/modules,share}

cd $ROOTFS/usr
ln -sf bin sbin

cd $ROOTFS
ln -sf usr/bin bin
ln -sf usr/lib lib
ln -sf usr/bin sbin

case $A in
	x86_64|arm64)
		cd $ROOTFS/usr
		ln -sf lib lib64
		cd $ROOTFS
		ln -sf lib lib64
		;;
esac

ln -sf /proc/mounts $ROOTFS/etc/mtab

touch $ROOTFS/var/log/lastlog
chmod 664 $ROOTFS/var/log/lastlog
