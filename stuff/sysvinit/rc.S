#!/bin/bash
#
# /etc/rc.d/rc.S:	System initialization script.
#
# Mostly written by:	Patrick J. Volkerding, <volkerdi@slackware.com>
# Modified by:          Damian Rakowski <maestromae@o2.pl>
# Modified by:          protonesso <ataraxialinux@protonmail.ch>
#

export PATH="/usr/local/games:/usr/local/sbin:/usr/local/bin:/usr/games:/usr/bin"
source /etc/rc.d/functions.sh

dmesg -n 1

# Try to mount /proc
msg="Mounting /proc filesystem" 
status mount proc -n -t proc /proc

# Mount sysfs next, if the kernel supports it:
msg="Mounting /sys filesystem"
status mount sysfs /sys -n -t sysfs

# Mount a tmpfs on /run
msg="Mounting /run filesystem"
status mount -n -t tmpfs tmpfs /run -o mode=0755,nosuid,nodev

# Start udev if exist
if [ -x /usr/bin/udevd ]; then
	mountpoint -q /dev || mount -t devtmpfs dev /dev -o mode=0755,nosuid

	mkdir -p /dev/pts /dev/shm

	mount -t devpts devpts /dev/pts -o mode=0620,gid=5,nosuid,noexec
	mount -t tmpfs shm /dev/shm -o mode=1777,nosuid,nodev

	msg="Initializing udev dynamic device directory"
	stat_busy

	udevd --daemon
	udevadm trigger --action=add --type=subsystems
	udevadm trigger --action=add --type=devices
	udevadm trigger --action=change --type=devices
	udevadm settle
	stat_ok
fi

# Mount read-only
msg="Remounting root device with read-only enabled"
status mount -o remount,ro /

# Mount Control Groups filesystem interface:
if grep -wq cgroup /proc/filesystems ; then
	if [ -d /sys/fs/cgroup ]; then
		# See linux-*/Documentation/cgroups/cgroups.txt (section 1.6)
		# Check if we have some tools to autodetect the available cgroup controllers
		if [ -x /bin/cut -a -x /bin/tail ]; then
			msg="Mounting control groups filesystem interface" 
			stat_busy

			# Mount a tmpfs as the cgroup filesystem root
			mount -t tmpfs -o mode=0755 cgroup_root /sys/fs/cgroup
			# Autodetect available controllers and mount them in subfolders
			controllers="$(/bin/cut -f 1 /proc/cgroups | /bin/tail -n +2)"
			for i in $controllers; do
				mkdir /sys/fs/cgroup/$i
				mount -t cgroup -o $i $i /sys/fs/cgroup/$i
			done
			unset i controllers
		else
			msg="Mounting control groups filesystem interface" 
			stat_busy

			# We can't use autodetection so fall back mounting them all together
			mount -t cgroup cgroup /sys/fs/cgroup
		fi
		stat_ok
	else
		msg="Mounting control groups filesystem interface" 
		stat_busy

		mkdir -p /dev/cgroup
		mount -t cgroup cgroup /dev/cgroup
		stat_ok
	fi
fi

# Initialize the Logical Volume Manager.
# This won't start unless we find /etc/lvmtab (LVM1) or
# /etc/lvm/backup/ (LVM2). This is created by /sbin/vgscan, so to
# use LVM you must run /sbin/vgscan yourself the first time (and
# create some VGs and LVs).
# Create LVM lock/run directories:
mkdir -p -m 0700 /run/lvm /run/lock /run/lock/lvm
if [ -r /etc/lvmtab -o -d /etc/lvm/backup ]; then
	msg="Initializing LVM (Logical Volume Manager)"
	# Scan for new volume groups:
	vgscan --mknodes --ignorelockingfailure 2> /dev/null
	if [ $? = 0 ]; then
		# Make volume groups available to the kernel.
		# This should also make logical volumes available.
		vgchange -ay --ignorelockingfailure
		stat_ok
	fi
fi

