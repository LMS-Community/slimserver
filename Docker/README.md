# docker-logitechmediaserver

Docker image for Logitech Media Server

Run:

```
docker run -it \
      -v "<somewhere>":"/config":rw \
      -v "<somewhere>":"/music":ro \
      -v "<somewhere>":"/playlist":ro \
      -p 9000:9000/tcp \
      -p 9090:9090/tcp \
      Logitech/slimserver
```

Docker compose:
```
version: '3'
services:
  lms:
    container_name: lms
    image: Logitech/slimserver
    volumes:
      - /<somewhere>:/config:rw
      - /<somewhere>:/music:ro
      - /<somewhere>:/playlist:ro
    ports:
      - 9000:9000/tcp
      - 9090:9090/tcp
    restart: always
```

Alternatively you can specify the user and group id to use:
For run add:
```
  -e PUID=1000 \
  -e PGID=1000
 ```
For compose add:
```
environment:
  - PUID=1000
  - PGID=1000
 ```