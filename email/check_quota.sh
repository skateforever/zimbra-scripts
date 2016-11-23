#!/bin/bash

################################################################################################################
#                                                                                                              #
# Autor: Leandro Carvalho <carvalho.inacio@gmail.com>                                                          #
# Versao 20150210                                                                                              #
#                                                                                                              #
# Automatizacao de Servicos                                                                                    #
# Adicionado verificacao de over quota, lista os grupos do usuario e muda sua senha                            #
# Toda a acao sera informada por email                                                                         #
#                                                                                                              #
################################################################################################################

DATA=$(date +%Y%m%d-%H%M)

OVER_QUOTA_USERS=($(/opt/zimbra/postfix/sbin/postqueue -p | grep "Over quota" -A 1 | egrep "@dominio.com|@mail.dominio.com" | awk '{print $1}' | sort -u))
#Possiveis status: active,maintenance,locked,closed,lockout,pending
OVER_QUOTA_STATUS="closed"
OVER_QUOTA_USER_STATUS="active"
OVER_QUOTA_LOG=/var/log/over_quota-${DATA}.log

DTSMAIL=(emails@dominio.com)

(
if [ ${#OVER_QUOTA_USERS[@]} -gt 0 ]; then
    for ((i = 0 ; i < ${#OVER_QUOTA_USERS[@]} ; i++)); do
        OVER_QUOTA_USER_STATUS_ATUAL="$(su - zimbra -c "zmprov ga ${OVER_QUOTA_USERS[$i]} zimbraAccountStatus | grep zimbraAccountStatus | cut -d ":" -f 2")"
        if [ ${OVER_QUOTA_USER_STATUS_ATUAL} != ${OVER_QUOTA_STATUS} ]; then
            LISTAS=($(su - zimbra -c "zmprov gam ${OVER_QUOTA_USERS[${i}]}"))
            if [ ${#LISTAS[@]} -gt 0 ]; then
                echo "O usuario ${OVER_QUOTA_USERS[$i]} esta nas seguintes listas..."
                for ((l = 0 ; l < ${#LISTAS[@]} ; l++)); do
                	echo "${LISTAS[${l}]}"
                done
            else
                echo "Usuario ${OVER_QUOTA_USERS[$i]} nao esta em nenhuma lista!"
            fi
            echo "Colocando a conta do usuario ${OVER_QUOTA_USERS[$i]} em modo fechado..."
            su - zimbra -c "zmprov ma ${OVER_QUOTA_USERS[$i]} zimbraAccountStatus ${OVER_QUOTA_STATUS}"
            if [ $? != 0 ]; then
                echo "Nao foi possivel fechar a conta ${OVER_QUOTA_USERS[$i]}!!!"
                echo "Favor verificar o que aconteceu!!"
                exit 1
            else
                SENHA=$(tr -d -c 'A-Za-z0-9' < /dev/urandom | head -c 8)
                echo "Mudando a senha do usuario ${OVER_QUOTA_USERS[${i}]} para ${SENHA}."
                su - zimbra -c "zmprov sp ${OVER_QUOTA_USERS[$i]} ${SENHA}"
                echo -e "\n"
                echo ""
            fi
        else
            echo "Usuario ${OVER_QUOTA_USERS[$i]} ja esta fechado e senha modificada!"
            echo "Entrar em contato com o usuario!"
            echo -e "\n"
            echo ""
        fi
    done
    echo "Apagando emails de over quota da lista"
    OVER_QUOTA_QUEUE=($(/opt/zimbra/postfix/sbin/postqueue -p | grep "Over quota" -B 1 | egrep ^[A-Z0-9] | awk '{print $1}'))
    for ID in ${OVER_QUOTA_QUEUE[@]}
    do
        /opt/zimbra/postfix/sbin/postsuper -d ${ID}
    done
fi) > ${OVER_QUOTA_LOG} 2>&1
if [ -s ${OVER_QUOTA_LOG} ]; then
    cat ${OVER_QUOTA_LOG} | strings | mail -s "Verifca QUOTA - ${DATA}" ${DTSMAIL[@]}
else
    rm -f ${OVER_QUOTA_LOG}
fi

find /var/log/ -maxdepth 1 -mtime +7 -name 'over_quota-*.log' -print | xargs rm -f
