#!/bin/bash

data_LOG=$(date +%Y-%m-%d)
access_LOG=/opt/zimbra/log/access_log.${data_LOG}

for IP in $(awk '{print $1}' ${access_LOG} | grep -Ev "192.168." | grep -Ev "10.84." | grep -Ev "127.0.0.1" | sort -u | sed 's/,$//' | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"); do
    PAIS=$(geoiplookup ${IP} | awk '{print $5}')
    if [[ "${PAIS}" != "Brazil" ]]; then
        RESTANTES=$(grep ${IP} ${access_LOG} | awk '{print $1}' | sort -u | sed 's/,$//' | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
        for IP_Dois in ${RESTANTES[@]}; do
            #echo -en "${IP_Dois}\t" && geoiplookup ${IP_Dois}
            if [[ ! $(grep ${IP} ${BLOCKIP_FILE}) ]]; then
                echo "${IP_Dois}" >> /var/log/block_ips.txt
                iptables -I INPUT -s ${IP_Dois} -j DROP
                iptables -I OUTPUT -d ${IP_Dois} -j DROP
            fi
        done
    fi
done
