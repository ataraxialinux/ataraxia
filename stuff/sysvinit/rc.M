#!/bin/bash
#
# rc.M		This file is executed by init(8) when the system is being
#		initialized for one of the "multi user" run levels (i.e.
#		levels 1 through 6).	It usually does mounting of file
#		systems et al.
#
# Version:	@(#)/etc/rc.d/rc.M	2.23	Wed Feb 26 19:20:58 PST 2003
#
# Author:	Fred N. van Kempen, <waltje@uwalt.nl.mugnet.org>
#		Heavily modified by Patrick Volkerding <volkerdi@slackware.com>
#		Modified by:	Damian Rakowski <maestromae@o2.pl>
#		Modified by:	protonesso <ataraxialinux@protonmail.ch>
#	


export PATH="/usr/local/games:/usr/local/sbin:/usr/local/bin:/usr/games:/usr/bin"
source /etc/rc.d/functions.sh

# Tell the viewers what's going to happen.
echo -e	"\033[1;37mGoing multiuser... \033[0m"

if [ -f "/etc/hostname" ]; then
	HOSTNAME="$(cat /etc/hostname)"
else
	HOSTNAME="$(cat /proc/sys/kernel/hostname)"
fi

# Set the hostname.
msg="Setting hostname to $HOSTNAME"
status hostname $HOSTNAME

msg="Starting networking"
status ifup -a

# Remove stale locks and junk files (must be done after mount -a!)
msg="Removing stale locks and junk files"
rm -rf /run/lock/* /var/spool/uucp/LCK..* /tmp/.X*lock
stat_ok

# Check quotas and then turn quota system on:
if fgrep quota /etc/fstab 1> /dev/null 2> /dev/null ; then
	if [ -x /sbin/quotacheck ]; then
		 msg="Checking filesystem quotas"
		 status quotacheck -avugm
	fi
	if [ -x /sbin/quotaon ]; then
		 msg="Activating filesystem quotas"
		 status quotaon -avug
	fi
fi

# Start the local setup procedure.
if [ -x /etc/rc.d/rc.local ]; then
	/etc/rc.d/rc.local
fi
