FROM guacamole/guacd:1.6.0 AS build
USER root
RUN apk add --no-cache autoconf automake build-base cairo-dev git libjpeg-turbo-dev libpng-dev libtool openssl-dev pango-dev util-linux-dev
WORKDIR /src
RUN git init && git fetch --depth 1 https://github.com/apache/guacamole-server.git 1f664e08feae6e7d15d8146b78acab2e6fb470ae \
    && git checkout --detach FETCH_HEAD
COPY terminal.patch tunnel-cleanup.patch /tmp/
RUN git apply /tmp/terminal.patch /tmp/tunnel-cleanup.patch && autoreconf -fi \
    && ./configure --without-vnc --without-rdp --without-ssh --without-telnet \
        --without-websockets --disable-kubernetes --disable-guacenc --disable-guaclog \
    && make -j2

FROM guacamole/guacd:1.6.0
COPY --from=build /src/src/guacd/.libs/guacd /opt/guacamole/sbin/guacd
COPY --from=build /src/src/terminal/.libs/libguac-terminal.so.2.0.0 /opt/guacamole/lib/
