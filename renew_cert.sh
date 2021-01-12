#!/bin/bash
# manage certificat for haproxy
# define variables

fullchain=fullchain.pem
priv_key=privkey.pem
cert_haproxy=/etc/haproxy/certs/
pid=/tmp/renew_ssl.pid
nagios_log=/tmp/renew_ssl_nagios.log
logfile=/tmp/renew_ssl.log
certbot_bin=$(which certbot)
exp_limit=30
date=$(date '+%d-%m-%Y %H:%M')
debug="0"
haproxy_cmd=$(which haproxyctl)
ha_reload=$(service haproxy reload)

function checkhaconf() {
    # manage configcheck and reload haproxy
    ${haproxy_cmd} configcheck
    if [ "$?" -ne 0 ]; then
        echo "critical: $date $? error in haproxy config" >> ${logfile}
        echo "critical: $date $? error in haproxy config" > ${nagios_log}
    else
        echo "config ok reload haproxy ${date}" >> ${logfile}
        ${ha_reload}
        if [ "$?" -ne 0 ]; then
            echo "error reload haproxy ${date}" >> ${logfile}
            echo "critical: ${date} $? error reload haproxy" > $ ${nagios_log}
        else
            echo "ok haproxy reload ${date}" >> ${logfile}
        fi
    fi
}

function checkstate() {

    if [ "$1" -ne 0 ]; then
        echo "critical $date ---- cert $2 " >> ${logfile}
        echo "critical ${date} $2" > ${nagios_log}
    else
        echo "${date} ---- $2 cert ok" >> ${logfile}
        echo "check haproxy conf and reload" >> ${logfile}
        echo "ok ${date} $2" > ${nagios_log}
        checkhaconf
    fi

}

function findcert() {

    for site in $(ls /etc/letsencrypt/renewal/); do

        echo "start generate ssl for haproxy for domaine: ${site}" >> ${logfile}
        domain=${site%.conf}
        echo "${domain}"
        echo "${date} check certificate valid for: ${cert_haproxy}${domain}.pem" >> ${logfile}
        if [ -f "${cert_haproxy}${domain}.pem" ]; then
            # cert_file="${cert_haproxy}${site}.pem"

            date_cert_lets=$(openssl x509 -in ${cert_haproxy}${domain}.pem -text -noout|grep "Not After"|cut -c 25-)
            # check if we can have the date of certificat
            if [ -z "$date_cert_lets" ]; then
                echo "$date: error with certificat date: ${domain}" >> ${logfile}
                continue
            else
                exp=$(date -d "${date_cert_lets}" +%s)
                echo "date du certif ${exp}"
                datenow=$(date -d "now" +%s)

                days_exp=$(echo \( ${exp} - ${datenow} \) / 86400 |bc)  # days left

                if [ "$days_exp" -gt "$exp_limit" ] ; then
                    echo "${date_cert_lets}: cert VALID" >> ${logfile}
                    echo "[${domain}] : The certificate is up to date, no need for renewal (${days_exp} days left)." >> ${logfile}

                else
                    echo "${days_exp} days left"
                    if [ "${debug}" -ne "1" ]; then   # not in debug mode

                        rm ${cert_haproxy}${domain}.pem
                        echo "${$date} The certificate for ${domain} is about to expire soon. Starting Let's Encrypt renewal script..." >> ${logfile}
                        echo "${$date} The certificate for ${domain} is about to expire soon. Starting Let's Encrypt renewal script..."

                        ${certbot_bin} certonly --standalone --renew-by-default --http-01-port=8888 -d ${domain}
                        cat /etc/letsencrypt/live/${domain}/${fullchain} /etc/letsencrypt/live/${domain}/${priv_key} > ${cert_haproxy}${domain}.pem
                        checkstate $? ${domain}

                    else
                        echo "mode debug do nothing"
                        # debug mode just dry_run
                        $certbot_bin certonly --standalone --dry-run --renew-by-default --http-01-port=8888 -d ${domain}
                        checkstate $? ${domain}
                    fi
                fi
            fi

        else
            echo "${date} new certificat need to add for haproxy" >> ${logfile}
            cat /etc/letsencrypt/live/${domain}/${fullchain} /etc/letsencrypt/live/${domain}/${priv_key} > ${cert_haproxy}${domain}.pem
            checkstate $? ${domain}
        fi

    done
}

function start() {
    echo "${date} start ssl renew" >> ${logfile}

    if [ -f "$pid" ]; then
        echo "critical script allready running" 2>&1 >> ${logfile}
        echo "critical ${date} script allready start" > ${nagios_log}
        exit 2
    else
        touch $pid
        echo "ok ${date} generate certs haproxy" > ${nagios_log}
        findcert
    fi
}

function clean() {
    rm $pid
    echo "${date} end ssl renew" >> ${logfile}
    exit 0
}

start
clean
