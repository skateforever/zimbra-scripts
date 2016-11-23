#!/bin/bash

################################################################################################################
#                                                                                                              #
# Autor: Leandro Carvalho <carvalho.inacio@gmail.com                                                           #
# Versao 20161113 / Domingo                                                                                    #
#                                                                                                              #
# Automatizacao de Servicos                                                                                    #
# Este script tem a tarefa de analisar a fila de emails.                                                       #
# Tarefa do script                                                                                             #
# Este script verifica a quantida de emails, caso ultrapasse a quantidade estabelecida (QTD_MAX)               #
# Verificara qual o usuario esta enviando spam, desta forma mudara a senha e apagara os emails da fila         #
# Tambem verificara se o MTA esta parado ou nao                                                                #
# Limpa os logs com mais de 7 dias                                                                             #
# Toda a acao sera informada por email                                                                         #
# Ajustado para apagar os emails que sao enviados pelo MAILER-DAEMON                                           #
# Ajustado para verificar se o usuario existe, se nao existir, apagar os emails                                #
# Adicionado uma funcao chamada remove para limpar a fila de email sem repetir                                 #
# Revisado para mudar a quantidade de spam se for Sabado ou Domingo                                            # 
#                                                                                                              #
################################################################################################################

HR=$(date +%H)
DATA=$(date +%Y%m%d-%H%M)
DIA=$(date +%a)

if [[ "$DIA" == "Sab" || "$DIA" == "Dom" ]]; then
    QTD_MAX=50
    QTD_SPAM=10    
else
    QTD_MAX=100
    QTD_SPAM=30
fi

COUNT=0
QTD_EMAILS=$(/opt/zimbra/postfix/sbin/postqueue -p | egrep "^[A-Z0-9]" | wc -l)
QTD_USER_EMAILS=($(/opt/zimbra/postfix/sbin/postqueue -p | egrep "^[A-Z0-9]" | egrep '@dominio.com|@mail.dominio.com|MAILER-DAEMON' | awk '{print $7}' | sort | uniq -c | awk '{print $1}'))
MTASTATUS=$(su - zimbra -c "zmcontrol status|grep mta"| awk '{print $2}')
USUARIOS=($(/opt/zimbra/postfix/sbin/postqueue -p | egrep "^[A-Z0-9]" | egrep '@dominio.com|@mail.dominio.com|MAILER-DAEMON' | awk '{print $7}' | sort | uniq -c | awk '{print $2}'))
CHECK_MAIL_LOG=/var/log/check_mail-${DATA}.log
LOCK=/tmp/check_spam.lock
DTSMAIL=(emails@dominio.com)
SERVIDOR=$(su - zimbra -c "zmhostname")

remove(){
    IDs=($(/opt/zimbra/postfix/sbin/postqueue -p | egrep "^[A-Z0-9]" | grep "${USUARIOS[${i}]}" | awk '{print $1}' | sed 's/\*//g'))
    echo "O ${USUARIOS[${i}]} tentou enviar ${#IDs[@]} spams."
    echo "Deletando os spams..."
    for ID in "${IDs[@]}"; do 
       /opt/zimbra/postfix/sbin/postsuper -d ${ID} 
    done
    let "COUNT += 1"
}

(
if [ ${QTD_EMAILS} -gt ${QTD_MAX} ]; then
    echo "O numero de emails ativos (${QTD_EMAILS}) esta acima do limite estipulado (${QTD_MAX})."
    echo "Verificando se existe algum usuario enviando spam..."
    for ((i = 0 ; i < ${#USUARIOS[@]} ; i++)); do
        if [[ ${QTD_USER_EMAILS[${i}]} -gt ${QTD_SPAM} ]]; then
            if [ "${USUARIOS[${i}]}" == "MAILER-DAEMON" ]; then
                 remove
            else
                if [[ $(su - zimbra -c "/opt/zimbra/bin/zmprov gqu ${SERVIDOR} | cut -d \" \" -f 1 | grep ${USUARIOS[${i}]}@dominio.com") == "" ]]; then
                    remove
                else
                    SENHA=$(tr -d -c 'A-Za-z0-9' < /dev/urandom | head -c 8)
                    echo "Mudando a senha do usuario ${USUARIOS[${i}]} para ${SENHA}."
                    su - zimbra -c "zmprov sp ${USUARIOS[${i}]} ${SENHA}"
                    if [ "$?" == "0" ]; then
                        remove
                    else
                        echo "Nao foi possivel modificar a senha do ${USUARIOS[${i}]}"
                        echo "Favor verificar o que ocorreu!"
                        exit 1
                    fi
                fi
            fi 
        fi
    done
    if [ $COUNT == 0 ]; then
        echo "Nenhum usuario enviando spam!"
    fi
fi
if [ -f ${LOCK} ]; then
    exit 0
elif [[ ${MTASTATUS} != "Running" ]]; then
    echo "MTA Parado, parando o zimbra..."
    touch $LOCK
    su - zimbra -c "zmcontrol stop"
    if [ "$?" == "0" ]; then
        sleep 5
        echo "Iniciando o zimbra..."
        su - zimbra -c "zmcontrol start"
        if [ "$?" != "0" ]; then
            echo "Nao foi possivel iniciar o zimbra..."
            echo "Favor verificar o motivo!"
        fi
    else
         echo "Nao consegui parar o zimbra, por favor, verificar o motivo."
    fi 
    echo " "
    echo "That's all Folks!"
    rm -f $LOCK
fi
) > ${CHECK_MAIL_LOG} 2>&1
if [ -s ${CHECK_MAIL_LOG} ]; then
    cat ${CHECK_MAIL_LOG} | strings | mail -s "Verifca SPAM e MTA Status - ${DATA}" ${DTSMAIL[@]}
else
    rm -f ${CHECK_MAIL_LOG}
fi

find /var/log/ -maxdepth 1 -mtime +7 -name 'check_mail-*.log' -print | xargs rm -f
