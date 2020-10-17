#!/bin/bash

#########################################
##        ENVIRONMENTAL CONFIG         ##
#########################################

# Configure user squeezeboxserver
export DEBIAN_FRONTEND="noninteractive"
useradd squeezeboxserver
usermod -u 99 squeezeboxserver
usermod -g 100 squeezeboxserver
usermod -d /home squeezeboxserver
chown -R squeezeboxserver:users /home

#########################################
##  FILES, SERVICES AND CONFIGURATION  ##
#########################################

# Allow acces to /dev/snd
usermod -a -G audio squeezeboxserver

#########################################
##             INSTALLATION            ##
#########################################

# Install LMS
OUT=$(curl -skL "http://downloads.slimdevices.com/nightly/index.php?ver=8.0")

# Check architecture
MACHINE_TYPE=`uname -m`
#X64
if [ ${MACHINE_TYPE} == 'x86_64' ]; then
  # Try to catch the link or die
  REGEX=".*href=\".(.*)amd64.deb\""
  if [[ ${OUT} =~ ${REGEX} ]]; then
    URL="http://downloads.slimdevices.com/nightly${BASH_REMATCH[1]}amd64.deb"
  else
    exit 1
  fi
#X86
elif [ ${MACHINE_TYPE} == 'i386' -o ${MACHINE_TYPE} == 'i686']; then
  # Try to catch the link or die
  REGEX=".*href=\".(.*)i386.deb\""
  if [[ ${OUT} =~ ${REGEX} ]]; then
    URL="http://downloads.slimdevices.com/nightly${BASH_REMATCH[1]}i386.deb"
  else
    exit 1
  fi
#ARM
else
  # Try to catch the link or die
  REGEX=".*href=\".(.*)arm.deb\""
  if [[ ${OUT} =~ ${REGEX} ]]; then
    URL="http://downloads.slimdevices.com/nightly${BASH_REMATCH[1]}arm.deb"
  else
    exit 1
  fi
fi

curl -skL -o /tmp/lms.deb $URL
dpkg -i /tmp/lms.deb
rm /tmp/lms.deb