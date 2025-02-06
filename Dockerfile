FROM alpine:latest as build

ARG BUILD

ARG NGX_MAINLINE_VER=1.26.2
ARG QUICTLS_VER=openssl-3.3.0+quic
ARG NGX_BROTLI=master
ARG NGX_STICKY_VER=1.2.6
ARG NGX_HEADERS_MORE=v0.37rc1
ARG NGX_NJS=0.8.7
ARG NGX_GEOIP2=3.4

WORKDIR /src

# Install the required packages

RUN apk add --no-cache \
        ca-certificates \
        build-base \ 
        patch \
        cmake \ 
        git \
        libtool \
        autoconf \
        automake \
        libatomic_ops-dev \
        zlib-dev \
        pcre2-dev \
        linux-headers \ 
        libxml2-dev \ 
        libxslt-dev \
        perl-dev \
        curl-dev \
        geoip-dev \
        libmaxminddb-dev 

   
RUN git clone --recursive --branch "$QUICTLS_VER" https://github.com/quictls/openssl /src/openssl 

# Modules

RUN (git clone --recursive --branch "$NGX_BROTLI" https://github.com/google/ngx_brotli /src/ngx_brotli \
        && git clone --recursive --branch "$NGX_HEADERS_MORE" https://github.com/openresty/headers-more-nginx-module /src/headers-more-nginx-module \
        && git clone --depth 1 --recurse-submodules https://github.com/tokers/zstd-nginx-module.git /src/ngx_zstd \
        && git clone --depth 1 --recurse-submodules https://github.com/facebook/zstd.git /src/zstd \
        && cd /src/zstd && make -j$(nproc) && make install && make clean \
        && git clone --depth 1 --recurse-submodules https://github.com/PCRE2Project/pcre2.git /src/pcre2 \
        && cd /src/pcre2 && ./autogen.sh && ./configure && make -j$(nproc) && make install && make clean \
        && git clone --recursive --branch "$NGX_NJS" https://github.com/nginx/njs /src/njs \
        && git clone --depth 1 https://github.com/cloudflare/zlib.git /src/zlib \
        && cd /src/zlib && ./configure \
        && cd ../ && wget https://github.com/Refinitiv/nginx-sticky-module-ng/archive/refs/tags/$NGX_STICKY_VER.tar.gz \
        && tar xf $NGX_STICKY_VER.tar.gz \
        && mv nginx-sticky-module-ng-$NGX_STICKY_VER nginx-sticky-module \
        && sed -i 's@ngx_http_parse_multi_header_lines.*@ngx_http_parse_multi_header_lines(r, r->headers_in.cookie, \&iphp->sticky_conf->cookie_name, \&route) != NULL){@g' nginx-sticky-module/ngx_http_sticky_module.c &&
        && sed -i '12a #include <openssl/sha.h>' nginx-sticky-module/ngx_http_sticky_misc.c \
        && sed -i '12a #include <openssl/md5.h>' nginx-sticky-module/ngx_http_sticky_misc.c \ 
        && git clone --recursive --branch "$NGX_GEOIP2" https://github.com/leev/ngx_http_geoip2_module /src/ngx_http_geoip2_module) 
    
# Nginx

RUN (wget https://nginx.org/download/nginx-"$NGX_MAINLINE_VER".tar.gz -O - | tar xzC /src \
        && mv /src/nginx-"$NGX_MAINLINE_VER" /src/nginx \
        && wget https://raw.githubusercontent.com/nginx-modules/ngx_http_tls_dyn_size/master/nginx__dynamic_tls_records_1.25.1%2B.patch -O /src/nginx/dynamic_tls_records.patch \
        && sed -i "s|nginx/|NGINX-QuicTLS/|g" /src/nginx/src/core/nginx.h \
        && sed -i "s|Server: nginx|Server: NGINX-QuicTLS|g" /src/nginx/src/http/ngx_http_header_filter_module.c \
        && sed -i "s|<hr><center>nginx</center>|<hr><center>NGINX-QuicTLS</center>|g" /src/nginx/src/http/ngx_http_special_response.c \
        && cd /src/nginx \
        && git clone --depth 1 --recurse-submodules https://github.com/zhouchangxun/ngx_healthcheck_module.git  ngx_healthcheck_module \
        &&  patch -p1 < ./ngx_healthcheck_module/nginx_healthcheck_for_nginx_1.19+.patch \
        && patch -p1 < dynamic_tls_records.patch) 
RUN cd /src/nginx \
    && ./configure \
        --prefix=/usr/local/nginx \
        --with-compat \
        --with-threads \
        --with-file-aio \
        --with-pcre=../pcre2  \
        --with-zlib=../zlib \
        --with-openssl="../openssl" \
        --with-openssl-opt="no-ssl3 no-ssl3-method no-weak-ssl-ciphers" \
        --with-http_sub_module \
        --with-http_stub_status_module \
        --with-http_auth_request_module \
        --with-stream \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module \
        --with-stream_realip_module \
        --with-http_v2_module \
        --with-http_v3_module \
        --with-http_ssl_module \
        --with-http_realip_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_auth_request_module \
        --add-module=../ngx_http_geoip2_module \
        --add-module=../headers-more-nginx-module \
        --add-module=./ngx_healthcheck_module \
        --add-module=../nginx-sticky-module \
        --add-module=../ngx_zstd \
        --add-module=../ngx_brotli \
        --with-cc-opt='-static -s' \
        --with-ld-opt=-static
    && make -j "$(nproc)" \
    && make -j "$(nproc)" install \
    && rm /src/nginx/*.patch \
    && strip -s /usr/local/nginx \
    && strip -s /usr/local/nginx/modules/*.so


