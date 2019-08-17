#!/bin/sh
#
# System startup script
#

 . /etc/rc.conf

dmesg -n 1

mountpoint -q /proc                || mount -t proc proc /proc -o nosuid,noexec,nodev
mountpoint -q /sys                 || mount -t sysfs sys /sys -o nosuid,noexec,nodev
mountpoint -q /run                 || mount -t tmpfs run /run -o mode=0755,nosuid,nodev
mountpoint -q /dev                 || mount -t devtmpfs dev /dev -o mode=0755,nosuid
mkdir -p -m0755 /run/runit /run/lvm /run/user /run/lock /run/log /dev/pts /dev/shm
mountpoint -q /dev/pts             || mount -t devpts devpts /dev/pts -o mode=0620,gid=5,nosuid,noexec
mountpoint -q /dev/shm             || mount -t tmpfs shm /dev/shm -o mode=1777,nosuid,nodev
mountpoint -q /sys/kernel/security || mount -n -t securityfs securityfs /sys/kernel/security
mountpoint -q /sys/fs/cgroup       || mount -o mode=0755 -t tmpfs cgroup /sys/fs/cgroup

live="0"
for arg in $(cat /proc/cmdline);do
	case "$arg" in
		live=*)        live="${arg#*=}" ;;
	esac
done

udevd --daemon
udevadm trigger --action=add --type=subsystems
udevadm trigger --action=add --type=devices
udevadm trigger --action=change --type=devices
udevadm settle

mount -o remount,ro /

if [ "$live" != "1" ]; then
	if [ -x /usr/bin/mdadm -o -f /etc/mdadm/mdadm.conf ]; then
		mdadm -As
	fi

	if [ -x /usr/bin/vgchange ]; then
		vgscan --mknodes --ignorelockingfailure >/dev/null 2>&1
		vgchange --sysinit --activate y >/dev/null 2>&1
	fi
fi

if [ "$live" != "1" ]; then
	if [ -f /forcefsck ]; then
		FORCEFSCK="-f"
	fi

	fsck $FORCEFSCK -A -T -C -a
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
		sulogin -p
		halt -r
	fi
fi

mount -o remount,rw /

if [ "$live" != "1" ]; then
	swapon -a
	mount -a -t "nosysfs,nonfs,nonfs4,nosmbfs,nocifs" -O no_netdev
fi

[ -f /etc/random-seed ] && cat /etc/random-seed >/dev/urandom
dd if=/dev/urandom of=/etc/random-seed count=1 bs=512 2>/dev/null

if [ -n "$hostname" ] ;then
	hostname $hostname
fi

ifup -a

if [ -n "$timezone" ] ;then
	ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
	export TZ=/etc/localtime
else
	export TZ=UTC
fi

hwclock --hctosys

sysctl -qp /etc/sysctl.d/*.conf

: > /run/utmp
rm -rf /forcefsck /fastboot /etc/nologin /etc/shutdownpid
(cd /run && /usr/bin/find . -name "*.pid" -delete)
(cd /run/lock && /usr/bin/find . ! -type d -delete)
(cd /tmp && /usr/bin/find . ! -name . -delete)
mkdir -m 1777 /tmp/.ICE-unix

dmesg >/var/log/dmesg.log

if [ -n "$keymap" ] ;then
	loadkeys $keymap
fi

if [ -n "$fontname" ] ;then
	setfont $fontname
fi

if [ "$IPTABLES" = "yes" ]; then
	/etc/rc.d/rc.iptables start
fi

if [ "$IP6TABLES" = "yes" ]; then
	/etc/rc.d/rc.ip6tables start
fi

if [ "$NFTABLES" = "yes" ]; then
	/etc/rc.d/rc.nftables start
fi

if [ "$IPSET" = "yes" ]; then
	/etc/rc.d/rc.ipset start
fi

if [ "$ALSA" = "yes" ]; then
	/etc/rc.d/rc.alsa start
fi

if [ -x /etc/rc.local ]; then
	/etc/rc.local
fi
