#!/bin/bash

DATA=$(date +%Y%m%d)
YESTERDAY=$(date -d "1 day ago" '+%d%m%Y')
TWODAYSAGO=$(date -d "2 day ago" '+%m/%d/%Y')
TODAY=$(date '+%m/%d/%Y')
DAY_OF_WEEK=$(date +%a)

BACKUP_MNT=/mnt/backup/zimbra
BACKUP_CONFIG=${BACKUP_MNT}/config-${DATA}
BACKUP_FULLDIR=${BACKUP_MNT}/full-${DATA}
BACKUP_INCDIR=${BACKUP_MNT}/inc-${DATA}
BACKUP_LOG=/var/log/zimbra_backup-${DATA}.log

(
echo "$(date "+%H:%M") Realizando backup das configuracoes..."
if [ ! -d ${BACKUP_CONFIG} ]; then
    su - zimbra -c "mkdir -pv ${BACKUP_CONFIG}"
fi

echo "$(date "+%H:%M") Listando os dominios..."
su - zimbra -c "zmprov gad > ${BACKUP_CONFIG}/domains.txt"

echo "$(date "+%H:%M") Listando as contas de admin..."
su - zimbra -c "zmprov gaaa > ${BACKUP_CONFIG}/admins.txt"

echo "$(date "+%H:%M") Realizando backup das listas de distribuicao..."
if [ ! -d ${BACKUP_CONFIG}/listas ]; then
    su - zimbra -c "mkdir -pv ${BACKUP_CONFIG}/listas"
fi

echo "$(date "+%H:%M") Listando todas as listas de distribuicao..."
su - zimbra -c "zmprov gadl > ${BACKUP_CONFIG}/listas/00_listas_distribuicao.txt"

echo "$(date "+%H:%M") Listando todos os membros das listas de distribuicao..."
for LIST in $(su - zimbra -c "zmprov gadl"); do
    su - zimbra -c "zmprov gdlm ${LIST} > ${BACKUP_CONFIG}/listas/${LIST}_membros.txt"
done

echo "$(date "+%H:%M") Limpando listas vazias..."
find ${BACKUP_CONFIG}/listas/ -type f -empty -exec rm -f {} \+

echo "$(date "+%H:%M") Realizando backup dos alias..."
if [ ! -d ${BACKUP_CONFIG}/aliases/ ]; then
    su - zimbra -c "mkdir -pv ${BACKUP_CONFIG}/aliases"
fi

for USER in $(su - zimbra -c "zmprov -l gaa | sort | grep -vE \"^spam|^virus|^hal|^galsync|^zmbackup|^ldap\""); do
    su - zimbra -c "zmprov ga ${USER} | grep zimbraMailAlias" | awk '{print $2}' > ${BACKUP_CONFIG}/aliases/${USER}.txt
done

echo "$(date "+%H:%M") Limpando aliases vazios..."
find ${BACKUP_CONFIG}/aliases/ -type f -empty -exec rm -f {} \+

echo "$(date "+%H:%M") Listando nome e senha dos usuários..."
for USER in $(su - zimbra -c "zmprov -l gaa | sort | grep -vE \"^spam|^virus|^hal|^galsync|^zmbackup|^ldap\""); do
    SENHA=$(su - zimbra -c "zmprov -l ga ${USER} userPassword" | grep userPassword: | awk '{ print $2}')
    DISPLAY_NAME=$(su - zimbra -c "zmprov ga ${USER}" | grep -E ^displayName | cut -d " " -f 2-)
    su - zimbra -c "echo \"${USER}:${SENHA}:${DISPLAY_NAME}\"" >> ${BACKUP_CONFIG}/users.txt
done

if [ "${DAY_OF_WEEK}" == "Sun" ]; then
    echo "$(date "+%H:%M") Realizando o backup full das contas..."
    if [ ! -d ${BACKUP_FULLDIR} ]; then
        su - zimbra -c "mkdir -pv ${BACKUP_FULLDIR}"
    fi

    for USER in $(su - zimbra -c "zmprov -l gaa | sort | grep -vE \"^spam|^virus|^hal|^galsync|^zmbackup|^ldap\""); do
        su - zimbra -c "zmmailbox -z -m ${USER} getRestURL '/?fmt=tgz' > ${BACKUP_FULLDIR}/${USER}-full-${DATA}.tgz" 2> /dev/null
        sleep 2
    done

    echo "Validando o backup..."
    for USER in $(su - zimbra -c "zmprov -l gaa | sort | grep -vE \"^spam|^virus|^hal|^galsync|^zmbackup|^ldap\""); do
        ls -lha -I. -I.. ${BACKUP_FULLDIR}/ | grep "${USER}"
        if (( $? != 0 )); then
            su - zimbra -c "zmmailbox -z -m ${USER} getRestURL '/?fmt=tgz' > ${BACKUP_FULLDIR}/${USER}-full-${DATA}.tgz" 2> /dev/null
            sleep 2
        fi
    done

    echo "$(date "+%H:%M") Limpando backups vazios..."
    find ${BACKUP_FULLDIR}/ -type f -empty -exec rm -f {} \+
else
    echo "$(date "+%H:%M") Realizando o backup incremental das contas..."
    if [ ! -d ${BACKUP_INCDIR} ]; then
        su - zimbra -c "mkdir -pv ${BACKUP_INCDIR}"
    fi

    for USER in $(su - zimbra -c "zmprov -l gaa | sort | grep -vE \"^spam|^virus|^hal|^galsync|^zmbackup|^ldap\""); do
        su - zimbra -c "zmmailbox -z -m ${USER} getRestURL '/?fmt=tgz&query=after:\"${TWODAYSAGO}\" and before:\"${TODAY}\"' > ${BACKUP_INCDIR}/${USER}-${YESTERDAY}.tgz" 2> /dev/null
        sleep 2
    done

    echo "Validando o backup..."
    for USER in $(su - zimbra -c "zmprov -l gaa | sort | grep -vE \"^spam|^virus|^hal|^galsync|^zmbackup|^ldap\""); do
        ls -lha -I. -I.. ${BACKUP_FULLDIR}/ | grep "${USER}"
        if (( $? != 0 )); then
            su - zimbra -c "zmmailbox -z -m ${USER} getRestURL '/?fmt=tgz&query=after:\"${TWODAYSAGO}\" and before:\"${TODAY}\"' > ${BACKUP_INCDIR}/${USER}-${YESTERDAY}.tgz" 2> /dev/null
            sleep 2
        fi
    done

    echo "$(date "+%H:%M") Limpando backups vazios..."
    find ${BACKUP_INCDIR}/ -type f -empty -exec rm -f {} \+
fi

echo "Backup finalizado as $(date "+%H:%M")!"
) >> ${BACKUP_LOG}

find /mnt/backup/zimbra/ -mtime +30 -type d -execdir rm -rf {} \+
find /var/log/zimbra_backup-* -mtime +7 -type f -exec rm -rf {} \+
