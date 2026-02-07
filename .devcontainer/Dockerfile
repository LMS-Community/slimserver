FROM mcr.microsoft.com/devcontainers/base:bookworm

# taken from: https://github.com/LMS-Community/slimserver-platforms/blob/public/9.1/Docker/Dockerfile

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL="C.UTF-8" LANG="en_US.UTF-8" LANGUAGE="en_US.UTF-8"


# Install packages
RUN sudo apt-get update -qq  && \
	sudo apt-get install --no-install-recommends -qy procps psmisc wget curl perl tzdata libcrypt-blowfish-perl libwww-perl libfont-freetype-perl liblinux-inotify2-perl \
	libdata-dump-perl libio-socket-ssl-perl libnet-ssleay-perl libcrypt-ssleay-perl libcrypt-openssl-rsa-perl libssl-dev libgomp1 libasound2 lame opus-tools && \
	sudo apt-get clean -qy && \
	sudo rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
