#Base image
FROM debian:9-slim

# Set environment variables
ENV DEBIAN_FRONTEND noninteractive
ENV HOME="/root"

# Install packages
RUN apt-get update -qq  && \
apt-get install -qy wget curl perl tzdata libwww-perl libio-socket-ssl-perl libnet-ssleay-perl supervisor && \
apt-get clean -qy && \
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Add supervisor script
COPY supervisor/supervisord.conf /etc/supervisor/supervisord.conf

# Add startup script
COPY start-container.sh /usr/bin/start-container
RUN chmod +x /usr/bin/start-container

# Add & install LMS sript
COPY install.sh /tmp/
RUN chmod +x /tmp/install.sh
RUN /tmp/install.sh

# Volume and port setup
RUN mkdir -p /config /music /playlist /var/log/supervisor

VOLUME /config /music /playlist

EXPOSE 3483 3483/udp 9000 9090 5353/udp 9005 38863 46960

#Startup setup
WORKDIR /config

ENTRYPOINT ["start-container"]