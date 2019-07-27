#!/bin/bash

STAT_COL=`stty size | cut -d " " -f 2`
COL_TEXT="\033[1;0m"
COL_OK="\033[1;37m"
COL_KO="\033[1;31m"
COL_NORM="\033[1;0m"
COL_DOT="\033[1;0m"
COL_BUSY="\033[1;37m"

write_dots () {
	for ((i=0; i<$[$1/2]; ++i)); do
		echo -n "  "
	done
 
	if [ $[$1%2] = 1 ]; then
		echo -n " "
	fi
}

deltext () {
	echo -ne "\033[1G"
}

stat_busy () {
	NUM_DOT=$(($STAT_COL-${#msg}-11))
	DOT=`write_dots $NUM_DOT`
	echo -ne "${COL_KO}* ${COL_TEXT}$msg${COL_DOT}$DOT[ BUSY ]\r"
}

stat_ok () {
	deltext 
	NUM_DOT=$(($STAT_COL-${#msg}-9))
	DOT=`write_dots $NUM_DOT`
	echo -ne "${COL_KO}* ${COL_TEXT}$msg${COL_DOT}$DOT[${COL_OK} OK ${COL_DOT}]${COL_NORM}\n"
}

stat_ko () {
	deltext
	NUM_DOT=$(($STAT_COL-${#msg}-9))
	DOT=`write_dots $NUM_DOT`
	echo -ne "${COL_KO}* ${COL_TEXT}$msg${COL_DOT}$DOT[${COL_KO} !! ${COL_DOT}]${COL_NORM}\n"
}

status() {
	stat_busy 
	$* >/dev/null 2>&1
	if [ $? -eq 0 ]; then
		stat_ok
		return 0
	else
	        stat_ko
		return 1
	fi
}
 
 
einfo(){
	echo -e " $COL_KO*${COL_NORM} ${*}"
}
