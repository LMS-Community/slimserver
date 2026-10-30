FROM mcr.microsoft.com/devcontainers/base:trixie

# Aligned with https://github.com/LMS-Community/slimserver-platforms/blob/public/9.2/Docker/Dockerfile

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL="C.UTF-8" LANG="en_US.UTF-8" LANGUAGE="en_US.UTF-8"
ENV HTTP_PORT=9000

# Install packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -qy \
    # Lyrion runtime dependencies
        procps psmisc wget curl perl tzdata libcrypt-blowfish-perl libwww-perl libfont-freetype-perl liblinux-inotify2-perl \
        libdata-dump-perl libcrypt-ssleay-perl libcrypt-openssl-rsa-perl libssl-dev libgomp1 libasound2 lame opus-tools \
    # Perl Language Server dependencies (for "richterger.perl" VS Code extension)
        cpanminus \
        libanyevent-perl libclass-refresh-perl libcompiler-lexer-perl libdata-dump-perl libio-aio-perl libjson-perl libmoose-perl libpadwalker-perl \
        libscalar-list-utils-perl libcoro-perl && \
    apt-get clean -qy && \
    rm -rf /var/lib/apt/lists/*

# Volume and port setup
# Permissions allow the non-root Dev Container user (vscode) to write here
# when no host folder is mounted (e.g. GitHub Codespaces).
RUN mkdir -p /music /playlist && \
    chmod 777 /music /playlist

# Install Perl::LanguageServer (for "richterger.perl" VS Code extension)
RUN cpanm --notest --quiet Perl::LanguageServer

# Re-install SSL packages after cpanm: cpanm may pull in or override Net::SSLeay
# with a CPAN version that doesn't work correctly on all platforms (e.g. ARM64).
# Installing via apt after cpanm ensures the distro-compiled packages win.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y libio-socket-ssl-perl libnet-ssleay-perl && \
    apt-get clean -qy && \
    rm -rf /var/lib/apt/lists/*