# Open any volumes created by cryptsetup.
#
# Some notes on /etc/crypttab in Slackware:
# Only LUKS formatted volumes are supported (except for swap)
# crypttab follows the following format:
# <luks_name> <device> <password> <options>
#
# <luks_name>: This is the name of your LUKS volume.
# For example: crypt-home
#
# <device>: This is the device containing your LUKS volume.
# For example: /dev/sda2
#
# <password>: This is either the volume password in plain text, or the name of
# a key file. Use 'none' to interactively enter password on boot.
#
# <options>: Comma-separated list of options. Note that there must be a
# password field for any options to be picked up (use a password of 'none' to
# get a password prompt at boot). The following options are supported:
#
# discard -- this will cause --allow-discards to be passed to the cryptsetup
# program while opening the LUKS volume.
#
# ro -- this will cause --readonly to be passed to the cryptsetup program while
# opening the LUKS volume.
#
# swap -- this option cannot be used with other options. The device given will
# be formatted as a new encrypted volume with a random key on boot, and used as
# swap.
#
if [ -f /etc/crypttab -a -x /usr/bin/cryptsetup ]; then
	# NOTE: we only support LUKS formatted volumes (except for swap)!
	cat /etc/crypttab | grep -v "^#" | grep -v "^$" | while read line; do
		eval LUKSARRAY=( $line )
		LUKS="${LUKSARRAY[0]}"
		DEV="${LUKSARRAY[1]}"
		PASS="${LUKSARRAY[2]}"
		OPTS="${LUKSARRAY[3]}"
		LUKSOPTS=""
		if echo $OPTS | grep -wq ro ; then LUKSOPTS="${LUKSOPTS} --readonly" ; fi
		if echo $OPTS | grep -wq discard ; then LUKSOPTS="${LUKSOPTS} --allow-discards" ; fi
		# Skip LUKS volumes that were already unlocked (in the initrd):
		cryptsetup status $LUKS 2>/dev/null | head -n 1 | grep -q "is active" && continue
		if cryptsetup isLuks $DEV 2>/dev/null ; then
			if [ -z "${LUKSOPTS}" ]; then
				einfo "Unlocking LUKS encrypted volume '${LUKS}' on device '$DEV':"
			else
				einfo "Unlocking LUKS encrypted volume '${LUKS}' on device '$DEV' with options '${LUKSOPTS}':"
			fi
			if [ -n "${PASS}" -a "${PASS}" != "none" ]; then
				if [ -f "${PASS}" ]; then
					# A password was given a key-file filename
					cryptsetup ${LUKSOPTS} --key-file=${PASS} luksOpen $DEV $LUKS
				else
					# A password was provided in plain text
					echo "${PASS}" | cryptsetup ${LUKSOPTS} luksOpen $DEV $LUKS
				fi
			else
				# No password was given, or a password of 'none' was given
				cryptsetup ${LUKSOPTS} luksOpen $DEV $LUKS </dev/tty0 >/dev/tty0 2>&1
			fi
			stat_ok
		elif echo $OPTS | grep -wq swap ; then
			# If any of the volumes is to be used as encrypted swap,
			# then encrypt it using a random key and run mkswap:
			msg="Creating encrypted swap volume '${LUKS}' on device '$DEV':"
			stat_busy

			cryptsetup --cipher=aes --key-file=/dev/urandom --key-size=256 create $LUKS $DEV
			mkswap /dev/mapper/$LUKS
			stat_ok
		fi
	done
fi

if ! grep -wq nofsck /proc/cmdline; then
	# See if a forced filesystem check was requested at shutdown:
	if [ -r /etc/forcefsck ]; then
		FORCEFSCK="-f"
	fi

	# Check the root filesystem:
	RETVAL=0
	if [ ! -r /etc/fastboot ]; then
		einfo "Checking root filesystem:"
		fsck $FORCEFSCK -C -a /
		RETVAL=$?
	fi
	# An error code of 2 or higher will require a reboot.
	if [ $RETVAL -ge 2 ]; then
		# An error code equal to or greater than 4 means that some errors
		# could not be corrected.	This requires manual attention, so we
		# offer a chance to try to fix the problem in single-user mode:
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
			msg="Unmounting file systems."
			stat_busy

			umount -a -r
			mount -n -o remount,ro /
			stat_ok

			einfo "Rebooting system."
			reboot -f
	fi
fi
 
# Check all the non-root filesystems:
if [ ! -r /etc/fastboot ]; then
	msg="Checking non-root filesystems"
	status fsck $FORCEFSCK -C -R -A -a
fi

if grep -wq rw /proc/cmdline ; then
	# Mount read-write if requested
	msg="Remounting root device with read-write enabled"
	status mount -o remount,rw /
fi

# mount non-root file systems in fstab (but not NFS or SMB 
# because TCP/IP is not yet configured):
msg="Mounting non-root filesystems"
stat_busy
mount -a -t nonfs,nonfs4,nosmbfs,nocifs -O no_netdev  &>/dev/null
stat_ok

# enable swapping
msg="Activating swap space"
status swapon -a

if [ -x /sbin/hwclock ]; then
	if grep "^UTC" /etc/hardwareclock 1> /dev/null 2> /dev/null ; then
		msg="Setting system time from the hardware clock (UTC)"
		status hwclock --utc --hctosys
	else
		msg="Setting system time from the hardware clock (localtime)"
		status hwclock --localtime --hctosys
	fi
fi

# Clean up some temporary files:
msg="Cleaning up temporary files"
/bin/rm -f /run/* /run/*pid /etc/nologin /run/lpd* \
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

# Create a fresh utmp file:
cat /dev/null > /run/utmp
stat_ok

# Carry an entropy pool between reboots to improve randomness.
if [ -f /etc/random-seed ]; then
	msg="Using /etc/random-seed to initialize /dev/urandom"
	cat /etc/random-seed > /dev/urandom
	stat_ok
fi
if [ -r /proc/sys/kernel/random/poolsize ]; then
	dd if=/dev/urandom of=/etc/random-seed count=1 bs=$(cat /proc/sys/kernel/random/poolsize) 2> /dev/null
else
	dd if=/dev/urandom of=/etc/random-seed count=1 bs=512 2> /dev/null
fi
chmod 600 /etc/random-seed
