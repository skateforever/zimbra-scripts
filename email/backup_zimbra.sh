#!/bin/bash

################################################################################################################
#                                                                                                              #
# Autor: Leandro Carvalho <carvalho.inacio@gmail.com>                                                          #
# Versao 20150413                                                                                              #
#                                                                                                              #
# Secretaria de Saude do Estado de Alagoas                                                                     #
# Automatizacao de Servicos de backup                                                                          #
# Limpa os logs com mais de 7 dias                                                                             #
# Toda a acao sera informada por email                                                                         #
#                                                                                                              #
################################################################################################################

HR=$(date +%H)
DATA=$(date +%Y%m%d-%H%M)
SUN=$(date +%a)

RSYNC_LOG=/var/log/zimbra_rsync-${DATA}.log
LOCK=/tmp/check_spam.lock

DTSMAIL=(emails@dominio.com)

(
if [ -f ${LOCK} ]; then
    echo "Arquivo de lock encontrado, favor verificar o que aconteceu." >> ${RSYNC_LOG}
    exit 0
else
    echo "${DATA}"
    echo "Criando o arquivo de lock..."
    touch ${LOCK}
    mount | grep "media/backup"
    if [ $? != 0 ]; then
        mount /dev/disk/by-id/"UUID_DO_DISCO" /mnt/backup
        if [ $? != 0 ]; then
            echo "Nao foi possivel montar o HD!"
            RESULTADO="FALHOU"
            exit 1
        else
            # verificando se consegue ler o disco
	    # se conseguir realiza o backup
            ls /mnt/backup > /dev/null 2>&1
            if [ $? == 0 ]; then
                echo "Parando o zimbra" 
                su - zimbra -c "zmcontrol stop"
                if [ $? == 0 ]; then
                    echo "Inicio da sincronizacao"
                    rsync -azt --delete --progress --stats /opt/zimbra/ /mnt/backup/zimbra
                    if [ $? == 0 ]; then
                        echo "Fim da sincronizacao!"
                        echo "Backup Realizado com Sucesso!"
                        echo "Iniciando o zimbra!"
                        su - zimbra -c "zmcontrol start"
                        if [ $? != 0 ]; then
                            RESULTADO="FALHOU"
                            echo "Falha ao iniciar o zimbra, favor verificar o motivo!"
                            exit 1 
                        else
                            RESULTADO="OK"
                        fi
                    fi
                else
                     echo "Nao foi possivel realizar o backup do zimbra!"
                     RESULTADO="FALHOU"
                     exit 1
                fi
            else
                echo "Nao foi possivel fazer o backup!"
                echo "Possivel erro de entrada e saida"
                exit 1
            fi
        fi
    else
        echo "Nao foi possivel parar o zimbra para realizar o backup"
    fi
fi
if [ ! -d /mnt/backup/scripts ]; then
    mkdir -p /mnt/backup/scripts
else
    cp -av /usr/local/sbin/* /mnt/backup/scripts/
fi
rm -f ${LOCK}
umount /mnt/backup
) > ${RSYNC_LOG} 2>&1
cat ${RSYNC_LOG} | strings | mail -s "Backup Zimbra ${RESULTADO} - ${DATA}" ${DTSMAIL[@]}

find /var/log/ -maxdepth 1 -mtime +7 -name 'zimbra_rsync-*.log' -print | xargs rm -f
