#!/usr/bin/bash

export PATH="/usr/local/usr/bin:/usr/local/usr/bin:/usr/usr/bin"

/usr/bin/dmesg -n 1

/usr/bin/clear

/usr/bin/mountpoint -q /proc || /usr/bin/mount -o nosuid,noexec,nodev -t proc proc /proc
/usr/bin/mountpoint -q /sys || /usr/bin/mount -o nosuid,noexec,nodev -t sysfs sys /sys
/usr/bin/mountpoint -q /run || /usr/bin/mount -o mode=0755,nosuid,nodev -t tmpfs run /run
/usr/bin/mountpoint -q /dev || /usr/bin/mount -o mode=0755,nosuid -t devtmpfs dev /dev
/usr/bin/mkdir -p -m0755 /run/lvm /run/user /run/lock /run/log /dev/pts /dev/shm
/usr/bin/mountpoint -q /dev/pts || /usr/bin/mount -o mode=0620,gid=5,nosuid,noexec -n -t devpts devpts /dev/pts
/usr/bin/mountpoint -q /dev/shm || /usr/bin/mount -o mode=1777,nosuid,nodev -n -t tmpfs shm /dev/shm
/usr/bin/mountpoint -q /sys/kernel/security || /usr/bin/mount -n -t securityfs securityfs /sys/kernel/security
/usr/bin/mountpoint -q /sys/fs/cgroup || /usr/bin/mount -o mode=0755 -t tmpfs cgroup /sys/fs/cgroup

for f in $(/usr/bin/kmod static-nodes 2>/dev/null|/usr/bin/awk '/Module/ {print $2}'); do
	/usr/bin/modprobe -bq $f 2>/dev/null
done

/usr/bin/modules-load -v | tr '\n' ' ' | sed 's:insmod [^ ]*/::g; s:\.ko\(\.xz\)\? ::g'

/usr/bin/udevd --daemon
/usr/bin/udevadm trigger --action=add --type=subsystems
/usr/bin/udevadm trigger --action=add --type=devices
/usr/bin/udevadm trigger --action=change --type=devices
/usr/bin/udevadm settle

if [[ -f '/etc/font.conf' ]]
then
	export FONT="$(cat /etc/font.conf)"
	/usr/bin/setfont $FONT
else
	/usr/bin/setfont default
fi

if [[ -f '/etc/kmap.conf' ]]
then
	export KEYMAP="$(cat /etc/kmap.conf)"
	/usr/bin/loadkeys -q $KEYMAP
else
	/usr/bin/loadkeys -q us
fi

/usr/bin/hwclock --hctosys --utc

/usr/bin/mount -o remount,ro /

if [ -x /usr/bin/dmraid -o -x /usr/bin/dmraid ]; then
	/usr/bin/dmraid -i -ay
fi

if [ -x /usr/bin/btrfs ]; then
	/usr/bin/btrfs device scan || exec sh
fi

if [ -x /usr/bin/vgchange -o -x /usr/bin/vgchange ]; then
	/usr/bin/vgchange --sysinit -a y || exec sh
fi

if [ -f /forcefsck ]; then
FORCEFSCK="-f"
fi

/usr/bin/fsck $FORCEFSCK -A -T -C -a
if [ $? -gt 1 ]; then
	echo
	echo "***************  FILESYSTEM CHECK FAILED  ******************"
	echo "*                                                          *"
	echo "*  Please repair manually and reboot. Note that the root   *"
	echo "*  file system is currently mounted read-only. To remount  *"
	echo "*  it read-write type: mount -n -o remount,rw /            *"
	echo "*  When you exit the maintainance shell the system will    *"
	echo "*  reboot automatically.                                   *"
	echo "*                                                          *"
	echo "************************************************************"
	echo
	/usr/bin/sulogin -p
	/usr/bin/umount -a -r
	/usr/bin/mount -o remount,ro /
	/usr/bin/halt -r
	exit 0
fi

/usr/bin/mount -o remount,rw /

/usr/bin/swapon -a

/usr/bin/mount -a -t "nosysfs,nonfs,nonfs4,nosmbfs,nocifs" -O no_netdev

/usr/bin/cp /var/lib/random-seed /dev/urandom >/dev/null 2>&1 || true
( /usr/bin/umask 077; bytes=$(/usr/bin/cat /proc/sys/kernel/random/poolsize) || bytes=512; /usr/bin/dd if=/dev/urandom of=/var/lib/random-seed count=1 bs=$bytes >/dev/null 2>&1 )

/usr/bin/ip link set up dev lo

if [[ -f '/etc/hostname' ]]
then
	/usr/bin/hostname -F /etc/hostname
else
	/usr/bin/hostname miyuki
fi

if [[ -f '/etc/timezone' ]]
then
	MYTZ="$(cat /etc/timezone)"
	/usr/bin/ln -sf /usr/share/zoneinfo/$MYTZ /etc/localtime
else
	/usr/bin/ln -sf /usr/share/zoneinfo/Europe/Moscow /etc/localtime
fi

sysctl -q --system

install -m0664 -o root -g utmp /dev/null /run/utmp
if [ ! -e /var/log/wtmp ]; then
	/usr/bin/install -m0664 -o root -g utmp /dev/null /var/log/wtmp
fi
if [ ! -e /var/log/btmp ]; then
	/usr/bin/install -m0600 -o root -g utmp /dev/null /var/log/btmp
fi
/usr/bin/install -dm1777 /tmp/.X11-unix /tmp/.ICE-unix
/usr/bin/rm -f /etc/nologin /forcefsck /forcequotacheck /fastboot

/usr/bin/dmesg >/var/log/dmesg.log

: > /run/utmp

echo

exec /usr/bin/agetty 38400 tty1 linux
exec /usr/bin/agetty 38400 tty2 linux
exec /usr/bin/agetty 38400 tty3 linux
exec /usr/bin/agetty 38400 tty4 linux
exec /usr/bin/agetty -L always ttyS0 115200 vt100
