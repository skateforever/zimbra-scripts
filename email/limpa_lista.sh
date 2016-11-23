#!/bin/bash

LIMPA='usario@dominio.com'

for ID in `/opt/zimbra/postfix/sbin/postqueue -p | egrep "^[A-Z0-9]" | egrep ${LIMPA} | awk '{print $1}' | sed 's/\*//g'`
do
    /opt/zimbra/postfix/sbin/postsuper -d "$ID"
done
