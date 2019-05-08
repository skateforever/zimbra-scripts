#!/bin/bash

IP_INT=""
IP_EXT=""
BLOCKIP_FILE=/var/log/block_ips.txt

for IP in $(netstat -napult | grep -v "Conex" | grep -v "Remoto" | awk '{print $5}' | grep -v ":::*" | grep -v "0.0.0.0:*" | grep -v "127.0.0.1" | grep -v ${IP_INT} | grep -v ${IP_EXT} | cut -d ":" -f 1); do
    PAIS=$(geoiplookup ${IP} | awk '{print $5}')
    if [[ "${PAIS}" != "Brazil" ]]; then
        PORTA_DESTINO=$(netstat -npulta | grep ${IP} | awk '{print $5}' | cut -d ":" -f 2)
        kill_PROCESSO=$(netstat -npulta | grep ${IP} | awk '{print $7}' | grep -v "-" | cut -d "/" -f 1)
        if [[ $PORTA_DESTINO == 80 ]] || [[ $PORTA_DESTINO == 8080 ]] || [[ $PORTA_DESTINO == 443 ]] || [[ $PORTA_DESTINO == 8443 ]] || [[ $PORTA_DESTINO == 1337 ]] || [[ $PORTA_DESTINO == 4444 ]]; then
            if [[ ! $(grep ${IP} ${BLOCKIP_FILE}) ]]; then
                iptables -I INPUT -s ${IP} -j DROP
                iptables -I OUTPUT -d ${IP} -j DROP
                echo "${IP}" >> ${BLOCKIP_FILE}
                kill -15 ${kill_PROCESSO} 2> /dev/null
            fi    
        fi
    fi
done
