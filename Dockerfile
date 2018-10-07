FROM rust as builder

COPY rust-doh /src/
WORKDIR /src/
RUN cargo build

FROM debian:stretch

ENV DEBIAN_FRONTEND=noninteractive

RUN mkdir -p /etc/doh/ \
    && mkdir -p /var/www/letsencrypt \
    && chown -R www-data:www-data /var/www/letsencrypt \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        nginx \
        supervisor \
        certbot \
        python3-pip \
        python3-setuptools \
        python3-pkg-resources \
    && pip3 --no-cache-dir install reload \
    && rm -rf /etc/nginx/sites-*/default \
 && rm -rf /var/lib/apt/lists/*
COPY set_log_format.sh /srv/
COPY letsencrypt-wrapper.sh /srv/
COPY doh-wrapper.sh /srv/
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY doh.conf /etc/nginx/conf.d/
COPY localhost.pem /etc/doh/
COPY localhost-key.pem /etc/doh/
COPY --from=builder /src/target/debug/doh-proxy /srv/
RUN /srv/set_log_format.sh /etc/nginx/nginx.conf

VOLUME ["/var/www/letsencrypt", "/var/log", "/etc/letsencrypt"]

EXPOSE "80"
EXPOSE "443"

ENTRYPOINT ["/usr/bin/supervisord"]
