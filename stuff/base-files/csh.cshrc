#############################################################################
##
## Gentoo's csh.cshrc
##
## Based on the TCSH package (http://tcshrc.sourceforge.net)
## 
## .tcshrc		2Sep2001, Simos Xenitellis (simos@hellug.gr)
##
## 2003-01-13  --  Alain Penders (alain@gentoo.org)
##     Renamed to /etc/csh.cshrc, basic cleanup work.
##
## 2003-01-24  --  Alain Penders (alain@gentoo.org)
##     Improved config file handling.
##
## 2020-07-04  --  Ishimoto Shinobu (nagakamira@gmail.com)
##     Improved config for Ataraxia Linux.
##
onintr -
##

##
## Load the environment defaults.
##
if ( -r /etc/csh.env ) then
    source /etc/csh.env
endif


##
## Make sure our path includes the basic stuff for root and normal users.
##
set -f path = ( $path /usr/bin )
set -f path = ( $path /usr/games )
set -f path = ( $path /usr/local/bin )


##
## Load our settings -- most are for interactive shells only, but not all.
##
if ( -e /etc/profile.d/tcsh-settings ) then
    source /etc/profile.d/tcsh-settings
endif


##
## Source extensions installed by ebuilds
##
if ( -d /etc/profile.d ) then
  set _tmp=${?nonomatch}
  set nonomatch
  foreach _s ( /etc/profile.d/*.csh )
    if ( -r $_s ) then
      source $_s
    endif
  end
  if ( ! ${_tmp} ) unset nonomatch
  unset _tmp _s
endif


# Everything after this point is interactive shells only.
if ( $?prompt == 0 ) goto end


##
## Load our aliases -- for interactive shells only
##
if ( -e /etc/profile.d/tcsh-aliases ) then
    source /etc/profile.d/tcsh-aliases
endif


##
## Load our key bindings -- for interactive shells only
##
if ( -e /etc/profile.d/tcsh-bindkey ) then
    source /etc/profile.d/tcsh-bindkey
endif


##
## Load our command completions -- for interactive shells only
##
if ( -e /etc/profile.d/tcsh-complete ) then
    source /etc/profile.d/tcsh-complete
endif


end:
##
onintr
##


