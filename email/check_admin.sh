#!/bin/bash

HORARIO=$(date +%Y%m%d)
DATA=$(date +%d/%m/%Y)
DOMINIO_EMAIL=
ZIMBRA_AUDIT_LOG=/opt/zimbra/log/audit.log

USERS_OK=$(grep ${DOMINIO_EMAIL}:7071 ${ZIMBRA_AUDIT_LOG} | grep "cmd=AdminAuth" | awk '{print $5}' | cut -d ";" -f 1 | cut -d "=" -f 2 | sort | uniq)
USERS_FAIL=$(grep ${DOMINIO_EMAIL}:7071 ${ZIMBRA_AUDIT_LOG} | grep -E "invalid password|error=authentication failed" | awk '{print $5}' | cut -d ";" -f 1 | cut -d "=" -f 2 | sort | uniq)
DTSMAIL=()

ADMIN_LOGIN_LOG=/var/log/check_admin-${HORARIO}.log

(
echo "Listando os usuarios que conseguiram acesso a interface administrativa..."
for USER in ${USERS_OK[@]}; do
    echo "O usuario ${USER} no dia ${DATA} acessou a interface administrativa a partir dos seguintes IPs:"
    grep ${DOMINIO_EMAIL}:7071 ${ZIMBRA_AUDIT_LOG} | grep -E "${USER}" | awk '{print $5}' | cut -d ";" -f 2 | cut -d "=" -f 2 | sort | uniq | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"
    HORARIOS=$(grep ${USER} ${ZIMBRA_AUDIT_LOG} | awk '{print $2}' | cut -d "," -f 1 | sort | uniq)
    echo "O usuario ${USER} no dia ${DATA} acessou a interface administrativa nos seguintes horarios:"
    echo "${HORARIOS}"
done
echo ""
echo "Listando os usuarios que falharam no acesso a interface administrativa..."
for USER in ${USERS_FAIL[@]}; do
    echo "O usuario ${USER} no dia ${DATA} tentou acessar a interface administrativa a partir dos seguintes IPs:"
    grep ${DOMINIO_EMAIL}:7071 ${ZIMBRA_AUDIT_LOG} | grep -E "${USER}" | awk '{print $5}' | cut -d ";" -f 2 | cut -d "=" -f 2 | sort | uniq | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"
    HORARIOS=$(grep ${USER} ${ZIMBRA_AUDIT_LOG} | awk '{print $2}' | cut -d "," -f 1 | sort | uniq)
    echo "O usuario ${USER} no dia ${DATA} tentou acessar a interface administrativa nos seguintes horarios:"
    echo "${HORARIOS}"
done
) > ${ADMIN_LOGIN_LOG} 2>&1
if [ -s ${ADMIN_LOGIN_LOG} ]; then
    cat ${ADMIN_LOGIN_LOG} | strings | mail -s "Verifica Admin LOGIN - ${DATA}" ${DTSMAIL[@]}
else
    rm -f ${ADMIN_LOGIN_LOG}
fi

find /var/log/ -maxdepth 1 -mtime +7 -name 'check_admin-*.log' -print | xargs rm -f
