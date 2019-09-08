#!/bin/bash
#
# System startup script
#

 . /etc/rc.conf

dmesg -n 1

mountpoint -q /proc                || mount -t proc proc /proc -o nosuid,noexec,nodev
mountpoint -q /sys                 || mount -t sysfs sys /sys -o nosuid,noexec,nodev
mountpoint -q /run                 || mount -t tmpfs run /run -o mode=0755,nosuid,nodev
mountpoint -q /dev                 || mount -t devtmpfs dev /dev -o mode=0755,nosuid
mkdir -p -m0755 /run/services /run/lvm /run/user /run/lock /run/log /dev/pts /dev/shm
mountpoint -q /dev/pts             || mount -t devpts devpts /dev/pts -o mode=0620,gid=5,nosuid,noexec
mountpoint -q /dev/shm             || mount -t tmpfs shm /dev/shm -o mode=1777,nosuid,nodev
mountpoint -q /sys/kernel/security || mount -n -t securityfs securityfs /sys/kernel/security
mountpoint -q /sys/fs/cgroup       || mount -o mode=0755 -t tmpfs cgroup /sys/fs/cgroup

live="0"
single="0"
for arg in $(cat /proc/cmdline);do
	case "$arg" in
		live=*)        live="${arg#*=}" ;;
		single=*)      single="${arg#*=}" ;;
		timezone=*)    timezone="${arg#*=}" ;;
		hostname=*)    hostname="${arg#*=}" ;;
	esac
done

if [ -x /usr/bin/udevd ]; then
	udevd --daemon
	udevadm trigger --action=add --type=subsystems
	udevadm trigger --action=add --type=devices
	udevadm trigger --action=change --type=devices
	udevadm settle
fi

mount -o remount,ro /

if [ "$live" != "1" ]; then
	if [ -x /usr/bin/mdadm -o -f /etc/mdadm/mdadm.conf ]; then
		mdadm -As
	fi

	if [ -x /usr/bin/vgchange ]; then
		vgscan --mknodes --ignorelockingfailure >/dev/null 2>&1
		vgchange --sysinit --activate y >/dev/null 2>&1
	fi

	if [ -f /etc/crypttab -a -x /usr/bin/cryptsetup ]; then
		cat /etc/crypttab | grep -v "^#" | grep -v "^$" | while read line; do
			eval LUKSARRAY=( $line )
			LUKS="${LUKSARRAY[0]}"
			DEV="${LUKSARRAY[1]}"
			PASS="${LUKSARRAY[2]}"
			OPTS="${LUKSARRAY[3]}"
			LUKSOPTS=""
			if echo $OPTS | grep -wq ro ; then LUKSOPTS="${LUKSOPTS} --readonly" ; fi
			if echo $OPTS | grep -wq discard ; then LUKSOPTS="${LUKSOPTS} --allow-discards" ; fi
			cryptsetup $LUKS 2>/dev/null | head -n 1 | grep -q "is active" && continue
			if cryptsetup isLuks $DEV 2>/dev/null ; then
				if [ -n "${PASS}" -a "${PASS}" != "none" ]; then
					if [ -f "${PASS}" ]; then
						cryptsetup ${LUKSOPTS} --key-file=${PASS} luksOpen $DEV $LUKS
					else
						echo "${PASS}" | cryptsetup ${LUKSOPTS} luksOpen $DEV $LUKS
					fi
				else
					cryptsetup ${LUKSOPTS} luksOpen $DEV $LUKS </dev/tty0 >/dev/tty0 2>&1
				fi
			elif echo $OPTS | grep -wq swap ; then
				cryptsetup --cipher=aes --key-file=/dev/urandom --key-size=256 create $LUKS $DEV
				mkswap /dev/mapper/$LUKS
			fi
		done
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
		setsid cttyhack /usr/bin/mksh
		if [ "$live" != "1" ]; then
			umount -a -r
			mount -o remount,ro /
		fi
		reboot -f
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

if [ ! -e /tmp/.ICE-unix ]; then
	mkdir -p /tmp/.ICE-unix
	chmod 1777 /tmp/.ICE-unix
fi
if [ ! -e /tmp/.X11-unix ]; then
	mkdir -p /tmp/.X11-unix
	chmod 1777 /tmp/.X11-unix
fi

cat /dev/null > /run/utmp

dmesg > /var/log/dmesg.log
chmod 600 /var/log/dmesg.log

if [ "$single" = "1" ]; then
	setsid cttyhack /usr/bin/mksh
	if [ "$live" != "1" ]; then
		umount -a -r
		mount -o remount,ro /
	fi
	reboot -f
fi
