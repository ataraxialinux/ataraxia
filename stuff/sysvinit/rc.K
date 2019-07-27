#!/bin/bash
#
# rc.K 		This file is executed by init when it goes into runlevel
#		1, which is the administrative state. It kills all
#		daemons and then puts the system into single user mode.
#		Note that the file systems are kept mounted.
#
# Version:	@(#)/etc/rc.d/rc.K	3.1415 Sat Jan 13 13:37:26 PST 2001
#
# Author:	Miquel van Smoorenburg <miquels@drinkel.nl.mugnet.org>
# Modified by:	Patrick J. Volkerding <volkerdi@slackware.com>
# Modified by:	Damian Rakowski <maestromae@o2.pl>
# Modified by:	protonesso <ataraxialinux@protonmail.ch>
#

# Set the path.
export PATH="/usr/local/games:/usr/local/sbin:/usr/local/bin:/usr/games:/usr/bin"
source /etc/rc.d/functions.sh

# Try to turn off quota:
if fgrep quota /etc/fstab 1> /dev/null 2> /dev/null ; then
	if [ -x /sbin/quotaoff ]; then
		msg="Turning off filesystem quotas"
		status quotaoff -a
	fi
fi

msg="Unmounting remote filesystems:"
status umount -v -a -l -f -r -t nfs,smbfs,cifs

# Kill all processes.
msg="Sending all processes the SIGTERM signal"
status killall5 -15
msg="Waiting processes to terminate"
stat_busy

sleep 1

stat_ok

msg="Sending all processes the SIGKILL signal"
status killall5 -9
msg="Waiting processes to exit"
stat_busy

sleep 1

stat_ok

# Now go to the single user level
einfo "Going to single user mode..."
telinit -t 1 1
