FROM ubuntu:22.04

ENV container docker

RUN sed -i 's/# deb/deb/g' /etc/apt/sources.list

RUN apt-get update ; \
  apt-get install -y systemd systemd-sysv ; \
  apt-get clean ; \
  rm -rf /tmp/* /var/tmp/* ; \
  cd /lib/systemd/system/sysinit.target.wants/ ; \
  ls | grep -v systemd-tmpfiles-setup | xargs rm -f $1 ; \
  rm -f /lib/systemd/system/multi-user.target.wants/* ; \
  rm -f /etc/systemd/system/*.wants/* ; \
  rm -f /lib/systemd/system/local-fs.target.wants/* ; \
  rm -f /lib/systemd/system/sockets.target.wants/*udev* ; \
  rm -f /lib/systemd/system/sockets.target.wants/*initctl* ; \
  rm -f /lib/systemd/system/basic.target.wants/* ; \
  rm -f /lib/systemd/system/anaconda.target.wants/* ; \
  rm -f /lib/systemd/system/plymouth* ; \
  rm -f /lib/systemd/system/systemd-update-utmp* ; \
  # Prevent system booting into Graphical interface
  systemctl set-default multi-user.target ; \
  # installing xrdp & KDE
  apt install -y kde-plasma-desktop xrdp

VOLUME [ "/sys/fs/cgroup" ]

CMD ["/lib/systemd/systemd"]
