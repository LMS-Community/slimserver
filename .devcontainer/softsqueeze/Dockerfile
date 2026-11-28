FROM debian:trixie-slim

# SoftSqueeze + VNC standalone image
# Connects to LMS running in the Dev Container (or anywhere reachable)

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL="C.UTF-8" LANG="en_US.UTF-8" LANGUAGE="en_US.UTF-8"
ENV DISPLAY=:99

# Install Java, VNC, audio and SoftSqueeze packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -qy \
        curl ca-certificates unzip procps iproute2 \
        default-jre xvfb x11vnc fluxbox novnc websockify xdg-utils \
        pulseaudio pulseaudio-utils libasound2-plugins alsa-utils && \
    mkdir -p /opt/softsqueeze && \
    curl -fsSL https://sourceforge.net/projects/lmsclients/files/softsqueeze/softsqueeze_3.9.3.zip/download -o /tmp/softsqueeze.zip && \
    unzip -q /tmp/softsqueeze.zip -d /opt/softsqueeze && \
    rm /tmp/softsqueeze.zip && \
    apt-get clean -qy && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 5900 6080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
