#!/bin/bash

#########################################
##        ENVIRONMENTAL CONFIG         ##
#########################################

# Configure user nobody
export DEBIAN_FRONTEND="noninteractive"
usermod -u 99 nobody
usermod -g 100 nobody
usermod -d /home nobody
chown -R nobody:users /home

# Disable SSH, Syslog and Cron
rm -rf /etc/service/sshd /etc/service/cron /etc/service/syslog-ng /etc/my_init.d/00_regen_ssh_host_keys.sh

#########################################
##  FILES, SERVICES AND CONFIGURATION  ##
#########################################
# LMS
mkdir -p /etc/service/logitechmediaserver
cat <<'EOT' > /etc/service/logitechmediaserver/run
#!/bin/bash
chown -R nobody:users /config
squeezeboxserver --user nobody  --prefsdir /config/prefs --logdir /config/logs --cachedir /config/cache
EOT

chmod -R +x /etc/service/ /etc/my_init.d/

# Allow acces to /dev/snd
usermod -a -G audio nobody

#########################################
##             INSTALLATION            ##
#########################################

# Install LMS
OUT=$(curl -skL "http://downloads.slimdevices.com/nightly/index.php?ver=8.0")
# Try to catch the link or die
REGEX=".*href=\".(.*)amd64.deb\""
if [[ ${OUT} =~ ${REGEX} ]]; then
  URL="http://downloads.slimdevices.com/nightly${BASH_REMATCH[1]}amd64.deb"
else
  exit 1
fi

curl -skL -o /tmp/lms.deb $URL
dpkg -i /tmp/lms.deb
rm /tmp/lms.deb


/etc/init.d/avahi-daemon restart
#########################################
##                 CLEANUP             ##
#########################################

# Clean APT install files
apt-get clean -y
rm -rf /var/lib/apt/lists/* /var/cache/* /var/tmp/*
