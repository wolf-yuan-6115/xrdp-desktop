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

ENV container docker

RUN sed -i 's/# deb/deb/g' /etc/apt/sources.list

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME="user"
ARG PASSWORD="pwd"

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
  rm /xrdp.deb 

# Setup systemctl
RUN apt-get install -y systemd systemd-sysv && \
  cd /lib/systemd/system/sysinit.target.wants/ && \
  ls | grep -v systemd-tmpfiles-setup | xargs rm -f $1 && \
  rm -f /lib/systemd/system/multi-user.target.wants/* && \
  rm -f /etc/systemd/system/*.wants/* && \
  rm -f /lib/systemd/system/local-fs.target.wants/* && \
  rm -f /lib/systemd/system/sockets.target.wants/*udev* && \
  rm -f /lib/systemd/system/sockets.target.wants/*initctl* && \
  rm -f /lib/systemd/system/basic.target.wants/* && \
  rm -f /lib/systemd/system/anaconda.target.wants/* && \
  rm -f /lib/systemd/system/plymouth* && \
  rm -f /lib/systemd/system/systemd-update-utmp* && \
  cd ~
# Install desktop & configure User
RUN apt install --no-install-recommends -y dolphin \
  firefox \
  kate \
  kmix \
  konsole \
  kubuntu-desktop && \
  mkdir -p /var/run/dbus && \
  chown messagebus:messagebus /var/run/dbus && \
  dbus-uuidgen --ensure && \
  groupadd --gid 1000 "$USERNAME" && \
  D_PASSWORD=$(openssl passwd -1 -salt ADUODeAy $PASSWORD) && \
  useradd --uid 1000 --gid 1000 --groups video -ms /bin/bash $USERNAME && \
  echo "$USERNAME:$D_PASSWORD" | chpasswd -e && \
  echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/default

COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

ENV KDE_FULL_SESSION=true
ENV SHELL=/bin/bash
ENV XDG_RUNTIME_DIR=/run/neon

VOLUME [ "/sys/fs/cgroup" ]

CMD ["/lib/systemd/systemd"]