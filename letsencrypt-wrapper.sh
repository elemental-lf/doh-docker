#!/bin/bash

if [[ $DEBUG ]]; then
    set -x
fi

logger() {
    echo "[letsencrypt] :: $(date +%x-%X) :: $@" | tee -a /var/log/letsencrypt-wrapper.log
}

edit_nginx_conf() {
    logger "Adding configuration to nginx for domain ${1}"
    cat > /etc/nginx/conf.d/${1}.conf << EOC

# ${1} #####
server{
    listen 443 ssl http2 default_server;
    server_name ${1};

    access_log /dev/stdout;
    error_log /dev/stderr;

    ssl_certificate /etc/letsencrypt/live/${1}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${1}/privkey.pem;

    include conf.d/pass_to_doh;
}
#####################################################
EOC

}

get_first_time() {
    local d=$1
    if certbot certonly --agree-tos --email $EMAIL \
        -n --webroot -w /var/www/letsencrypt -d $d
    then
        logger "First certificate got for $d"
        edit_nginx_conf $d
    else
        logger "ERROR on first time certificate for $d"
        exit 2
    fi
}

renew_certs() {
    certbot renew -n --webroot -w /var/www/letsencrypt -d "${1}"
}

check_env() {
    if ! [[ $DOMAINS ]]; then
        logger "ERROR! Missing domains to be used! Set DOMAINS environment variable."
        exit 1
    fi
    if ! [[ $EMAIL ]]; then
        logger "ERROR! Missing email address to use to register the domain(s) certificates."
    fi
}

should_force() {
    if ! [[ -f "/etc/letsencrypt/live/${1}/.doh-force" ]]; then
        return 0
    fi
    logger "Not skipping - found file /etc/letsencrypt/live/${1}/.doh-force"
    return 1
}

le_vol_mounted() {
    if grep "/etc/letsencrypt/live/${1}" <(mount) > /dev/null; then
        logger "A letsencrypt volume is mounted for domain ${1}"
        should_force $1 && return 0
    elif grep "/etc/letsencrypt" <(mount) > /dev/null; then
        logger "The whole /etc/letsencrypt is mounted"
        if [[ -d "/etc/letsencrypt/live/${1}" ]]; then
            should_force $1 && return 0
        fi
    fi
    return 1
}

main() {
    check_env
    for d in $DOMAINS; do
        if le_vol_mounted ${d}; then
            # Assuming that if the volume is mounted from the host
            # creation and renewal is in charge of others,
            # except if the .doh-force file il present in the
            # directory of the certificates. In such case, the container
            # will take care of renewing them.
            edit_nginx_conf $d
            logger "Skipping domain ${1}"
            continue
        fi
        if [[ -f /var/www/letsencrypt/live/$d/privkey.pem ]]; then
            logger "Renewing certificate for $d"
            renew_certs $d
        else
            logger "Getting first time certificates for $d"
            get_first_time $d
        fi
    done
    logger "All done, sleeping for ${WAIT_TIME:-"1d"}."
    sleep ${WAIT_TIME:-"1d"}
}

while true
do
    main
done
