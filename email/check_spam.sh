#!/bin/bash

################################################################################################################
#                                                                                                              #
# Autor: Leandro Carvalho                                                                                      #
# Contato: carvalho.inacio@gmail.com                                                                           #
# Versao: 2019.01.17 / Quinta                                                                                  #
#                                                                                                              #
# Função:                                                                                                      #
#                                                                                                              #
# Automatizacao de Servicos                                                                                    #
# Este script tem a tarefa de analisar a fila de emails.                                                       #
# Tarefa do script                                                                                             #
# Este script verifica a quantidade de emails, caso ultrapasse a quantidade estabelecida (QTD_MAX)             #
# Verificara qual o usuario esta enviando spam, desta forma mudara a senha e apagara os emails da fila         #
# Tambem verificara se o MTA esta parado ou nao                                                                #
# Limpa os logs com mais de 7 dias                                                                             #
# Toda a acao sera informada por email                                                                         #
#                                                                                                              #
# Change log:                                                                                                  #
#                                                                                                              #
# Ajustado para apagar os emails que sao enviados pelo MAILER-DAEMON                                           #
# Ajustado para verificar se o usuario existe, se nao existir, apagar os emails                                #
# Revisado para mudar a quantidade de spam se for Sabado ou Domingo                                            #
# Adicionado a busca pelo ip externo para bloqueio no iptables com "postcat -q"                                #
# Verificando a localização do ip externo que está enviando spam com o comando geoiplookup                     #
# Scripts check_ip.sh, check_fantasma.sh e check_spam_mtastatus.sh unificados                                  #
# Verificacao do status do MTA retirada                                                                        #
# Atualizado para funcionar na versão 8 do zimbra                                                              #
# Atualizado para mudar o status da conta que estava enviando SPAM                                             #
# Atualizado para adicionar na descrição da conta o motivo do bloqueio                                         #
# Ajuste de variaveis para setar o dominio em um único local                                                   #
# Ajuste de variaveis para definicao dos comandos da versao do zimbra                                          #
# Ajuste para permitir utilização em zimbra com vários domínios                                                #
#                                                                                                              #
################################################################################################################

DATA=$(date +%Y%m%d-%H%M)
DATA_zimbraNotes=$(date +"%H:%M %d/%m/%Y")
DIA=$(date +%a)

if [[ "$DIA" == "Sat" || "$DIA" == "Sun" ]]; then
    QTD_MAX=30
    QTD_SPAM=5
else
    QTD_MAX=80
    QTD_SPAM=25
fi

ZIMBRA_VERSION=8
if [ "${ZIMBRA_VERSION}" -le "7" ]; then
    POSTQUEUE=/opt/zimbra/postfix/sbin/postqueue
    POSTCAT=/opt/zimbra/postfix/sbin/postcat
    POSTSUPER=/opt/zimbra/postfix/sbin/postsuper
else
    POSTQUEUE=/opt/zimbra/common/sbin/postqueue
    POSTCAT=/opt/zimbra/common/sbin/postcat
    POSTSUPER=/opt/zimbra/common/sbin/postsuper
fi

COUNT=0
IP_INT=
IP_EXT=
QTD_EMAILS=$(${POSTQUEUE} -p | grep -c -E "^[A-Z0-9]")
QTD_USER_EMAILS=($(${POSTQUEUE} -p | grep -E "^[A-Z0-9]" | awk '{print $7}' | sort | uniq -c | awk '{print $1}'))
USUARIOS=($(${POSTQUEUE} -p | grep -E "^[A-Z0-9]" | awk '{print $7}' | sort | uniq -c | awk '{print $2}'))
CHECK_SPAM_LOG=/var/log/check_spam-${DATA}.log
DTSMAIL=()
BLOCKIP_FILE=/var/log/block_ips.txt

# Mude o status da conta conforme sua necessidade, o status da conta podem ser:
# Manutenção: maintenance
# Bloqueada: lockout
# Fechada: closed
ACCOUNT_STATUS="maintenance"

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
    if [ ! -z $IP ]; then
        /sbin/iptables -t filter -I INPUT -s $IP -j DROP
        /sbin/iptables -t filter -I OUTPUT -d $IP -j DROP
        echo "O usuario ${USUARIOS[${i}]} estava enviando spam, verificar o que esta acontecendo."
        echo "Adicione o ip $IP no alias do firewall."
        echo "$IP" >> ${BLOCKIP_FILE}
        geoiplookup $IP
        sed -i '/^\s*$/d' ${BLOCKIP_FILE}
    fi
}

(
if [[ ${QTD_EMAILS} -gt ${QTD_MAX} ]]; then
    echo "O numero de emails ativos (${QTD_EMAILS}) esta acima do limite estipulado (${QTD_MAX})."
    echo "Verificando se existe algum usuario enviando spam..."
    for ((i = 0 ; i < ${#USUARIOS[@]} ; i++)); do
        if [ ${QTD_USER_EMAILS[${i}]} -gt ${QTD_SPAM} ]; then
            if [ "${USUARIOS[${i}]}" == "MAILER-DAEMON" ]; then
                get_id
                remove_emails
                ((COUNT += 1))
            else
                su - zimbra -c "zmprov ga ${USUARIOS[${i}]} mail > /dev/null 2>&1"
                if [ "$?" == "0" ]; then
                    SENHA=$(tr -d -c 'A-Za-z0-9' < /dev/urandom | head -c 12)
                    echo "Mudando a senha do usuario ${USUARIOS[${i}]} para ${SENHA}."
                    su - zimbra -c "zmprov sp ${USUARIOS[${i}]} ${SENHA}"
                    if [ "$?" == "0" ]; then
                        # Caso queira mudar o status da conta, descomentar o comando abaixo e informar na descrição a mudança de status da conta
                        #echo "Mudando o status da conta de ativo para manutencao..."
                        #su - zimbra "zmprov ma ${USUARIOS[${i}]} zimbraAccountStatus ${ACCOUNT_STATUS}"
                        echo "Informando na descricao do usuario o motivo da mudanca..."
                        su - zimbra -c "zmprov ma ${USUARIOS[${i}]} description \"SPAM\" zimbraNotes \"Esta conta foi modificada pois estava enviando SPAM as ${DATA_zimbraNotes}, senha modificada pra ${SENHA}.\""
                        get_id
                        get_ip
                        block_ip
                        remove_emails
                        ((COUNT += 1))
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

    if [ $COUNT == 0 ]; then
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
