FROM debian:stable-slim

#########################################
##        ENVIRONMENTAL CONFIG         ##
#########################################

# Set correct environment variables
ENV DEBIAN_FRONTEND noninteractive
ENV HOME="/root"

#########################################
##         INSTALL PACKAGES            ##
#########################################

RUN apt-get update  && \
apt-get install -y wget perl tzdata pv libwww-perl avahi-utils libio-socket-ssl-perl libnet-ssleay-perl curl supervisor && \
apt-get clean -qy && \
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add start script
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf

#########################################
##         RUN INSTALL SCRIPT          ##
#########################################

COPY install.sh /tmp/
RUN chmod +x /tmp/install.sh
RUN /tmp/install.sh

RUN mkdir -p /config /var/log/supervisor

RUN mkdir /music && \
  chown -R squeezeboxserver:users /config /music
 
#########################################
##         EXPORTS AND VOLUMES         ##
#########################################
VOLUME /config /music
WORKDIR /config

USER squeezeboxserver

EXPOSE 3483 3483/udp 9000 9090 5353/udp 9005 38863 46960

#########################################
##       	    SUPERVISOR 	           ##
#########################################
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/supervisord.conf"]