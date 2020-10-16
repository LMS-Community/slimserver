# docker-logitechmediaserver

Docker image for Logitech Media Server (SqueezeCenter, SqueezeboxServer, SlimServer)

Also with airplay function!

Run with:

```
docker run -t -i --rm=true --net="bridge" \
      -v "/mnt/user/appdata/LogitechMediaServer":"/config":rw \
      -v "/mnt/music":"/music":ro \
      -v "/var/run/dbus":"/var/run/dbus":rw \
      -v "/etc/localtime":"/etc/localtime":ro \
      -p 9000:9000/tcp \
      -p 9090:9090/tcp \
      -p 3483:3483/tcp \
      -p 3483:3483/udp \
      -p 5353:5353/tcp \
      -p 5353:5353/udp \
      Logitech/slimserver
```

or compose
```
version: '3'
services:
  lms:
    container_name: lms
    image: Logitech/slimserver
    volumes:
      - /etc/localtime:/etc/localtime:ro
      - /<somewhere>:/config:rw
      - /<somewhere else>:/music:ro
      - /var/run/dbus:/var/run/dbus:rw
    ports:
      - 9000:9000/tcp
      - 9090:9090/tcp
      - 3483:3483/tcp
      - 3483:3483/udp
      - 5353:5353/tcp
      - 5353:5353/udp
    restart: always
```
