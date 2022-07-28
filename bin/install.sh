#!/bin/bash
set -e
#set -x



ProgName=$(basename $0)
ABSPATH=$(readlink -f $0)
ABSDIR=$(dirname $ABSPATH)


BASE_PATH=$ABSDIR/..




#Software basico
apt install -y apache2-utils zip unzip curl

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

#Instalar Docker
set +e
apt-get remove docker docker-engine docker.io containerd runc 
set -e
apt-get install ca-certificates curl gnupg lsb-release
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin

#Establecer el tamaño de los log
systemctl stop docker.service
echo "{  \"log-driver\": \"json-file\",    \"log-opts\": {        \"max-size\": \"20m\",        \"max-file\": \"8\"    } }" > /etc/docker/daemon.json
systemctl start docker.service
systemctl enable docker.service

#Timezone
timedatectl set-timezone Europe/Madrid

#Reiniciar el servidor todas los domingos de madrugada
echo '0 7 * * 0 root reboot' >> /etc/crontab

#Iniciar el proxy
$BASE_PATH/bin/webapp.sh start_proxy


echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo ""
echo "Ahora deberas añadir las aplicaciones con:"
echo "./webapp.sh add "
echo "Para manejar las tareas, usa acciones de github en repositorios distintos para cada entorno "
