#!/bin/bash
set -e
#set -x


#Para evitar ataques de fuerza bruta
apt install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban
#Para personalizar fail2ban usar el fichero jail.local
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
#guias fail2ban
#https://www.howtoforge.com/how-to-install-fail2ban-on-ubuntu-22-04/
#https://howto88.com/es/instale-configure-y-use-fail2ban-en-el-servidor-ubuntu-20-04-lts


#Para que se instale de forma automática los parches de seguridad 
apt install -y unattended-upgrades
dpkg-reconfigure unattended-upgrades


#Timezone
timedatectl set-timezone Europe/Madrid

#Reiniciar el servidor todas los domingos de madrugada
echo '0 7 * * 0 root reboot' >> /etc/crontab

mkdir /opt/backups_empleafp


