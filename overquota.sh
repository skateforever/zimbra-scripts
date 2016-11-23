#!/bin/bash

OVER_QUOTA_USERS=($(/opt/zimbra/postfix/sbin/postqueue -p | grep "Over quota" -A 1 | grep "@dominio.com" | awk '{ print $1 }' | sort -u))
# Possiveis status: active,maintenance,locked,closed,lockout,pending
OVER_QUOTA_STATUS=maintenance
OVER_QUOTA_USER_STATUS=active

if [ ${#OVER_QUOTA_USERS[@]} -gt 0 ]; then
    for ((i = 0 ; i < ${#OVER_QUOTA_USERS[@]} ; i++)); do
        OVER_QUOTA_USER__STATUS_ATUAL=($(zmprov ga "${OVER_QUOTA_USERS[$i]}" zimbraAccountStatus | grep zimbraAccountStatus | awk '{print $2}'))
        if [ "${OVER_QUOTA_USER_STATUS_ATUAL}" != "${OVER_QUOTA_STATUS}" ]; then
            LISTAS=($(su - zimbra -c "zmprov gam ${OVER_QUOTA_USERS[${i}]}"))
            if [ ${#LISTAS[@]} -gt 0 ]; then
                echo "O usuario ${OVER_QUOTA_USERS[$i]} esta nas seguintes listas..."
                echo "$LISTAS"
            else
                echo "Usuario ${OVER_QUOTA_USERS[$i]} nao esta em nenhuma lista!"
            fi
            echo "Colocando a conta do usuario ${OVER_QUOTA_USERS[$i]} em modo manutencao..."
            su - zimbra -c "zmprov ma ${OVER_QUOTA_USERS[$i]} zimbraAccountStatus ${OVER_QUOTA_STATUS}"
            if [ $? != 0 ]; then
                echo "Nao foi possivel fechar a conta ${OVER_QUOTA_USERS[$i]}!!!"
                echo "Favor verificar o que aconteceu!!"
                exit 1
            else
                echo "Mudando a senha do usuario..."
                SENHA=$(tr -d -c 'A-Za-z0-9' < /dev/urandom | head -c 8)
                echo "Mudando a senha do usuario ${USUARIOS[${i}]} para ${SENHA}."
                su - zimbra -c "zmprov sp ${OVER_QUOTA_USERS[$i]} ${SENHA}"
            fi
        else
            echo "Usuario ${OVER_QUOTA_USERS[$i]} ja esta em manutencao e senha modificada!"
            echo "Entrar em contato com o usuario!"
        fi
    done
fi
