#!/bin/sh

export PATH="/usr/local/sbin:/usr/local/bin:/usr/bin"

dmesg -n 1

mountpoint -q /proc    || mount -t proc proc /proc -o nosuid,noexec,nodev
mountpoint -q /sys     || mount -t sysfs sys /sys -o nosuid,noexec,nodev
mountpoint -q /run     || mount -t tmpfs run /run -o mode=0755,nosuid,nodev
mountpoint -q /dev     || mount -t devtmpfs dev /dev -o mode=0755,nosuid
mkdir -p /dev/pts /dev/shm
mountpoint -q /dev/pts || mount -t devpts devpts /dev/pts -o mode=0620,gid=5,nosuid,noexec
mountpoint -q /dev/shm || mount -t tmpfs shm /dev/shm -o mode=1777,nosuid,nodev

udevd --daemon
udevadm trigger --action=add --type=subsystems
udevadm trigger --action=add --type=devices
udevadm trigger --action=change --type=devices
udevadm settle

mount -o remount,ro /

fsck -ATa
if [ $? -eq 1 ]; then
	clear
	echo Filesystem errors exist, fix manually.
	sleep 15
	sh
	halt -r
fi

mount -o remount,rw /

swapon -a

mount -a

if [[ -f '/etc/sysctl.conf' ]]
then
	sysctl -w -p /etc/sysctl.conf
fi

: > /var/run/utmp
rm -rf /forcefsck /fastboot /etc/nologin /etc/shutdownpid
(cd /var/run && find . -name "*.pid" -delete)
(cd /var/lock && find . ! -type d -delete)
(cd /tmp && find . ! -name . -delete)
mkdir -m 1777 /tmp/.ICE-unix

if [[ -f '/etc/hostname' ]]
then
	hostname -F /etc/hostname
else
	hostname localhost
fi

hwclock --hctosys --utc

if [[ -f '/etc/font.conf' ]]
then
	export FONT="$(cat /etc/font.conf)"
	setfont $FONT
else
	setfont default
fi

if [[ -f '/etc/kmap.conf' ]]
then
	export KEYMAP="$(cat /etc/kmap.conf)"
	loadkeys -q $KEYMAP
else
	loadkeys -q us
fi

ifup -a

if [ -x /etc/rc.local ]; then
	/etc/rc.local
fi

dmesg >/var/log/dmesg.log

clear
