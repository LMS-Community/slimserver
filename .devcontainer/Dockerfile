FROM mcr.microsoft.com/devcontainers/base:trixie

# Taken from: https://github.com/LMS-Community/slimserver-platforms/blob/public/9.2/Docker/Dockerfile

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL="C.UTF-8" LANG="en_US.UTF-8" LANGUAGE="en_US.UTF-8"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -qy \
# Install Lyrion packages
      procps psmisc wget curl perl tzdata libcrypt-blowfish-perl libwww-perl libfont-freetype-perl liblinux-inotify2-perl \
      libdata-dump-perl libio-socket-ssl-perl libnet-ssleay-perl libcrypt-ssleay-perl libcrypt-openssl-rsa-perl libssl-dev libgomp1 libasound2 lame opus-tools \
# Install Perl Language Server packages
      cpanminus \
      libanyevent-perl libclass-refresh-perl libcompiler-lexer-perl libdata-dump-perl libio-aio-perl libjson-perl libmoose-perl libpadwalker-perl \
      libscalar-list-utils-perl libcoro-perl && \
    apt-get clean -qy && \
    rm -rf /var/lib/apt/lists/*

# Install Perl::LanguageServer (for "richterger.perl" VS Code extension)
RUN cpanm --notest --quiet Perl::LanguageServer
