#!/bin/bash
cd /var/log
for LOG in maillog*
do
    read -p "Gerar relatorio de $LOG ? (S/N)" OPCAO
    if [ "$OPCAO" == "S" -o "$OPCAO" == "s" -o "$OPCAO" == "Y" -o "$OPCAO" == "y" ]; then
    for RBL in dnsbl.njabl.org zen.spamhaus.org dnsbl-1.uceprotect.net bl.spamcop.net dul.dnsbl.sorbs.net sbl-xbl.spamhaus.org
        do
            echo -n "Verificando $RBL - "
            grep "$RBL" /var/log/${LOG} | wc -l
        done
    fi 
done
