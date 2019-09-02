#!/bin/bash
#
# /etc/rc.d/rc.boot:	System initialization script.
#

. /etc/rc.conf

dmesg -n 1

mountpoint -q /proc                || mount -t proc proc /proc -o nosuid,noexec,nodev
mountpoint -q /sys                 || mount -t sysfs sys /sys -o nosuid,noexec,nodev
mountpoint -q /run                 || mount -t tmpfs run /run -o mode=0755,nosuid,nodev
mountpoint -q /dev                 || mount -t devtmpfs dev /dev -o mode=0755,nosuid
mkdir -p -m0755 /run/lvm /run/user /run/lock /run/log /dev/pts /dev/shm
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

	if [ -r /etc/lvmtab -o -d /etc/lvm/backup ]; then
		vgscan --mknodes --ignorelockingfailure 2> /dev/null
		if [ $? = 0 ]; then
			vgchange -ay --ignorelockingfailure
		fi
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

if ! grep -wq nofsck /proc/cmdline; then
	if [ -r /etc/forcefsck ]; then
		FORCEFSCK="-f"
	fi
	RETVAL=0
	if [ ! -r /etc/fastboot ]; then
		fsck $FORCEFSCK -C -a /
		RETVAL=$?
	fi
	if [ $RETVAL -ge 2 ]; then
			if [ $RETVAL -ge 4 ]; then
				echo
				echo "***********************************************************"
				echo "*** An error occurred during the root filesystem check. ***"
				echo "*** You will now be given a chance to log into the      ***"
				echo "*** system in single-user mode to fix the problem.      ***"
				echo "***                                                     ***"
				echo "***********************************************************"
				echo
				echo "Once you exit the single-user shell, the system will reboot."
				echo
				PS1="(Repair filesystem) \# "; export PS1
				sulogin
			else
				echo
				echo "***********************************"
				echo "*** The filesystem was changed. ***"
				echo "*** The system will now reboot. ***"
				echo "***********************************"
				echo
			fi
			umount -a -r
			mount -n -o remount,ro /
			reboot -f
	fi
fi

if ! grep -wq nofsck /proc/cmdline; then
	if [ ! -r /etc/fastboot ]; then
		fsck $FORCEFSCK -C -R -A -a
	fi
fi

if grep -wq rw /proc/cmdline ; then
	mount -o remount,rw /
fi

mount -a -t nonfs,nonfs4,nosmbfs,nocifs -O no_netdev  &>/dev/null

swapon -a

if [ -n "$hostname" ] ;then
	hostname $hostname
fi

if ! grep -wq nonet /proc/cmdline; then
	ifup -a
fi

if [ -n "$timezone" ] ;then
	ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
	export TZ=/etc/localtime
else
	export TZ=UTC
fi

hwclock --hctosys

sysctl -qp /etc/sysctl.d/*.conf

rm -f /run/* /run/*pid /etc/nologin /run/lpd* \
	/run/ppp* /etc/forcefsck /etc/fastboot /tmp/.Xauth* &>/dev/null
( cd /tmp && rm -rf kde-[a-zA-Z]* ksocket-[a-zA-Z]* hsperfdata_[a-zA-Z]* plugtmp* &>/dev/null )

if [ ! -e /tmp/.ICE-unix ]; then
	mkdir -p /tmp/.ICE-unix
	chmod 1777 /tmp/.ICE-unix
fi
if [ ! -e /tmp/.X11-unix ]; then
	mkdir -p /tmp/.X11-unix
	chmod 1777 /tmp/.X11-unix
fi

cat /dev/null > /run/utmp

if [ -f /etc/random-seed ]; then
	cat /etc/random-seed > /dev/urandom
fi
if [ -r /proc/sys/kernel/random/poolsize ]; then
	dd if=/dev/urandom of=/etc/random-seed count=1 bs=$(cat /proc/sys/kernel/random/poolsize) 2> /dev/null
else
	dd if=/dev/urandom of=/etc/random-seed count=1 bs=512 2> /dev/null
fi
chmod 600 /etc/random-seed

dmesg > /var/log/dmesg.log
chmod 600 /var/log/dmesg.log

if [ "$single" = "1" ]; then
	setsid cttyhack /usr/bin/mksh
	reboot -f
fi
