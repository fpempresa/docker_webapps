# docker_webapps
Nueva versión de los scripts de creación de EmpleaFP

``` script
passwd
apt -y update
apt -y upgrade
reboot
cd /opt
git clone https://github.com/fpempresa/docker_webapps.git
cd ./docker_webapps/bin
./install.sh

```

Y despues de instalar todo deberás para cada aplicación

``` script
./webapp.sh add 
```


# Para el servidor de backup

``` script
passwd
apt -y update
apt -y upgrade
reboot
cd /opt
git clone https://github.com/fpempresa/docker_webapps.git
cd ./docker_webapps/bin
./install_backup.sh

```
