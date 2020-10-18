#!/bin/bash

#Set user and group
umask 0002
PUID=${PUID:-id -u squeezeboxserver}
PGID=${PGID:-id -g users}

usermod -o -u "$PUID" squeezeboxserver
groupmod -o -g "$PGID" users

umask 0002

#Add permissions
chown -R squeezeboxserver:users /config /music /playlist

#Run supervisor
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf