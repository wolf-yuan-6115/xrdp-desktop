# xrdp-desktop

xRDP desktop with systemctl support.

# Building

```sh
docker build -t xrdp-desktop .
```

# Starting container

```sh
docker run -it --rm \
  --privileged \ # Required for systemd
  --volume /sys/fs/cgroup:/sys/fs/cgroup:ro \ # Required for systemd
  --name xrdp-desktop -p 3389:3389 xrdp-desktop
```
