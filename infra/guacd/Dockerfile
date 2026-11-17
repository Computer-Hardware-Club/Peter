ARG GUACD_BASE=guacamole/guacd:1.6.0@sha256:8974eaa9ba32f713daf311e7cc8cd7e4cdfba1edea39eed75524e78ef4b08f4f
FROM ${GUACD_BASE} AS build
USER root
ENV SOURCE_DATE_EPOCH=1750361542
RUN apk add --no-cache autoconf=2.71-r2 automake=1.16.5-r2 build-base=0.5-r3 \
        cairo-dev=1.17.8-r1 curl=8.12.1-r0 git=2.40.4-r0 libjpeg-turbo-dev=2.1.5.1-r3 \
        libpng-dev=1.6.44-r0 libtool=2.4.7-r2 openssl-dev=3.1.8-r0 pango-dev=1.50.14-r1 util-linux-dev=2.38.1-r8 \
    && apk info -v | sort > /tmp/peter-guacd-build-packages.txt
WORKDIR /src
RUN curl -fSL --retry 3 https://archive.apache.org/dist/guacamole/1.6.0/source/guacamole-server-1.6.0.tar.gz -o /tmp/guacamole-server.tar.gz \
    && echo '8bc45675da96d7b6f39728160181e3d4ff3c08f460f6d26de5805b642bf13f2b  /tmp/guacamole-server.tar.gz' | sha256sum -c - \
    && tar -xzf /tmp/guacamole-server.tar.gz --strip-components=1
COPY terminal.patch tunnel-cleanup.patch recording.patch /tmp/patches/
RUN git apply --check /tmp/patches/*.patch && git apply /tmp/patches/*.patch \
    && (cd /tmp/patches && sha256sum *.patch > /tmp/peter-guacd-patches.sha256) \
    && autoreconf -fi \
    && ./configure --without-vnc --without-rdp --without-ssh --without-telnet \
        --without-websockets --disable-kubernetes --disable-guacenc --disable-guaclog \
    && make -j2

FROM ${GUACD_BASE}
LABEL org.opencontainers.image.source="https://github.com/Computer-Hardware-Club/Peter" \
      org.opencontainers.image.version="1.6.0"
COPY --from=build /src/src/guacd/.libs/guacd /opt/guacamole/sbin/guacd
COPY --from=build /src/src/terminal/.libs/libguac-terminal.so.2.0.0 /opt/guacamole/lib/
COPY --from=build /src/src/libguac/.libs/libguac.so.25.0.0 /opt/guacamole/lib/
COPY --from=build /tmp/peter-guacd-patches.sha256 /opt/guacamole/
COPY --from=build /tmp/peter-guacd-build-packages.txt /opt/guacamole/
