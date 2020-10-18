# docker-logitechmediaserver

Docker image for Logitech Media Server

Run with:

```
docker run -t -i --rm=true --net="bridge" \
      -v "<somewhere>":"/config":rw \
      -v "<somewhere>":"/music":ro \
      -v "<somewhere>":"/playlist":ro \
      -v "/var/run/dbus":"/var/run/dbus":rw \
      -v "/etc/localtime":"/etc/localtime":ro \
      -p 9000:9000/tcp \
      -p 9090:9090/tcp \
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
      - /<somewhere>:/music:ro
      - /<somewhere>:/playlist:ro
      - /var/run/dbus:/var/run/dbus:rw
    ports:
      - 9000:9000/tcp
      - 9090:9090/tcp
    restart: always
```
