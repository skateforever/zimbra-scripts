#!/bin/bash
# 
# Script para monitoramento de envio de SPAM
# Usar em conjunto com o PolicyD
#

DATA=$(date +%Y%m%d-%H%M)
DATA_zimbraNotes=$(date +"%H:%M %d/%m/%Y")
DIA=$(date +%a)
IP_INT=
IP_EXT=
BLOCKIP_FILE=/var/log/block_ips.txt
CHECK_SPAM_LOG=/var/log/check_spam-${DATA}.log
COUNT=0
ZIMBRA_VERSION=8
DTSMAIL=()

# Lista de e-mails que nao vao entrar no monitoramento
WHITELIST=""

# Mude o status da conta conforme sua necessidade, o status da conta podem ser:
# Manutenção: maintenance
# Bloqueada: lockout
# Fechada: closed
ACCOUNT_STATUS="maintenance"

if [[ "$DIA" == "Sat" || "$DIA" == "Sun" ]]; then
    QTD_MAX=30
    QTD_SPAM=5
else
    QTD_MAX=80
    QTD_SPAM=25
fi

if (( ${ZIMBRA_VERSION} <= 7 )); then
    POSTQUEUE=/opt/zimbra/postfix/sbin/postqueue
    POSTCAT=/opt/zimbra/postfix/sbin/postcat
    POSTSUPER=/opt/zimbra/postfix/sbin/postsuper
else
    POSTQUEUE=/opt/zimbra/common/sbin/postqueue
    POSTCAT=/opt/zimbra/common/sbin/postcat
    POSTSUPER=/opt/zimbra/common/sbin/postsuper
fi

QTD_EMAILS=$(${POSTQUEUE} -p | grep -c -E "^[A-Z0-9]")

if [ -z ${WHITELIST} ]; then
    QTD_USER_EMAILS=($(${POSTQUEUE} -p | grep -E "^[A-Z0-9]" | awk '{print $7}' | sort | uniq -c | awk '{print $1}'))
    USUARIOS=($(${POSTQUEUE} -p | grep -E "^[A-Z0-9]" | awk '{print $7}' | sort | uniq -c | awk '{print $2}'))
else
    QTD_USER_EMAILS=($(${POSTQUEUE} -p | grep -E "^[A-Z0-9]" | awk '{print $7}' | grep -Ev "${WHITELIST}" | sort | uniq -c | awk '{print $1}'))
    USUARIOS=($(${POSTQUEUE} -p | grep -E "^[A-Z0-9]" | awk '{print $7}' | grep -Ev "${WHITELIST}" | sort | uniq -c | awk '{print $2}'))
fi

function get_id() {
    IDs=($(${POSTQUEUE} -p | grep -E "^[A-Z0-9]" | grep "${USUARIOS[${i}]}" | awk '{print $1}' | sed 's/\*//g'))
}

function get_ip() {
    IP=($(${POSTCAT} -q ${IDs[0]} | grep "Received: from" | grep -Ev "127.0.0.1|${IP_INT}|${IP_EXT}" | awk '{print $5}' | sed -e 's/\[//' -e 's/\]//' -e 's/)//' | grep -oE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b"))
}

function remove_emails() {
    echo "O ${USUARIOS[${i}]} tentou enviar ${#IDs[@]} spams."
    echo "Deletando os spams..."
    for ID in "${IDs[@]}"; do
        ${POSTSUPER} -d "${ID}" > /dev/null
    done
}

function block_ip() {
    if [ ! -z ${IP} ]; then
        /sbin/iptables -t filter -I INPUT -s $IP -j DROP
        /sbin/iptables -t filter -I OUTPUT -d $IP -j DROP
        echo "O usuario ${USUARIOS[${i}]} estava enviando spam, verificar o que esta acontecendo."
        echo "Adicione o ip $IP no alias do firewall."
        echo "${IP}" >> ${BLOCKIP_FILE}
        geoiplookup ${IP}
        sed -i '/^\s*$/d' ${BLOCKIP_FILE}
    fi
}

(
if (( ${QTD_EMAILS} > ${QTD_MAX} )); then
    echo "O numero de emails ativos (${QTD_EMAILS}) esta acima do limite estipulado (${QTD_MAX})."
    echo "Verificando se existe algum usuario enviando spam..."
    for ((i = 0 ; i < ${#USUARIOS[@]} ; i++)); do
        if [ ${QTD_USER_EMAILS[${i}]} > ${QTD_SPAM} ]; then
            if [ "${USUARIOS[${i}]}" == "MAILER-DAEMON" ]; then
                get_id
                remove_emails
                ((COUNT ++))
            else
                su - zimbra -c "zmprov ga ${USUARIOS[${i}]} mail > /dev/null 2>&1"
                if (( $? == 0 )); then
                    SENHA=$(tr -d -c 'A-Za-z0-9' < /dev/urandom | head -c 12)
                    echo "Mudando a senha do usuario ${USUARIOS[${i}]} para ${SENHA}."
                    su - zimbra -c "zmprov sp ${USUARIOS[${i}]} ${SENHA}"
                    if [ $? == 0 ]; then
                        # Caso queira mudar o status da conta, descomentar o comando abaixo e informar na descrição a mudança de status da conta
                        #echo "Mudando o status da conta de ativo para manutencao..."
                        #su - zimbra "zmprov ma ${USUARIOS[${i}]} zimbraAccountStatus ${ACCOUNT_STATUS}"
                        echo "Informando na descricao do usuario o motivo da mudanca..."
                        su - zimbra -c "zmprov ma ${USUARIOS[${i}]} description \"SPAM\" zimbraNotes \"Esta conta foi modificada pois estava enviando SPAM as ${DATA_zimbraNotes}, senha modificada pra ${SENHA}.\""
                        get_id
                        get_ip
                        block_ip
                        remove_emails
                        ((COUNT ++))
                    else
                        echo "Nao foi possivel modificar a senha do ${USUARIOS[${i}]}"
                        echo "Favor verificar o que ocorreu!"
                        exit 1
                    fi
                else
                    get_id
                    get_ip
                    block_ip
                    remove_emails
                fi
            fi
        fi
    done

    if (( ${COUNT} == 0 )); then
        echo "Nenhum usuario do zimbra enviando spam!"
    fi

fi
) > ${CHECK_SPAM_LOG} 2>&1
if [ -s ${CHECK_SPAM_LOG} ]; then
    cat ${CHECK_SPAM_LOG} | strings | mail -s 'Verifica SPAM - "${DATA}"' "${DTSMAIL[@]}"
else
    rm -f ${CHECK_SPAM_LOG}
fi

find /var/log/ -maxdepth 1 -mtime +7 -name 'check_spam-*.log' -print | xargs rm -f
