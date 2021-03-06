FROM ubuntu:22.04 AS builder

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

SHELL [ "bash", "-c" ]

RUN \
  echo "== Build XRDP ==" && \
  cd /tmp && \
  apt-get source xrdp && \
  cd xrdp-* && \
  sed -i 's/--enable-fuse/--disable-fuse/g' debian/rules && \
  debuild -b -uc -us && \
  mkdir /buildout && \
  cp -ax ../xrdp_*.deb /buildout/xrdp.deb

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
  meson --prefix="$tmp/pulseaudio-$pulseaudio_upstream_version" build && \
  ninja -C build install && \
  cd - && \
  git clone https://github.com/neutrinolabs/pulseaudio-module-xrdp.git && \
  cd pulseaudio-module-xrdp && \
  ./bootstrap && \
  ./configure PULSE_DIR="$tmp/pulseaudio-$pulseaudio_upstream_version" && \
  make && \
  install -t "/buildout/var/lib/xrdp-pulseaudio-installer" -D -m 644 src/.libs/*.so

FROM docker:20.10.16 AS docker

FROM ubuntu:22.04

ENV container docker

RUN sed -i 's/# deb/deb/g' /etc/apt/sources.list

ARG DEBIAN_FRONTEND=noninteractive
ARG USERNAME="user"
ARG PASSWORD="pwd"

COPY --from=builder /buildout/ /
COPY --from=docker /usr/local/bin/docker /usr/local/bin/

RUN apt-get update && \
  apt-get install -y ubuntu-standard ubuntu-minimal gnupg && \
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
# Install desktop
RUN apt install -y kde-full

# Setup firefox
RUN add-apt-repository ppa:mozillateam/ppa && \
  echo 'Package: *' > /etc/apt/preferences.d/firefox && \
  echo 'Pin: release o=Debian,a=stable' >> /etc/apt/preferences.d/firefox && \
  echo 'Pin-Priority: -1' >> /etc/apt/preferences.d/firefox && \
  apt update && \
  apt install -y firefox

# Setup container
RUN groupadd --gid 1000 "$USERNAME" && \
  D_PASSWORD=$(openssl passwd -1 -salt ADUODeAy $PASSWORD) && \
  useradd --uid 1000 --gid 1000 --groups video -ms /bin/bash $USERNAME && \
  echo "$USERNAME:$D_PASSWORD" | chpasswd -e && \
  echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/default && \
  groupadd docker && \
  usermod -aG docker ${USERNAME} && \
  systemctl enable xrdp && \
  sed  '/exit 1/i pulseaudio --start &' /etc/xrdp/startwm.sh > /etc/xrdp/startwm.sh

ENV KDE_FULL_SESSION=true
ENV SHELL=/bin/bashte
ENV XDG_RUNTIME_DIR=/run/neon

VOLUME [ "/sys/fs/cgroup" ]

STOPSIGNAL SIGRTMIN+3

CMD ["/lib/systemd/systemd"]
