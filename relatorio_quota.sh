#!/bin/bash
DATA=$(date +%Y%m%d-%H%M)
DOMINIO="dominio.com"
DTSMAIL=(emails@dominio.com)
RELATORIO="/tmp/relatorio_quota.txt"

rm -f ${RELATORIO}
touch ${RELATORIO}

SERVIDOR=$(su - zimbra -c "zmhostname")
su - zimbra -c "/opt/zimbra/bin/zmprov gqu ${SERVIDOR} | grep ${DOMINIO}" | awk {'print $1" "$3" "$2'} | sort | while read LINHA 
do
    USO=$(echo ${LINHA} | cut -f2 -d " ")
    QUOTA=$(echo ${LINHA} | cut -f3 -d " ")
    USUARIO=$(echo ${LINHA} | cut -f1 -d " ")
    STATUS=$(su - zimbra -c "/opt/zimbra/bin/zmprov ga ${USUARIO}" | grep  ^zimbraAccountStatus | cut -f2 -d " ")
echo "${USUARIO} `expr ${USO} / 1024 / 1024`Mb `expr ${QUOTA} / 1024 / 1024`Mb (${STATUS} account)" >> ${RELATORIO}
done

cat ${RELATORIO} | strings | mail -s "Uso do e-mail ${DATA}" ${DTSMAIL[@]}
