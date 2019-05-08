#!/bin/bash

IP_INT=""
IP_EXT=""
data_LOG=$(date +%Y-%m-%d)
access_LOG=/opt/zimbra/log/access_log.${data_LOG}
BLOCKIP_FILE=/var/log/block_ips.txt

for IP in $(awk '{print $1}' ${access_LOG} | grep -Ev "127.0.0.1" | grep -v ${IP_INT} | grep -v ${IP_EXT} | sort -u | sed 's/,$//' | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"); do
    PAIS=$(geoiplookup ${IP} | awk '{print $5}')
    if [[ "${PAIS}" != "Brazil" ]]; then
        RESTANTES=$(grep ${IP} ${access_LOG} | awk '{print $1}' | sort -u | sed 's/,$//' | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b")
        for IP_Dois in ${RESTANTES[@]}; do
            if [[ ! $(grep ${IP} ${BLOCKIP_FILE}) ]]; then
                echo "${IP_Dois}" >> ${BLOCKIP_FILE}
                iptables -I INPUT -s ${IP_Dois} -j DROP
                iptables -I OUTPUT -d ${IP_Dois} -j DROP
            fi
        done
    fi
done
