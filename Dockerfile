FROM ubuntu:20.04 AS builder

ARG XRDP_PULSE_VERSION=v0.4
ARG DEBIAN_FRONTEND=noninteractive

RUN \
  echo "== Get packages ==" && \
  sed -i 's/# deb-src/deb-src/g' /etc/apt/sources.list && \
  apt-get update && \
  apt-get install -y \
  build-essential \
  devscripts \
  dpkg-dev \
  git \
  libpulse-dev \
  pulseaudio && \
  apt build-dep -y \
  pulseaudio \
  xrdp

RUN \
  echo "== Build pulseaudio ==" && \
  mkdir -p /buildout/var/lib/xrdp-pulseaudio-installer && \
  tmp=$(mktemp -d); cd "$tmp" && \
  pulseaudio_version=$(dpkg-query -W -f='${source:Version}' pulseaudio|awk -F: '{print $2}') && \
  pulseaudio_upstream_version=$(dpkg-query -W -f='${source:Upstream-Version}' pulseaudio) && \
  set -- $(apt-cache policy pulseaudio | fgrep -A1 '***' | tail -1) && \
  mirror=$2 && \
  suite=${3#*/} && \
  dget -u "$mirror/pool/$suite/p/pulseaudio/pulseaudio_$pulseaudio_version.dsc" && \
  cd "pulseaudio-$pulseaudio_upstream_version" && \
  ./configure && \
  cd - && \
  git clone https://github.com/neutrinolabs/pulseaudio-module-xrdp.git && \
  cd pulseaudio-module-xrdp && \
  git checkout ${XRDP_PULSE_VERSION} && \
  ./bootstrap && \
  ./configure PULSE_DIR="$tmp/pulseaudio-$pulseaudio_upstream_version" && \
  make && \
  install -t "/buildout/var/lib/xrdp-pulseaudio-installer" -D -m 644 src/.libs/*.so

RUN \
  echo "== Build XRDP ==" && \
  cd /tmp && \
  apt-get source xrdp && \
  cd xrdp-* && \
  sed -i 's/--enable-fuse/--disable-fuse/g' debian/rules && \
  debuild -b -uc -us && \
  cp -ax ../xrdp_*.deb /buildout/xrdp.deb

FROM docker:20.10.16 AS docker

FROM ubuntu:20.04

RUN sed -i 's/# deb/deb/g' /etc/apt/sources.list
ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME="user"
ARG PASSWORD="pwd"

# === Setup docker image ===
# Copied from LinuxServer source code
RUN \
  echo "**** Ripped from Ubuntu Docker Logic ****" && \
  set -xe && \
  echo '#!/bin/sh' \
  > /usr/sbin/policy-rc.d && \
  echo 'exit 101' \
  >> /usr/sbin/policy-rc.d && \
  chmod +x \
  /usr/sbin/policy-rc.d && \
  dpkg-divert --local --rename --add /sbin/initctl && \
  cp -a \
  /usr/sbin/policy-rc.d \
  /sbin/initctl && \
  sed -i \
  's/^exit.*/exit 0/' \
  /sbin/initctl && \
  echo 'force-unsafe-io' \
  > /etc/dpkg/dpkg.cfg.d/docker-apt-speedup && \
  echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
  > /etc/apt/apt.conf.d/docker-clean && \
  echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
  >> /etc/apt/apt.conf.d/docker-clean && \
  echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' \
  >> /etc/apt/apt.conf.d/docker-clean && \
  echo 'Acquire::Languages "none";' \
  > /etc/apt/apt.conf.d/docker-no-languages && \
  echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' \
  > /etc/apt/apt.conf.d/docker-gzip-indexes && \
  echo 'Apt::AutoRemove::SuggestsImportant "false";' \
  > /etc/apt/apt.conf.d/docker-autoremove-suggests && \
  mkdir -p /run/systemd && \
  echo 'docker' \
  > /run/systemd/container && \
  echo "**** install apt-utils and locales ****" && \
  apt-get update && \
  apt-get install -y \
  apt-utils \
  locales && \
  echo "**** install packages ****" && \
  apt-get install -y \
  curl \
  patch \
  tzdata && \
  echo "**** generate locale ****" && \
  locale-gen en_US.UTF-8 && \
  echo "**** create user and make our folders ****" && \
  useradd -u 911 -U -d /config -s /bin/false ${USERNAME} && \
  usermod -G users ${USERNAME} && \
  mkdir -p \
  /app \
  /config \
  /defaults && \
  echo "**** cleanup ****" && \
  apt-get autoremove && \
  apt-get clean && \
  rm -rf \
  /tmp/* \
  /var/lib/apt/lists/* \
  /var/tmp/*

ENV container docker

COPY --from=builder /buildout/ /
COPY --from=docker /usr/local/bin/docker /usr/local/bin/

RUN apt-get update && \
  apt-get install -y supervisor ubuntu-standard ubuntu-minimal gnupg && \
  mkdir -p /var/log/supervisor && \
  # installing xrdp & KDE
  echo " == Install packages ==" && \
  ldconfig && \
  apt-get update && \
  DEBIAN_FRONTEND=noninteractive \
  apt-get install -y --no-install-recommends \
  apt-transport-https \
  ca-certificates \
  curl \
  dbus-x11 \
  gawk \
  gnupg2 \
  libfuse2 \
  libx11-dev \
  libxfixes3 \
  libxml2 \
  libxrandr2 \
  openssh-client \
  pulseaudio \
  software-properties-common \
  sudo \
  x11-apps \
  x11-xserver-utils \
  xfonts-base \
  xorgxrdp \
  xrdp \
  xserver-xorg-core \
  xserver-xorg-video-intel \
  xserver-xorg-video-amdgpu \
  xserver-xorg-video-ati \
  xutils \
  zlib1g && \
  dpkg -i /xrdp.deb && \
  rm /xrdp.deb && \
  echo "$USERNAME:$D_PASSWORD" | chpasswd -e && \
  echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/default

# Install desktop & configure User
RUN apt install --no-install-recommends -y dolphin \
  firefox \
  kate \
  kmix \
  konsole \
  kubuntu-desktop && \
  mkdir -p /var/run/dbus && \
  chown messagebus:messagebus /var/run/dbus && \
  dbus-uuidgen --ensure

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

ENV KDE_FULL_SESSION=true
ENV SHELL=/bin/bash
ENV XDG_RUNTIME_DIR=/run/neon

CMD ["/usr/bin/supervisord"]
