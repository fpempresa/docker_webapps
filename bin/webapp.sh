#!/bin/bash

#Falla el script si falla algun comando
set -e

#Es para permitir expresiones regulares
shopt -s extglob

#debug
#set -x

ProgName=$(basename $0)
CURDIR=`/bin/pwd`
BASEDIR=$(dirname $0)
ABSPATH=$(readlink -f $0)
ABSDIR=$(dirname $ABSPATH)

#echo "CURDIR is $CURDIR"
#echo "BASEDIR is $BASEDIR"
#echo "ABSPATH is $ABSPATH"
#echo "ABSDIR is $ABSDIR"

ENVIRONMENTS="PRODUCCION PREPRODUCCION PRUEBAS"

BASE_PATH=$ABSDIR/..
APP_NAME=$2
APP_ENVIRONMENT=$3
APP_BASE_PATH=$BASE_PATH/apps/$APP_NAME/$APP_ENVIRONMENT


NAME_DOCKER_IMAGE_TOMCAT=tomcat:7.0.94-jre7
NAME_DOCKER_IMAGE_MYSQL=mysql/mysql-server:5.5.61
NAME_DOCKER_IMAGE_PROXY=nginxproxy/nginx-proxy:1.7.0
NAME_DOCKER_IMAGE_LETSENCRYPT=nginxproxy/acme-companion:2.5.2
NAME_DOCKER_IMAGE_JDK_BUILDER=openjdk:7u181-jdk

ENABLED_LETSENCRYPT=1


#Cargar propiedades globales
. $BASE_PATH/config/global.config

sub_help(){
    echo "Uso: $ProgName <suborden> [opciones]"
    echo "Subordenes:"
    echo "    start_proxy : Inicia el proxy y sus dependencias (certificadoss,etc)."
    echo "    stop_proxy : Para el proxy y sus dependencias (certificadoss,etc)."
    echo "    restart_proxy : Reinicia el proxy y sus dependencias (certificadoss,etc)."
    echo "    restart_all : Reinicia el proxy y el resto de las aplicaciones web"
    echo ""
    echo "    add   : Añade una aplicacion y todos sus entornos. Pero no inicia las maquinas"
    echo "    remove   : Borrar una aplicación, Para las maquinas y borrar toda la información"
    echo ""
    echo "    start  <app name> <environment> : Inicia las máquinas un entorno de una aplicación "
    echo "    stop  <app name> <environment> : Para las máquina un entorno de una aplicación"
    echo "    restart  <app name> <environment> : Reinicia las máquinas de web y database un entorno de una aplicación pero sin borrar nada "
    echo "    restart_hard  <app name> <environment> : Reinicia las máquinas de web y database de un entorno de una aplicación pero borrando la base de datos y la aplicacion "
    echo ""
    echo "    deploy <app name> <environment> : Compila y Despliega la aplicacion en un entorno"
    echo ""
    echo "    backup_database  <app name> <environment> : Backup de la base de datos de un entorno"	
    echo "    restore_database  <app name> <environment>  [DIA|MES] [<numero>] [<backup_environment>]  : Restore de la base de datos de un entorno"	
    echo ""
    echo "    delete_logs  <app name> <environment> : Imprimer un mensaje. Se usapara comprobar probar si se tiene acceso al script"
}






urlencode() {
  local length="${#1}"
  for (( i = 0; i < length; i++ )); do
    local c="${1:i:1}"
    case $c in
      [a-zA-Z0-9.~_-]) printf "$c" ;;
      *) printf "$c" | xxd -p -c1 |
               while read x;
               do printf "%%%s" $(echo $x | tr "[:lower:]" "[:upper:]" );
               done
    esac
  done
}

encode_url_password() {
  local URL=$1

  local PASSWORD=$(echo $(echo $URL) | cut -d ":" -f3 | cut -d "@" -f1)
  local PASSWORD_ENCODED=$(urlencode $PASSWORD)
  local URL_ENCODED=$(echo $URL | sed "s/:[^:]*@/:$PASSWORD_ENCODED@/g")
  echo $URL_ENCODED
}


load_project_properties(){
  . $BASE_PATH/config/$APP_NAME.app.config
  URL_ENCODED=$(encode_url_password $GIT_REPOSITORY_PRIVATE)
  PATH_PRIVATE_DIR=$(mktemp -d --tmpdir=$BASE_PATH/tmp --suffix=.private)

  git clone -q $URL_ENCODED $PATH_PRIVATE_DIR

  PROJECT_PROPERTIES=$PATH_PRIVATE_DIR/proyecto.properties

  . $PROJECT_PROPERTIES

  rm -rf $PATH_PRIVATE_DIR
}


check_app_name_environment_arguments() {
if [ "$APP_NAME" == "" ]; then
	echo "El nombre de la app no puede estar vacio"
	sub_help
	exit 1
fi

if [ ! -f $BASE_PATH/config/${APP_NAME}.app.config ]; then
	echo "No existe el fichero de configuracion de la aplicacion"
	sub_help
	exit 1
fi

if [ "$APP_ENVIRONMENT" !=  "PRODUCCION" ] && [ "$APP_ENVIRONMENT" != "PREPRODUCCION" ] && [ "$APP_ENVIRONMENT" != "PRUEBAS" ]; then
        echo "El entorno no es valido"
        sub_help
	exit 1
fi
}


get_app_config_value() {
	KEY_NAME=$1

	VALUE=$(cat $BASE_PATH/config/${APP_NAME}.app.config | grep "^$1=" | cut -d "=" -f2)
	if [ -z "$VALUE" ]; then
		echo "No existe clave secreta en el fichero de configuracion"
		exit 1
	fi
	echo $VALUE
}

set_app_config_value() {
	KEY_NAME=$1
	VALUE=$2

	if [ ! -f $BASE_PATH/config/$APP_NAME.app.config ]; then
	   touch $BASE_PATH/config/$APP_NAME.app.config
	fi

	if [ -z "$(cat $BASE_PATH/config/$APP_NAME.app.config| grep ^${KEY_NAME}=)" ]; then
		echo ${KEY_NAME}=${VALUE} >> $BASE_PATH/config/$APP_NAME.app.config
	else 
		sed -i "s/${KEY_NAME}=.*/${KEY_NAME}=${VALUE}/g" $BASE_PATH/config/$APP_NAME.app.config
	fi

	STORED_VALUE=$(get_app_config_value ${KEY_NAME})

	if [ "$VALUE" != "$STORED_VALUE" ]; then
		echo "No se ha almacenado correctamente el valor ${VALUE} en ${KEY_NAME} ya que es $STORED_VALUE"
		exit 1
	fi
}


# SubOrdenes

sub_test_success() {
  echo "Script que tiene exito"
	echo "Args:"
	echo "$@"
  exit 0
}

sub_test_fail() {
  echo "Script que falla"
	echo "Args:"
	echo "$@"
  exit 1
}



sub_start_proxy(){


  mkdir -p $BASE_PATH/var/certs

  docker container \
      run \
      -d \
      -p 80:80 \
      -p 443:443 	\
			--restart always \
			-e TZ=Europe/Madrid \
			-v $BASE_PATH/var/certs:/etc/nginx/certs:ro \
			-v /etc/nginx/vhost.d \
			-v /usr/share/nginx/html \
			-v /var/run/docker.sock:/tmp/docker.sock:ro \
		  --label com.github.jrcs.letsencrypt_nginx_proxy_companion.nginx_proxy \
			--name nginx-proxy \
			${NAME_DOCKER_IMAGE_PROXY}

  docker container exec nginx-proxy bash -c "echo 'server_tokens off;' >> /etc/nginx/conf.d/no_tokens.conf"
  docker container restart nginx-proxy

  for APP_FILE_NAME in $(find $BASE_PATH/config -maxdepth 1 -name "*.app.config" -exec basename {} \;); do
		APP_NAME=$(echo ${APP_FILE_NAME} | sed -e "s/.app.config//")

    for APP_ENVIRONMENT in ${ENVIRONMENTS}; do
			if [ "$(docker network ls | grep  webapp-${APP_NAME}-${APP_ENVIRONMENT})" == "" ]; then
				docker network create webapp-${APP_NAME}-${APP_ENVIRONMENT}
			fi

			if [ "$(docker network inspect webapp-${APP_NAME}-${APP_ENVIRONMENT} | grep  nginx-proxy)" == "" ]; then
				docker network connect webapp-${APP_NAME}-${APP_ENVIRONMENT} nginx-proxy
			fi

    done
	done


if [ "${ENABLED_LETSENCRYPT}" == "1" ]; then

	docker run -d \
  	-v $BASE_PATH/var/certs:/etc/nginx/certs:rw \
  	-v /var/run/docker.sock:/var/run/docker.sock:ro \
  	--volumes-from nginx-proxy \
	--name letsencript \
	--restart always \
	-e DEFAULT_EMAIL=${GLOBAL_EMAIL} \
	${NAME_DOCKER_IMAGE_LETSENCRYPT}

fi



   echo "Proxy arrancado"
}

sub_stop_proxy(){
	set +e
  docker container stop nginx-proxy 
  docker container rm nginx-proxy 


  docker container stop letsencript
  docker container rm letsencript

   echo "Proxy parado"
   set -e
}

sub_restart_proxy(){
sub_stop_proxy
sub_start_proxy
}


sub_restart_all(){
	sub_restart_proxy

	for APP_FILE_NAME in $(find $BASE_PATH/config -maxdepth 1 -name "*.app.config" -printf "%f\n"); do
		APP_NAME=$(echo ${APP_FILE_NAME} | sed -e "s/.app.config//")
		for APP_ENVIRONMENT in ${ENVIRONMENTS}; do
			APP_BASE_PATH=$BASE_PATH/apps/$APP_NAME/$APP_ENVIRONMENT

			ENABLE_WEBAPP=$(get_app_config_value ${APP_ENVIRONMENT}_ENABLE_WEBAPP)

			echo "La app '$APP_NAME' en entorno $APP_ENVIRONMENT ENABLE_WEBAPP=${ENABLE_WEBAPP} "

			if [ "${ENABLE_WEBAPP}" == "1" ]; then
				sub_restart

			fi

		done
	done

}




sub_add(){

	APP_NAME=""
	while [ "$APP_NAME" == "" ]; do
		read  -p "Nombre de la aplicacion:" APP_NAME
	done

	if [ -d $BASE_PATH/apps/$APP_NAME ]; then
		echo "Ya existe la carpeta de la aplicación"
		exit 1
	fi
	if [ -f $BASE_PATH/config/$APP_NAME.app.config ]; then
		echo "Ya existe el fichero de configuracion"
		exit 1
	fi


	GIT_REPOSITORY_PRIVATE=""
	while [ "$GIT_REPOSITORY_PRIVATE" == "" ]; do
		read  -p "URL Git con las propiedades de la aplicación:" GIT_REPOSITORY_PRIVATE
	done

	HOUR_PERIODIC_TASKS=""
	while [ "$HOUR_PERIODIC_TASKS" == "" ]; do
		read  -p "Hora en la que ejecutar las tareas periodicas en todos los entornos (0-23):" HOUR_PERIODIC_TASKS
	done


	for APP_ENVIRONMENT in ${ENVIRONMENTS}; do
		mkdir -p $BASE_PATH/apps/$APP_NAME/${APP_ENVIRONMENT}/{database,database_logs,database_backup,web_logs,web_app,web_temp,dist}
	done 




	find $BASE_PATH/apps/$APP_NAME -type d -exec chmod 777 {} \;
	find $BASE_PATH/apps/$APP_NAME -type f -exec chmod 666 {} \;

	set_app_config_value GIT_REPOSITORY_PRIVATE $(echo $GIT_REPOSITORY_PRIVATE | sed "s/\\$/\\\\\$/g")
	set_app_config_value HOUR_PERIODIC_TASKS $HOUR_PERIODIC_TASKS
	for APP_ENVIRONMENT in ${ENVIRONMENTS}; do
		set_app_config_value ${APP_ENVIRONMENT}_ENABLE_WEBAPP 0
	done


	echo "Aplicacion añadida"
    
}

sub_remove(){



DELETE_APP_NAME=""
while [ "$DELETE_APP_NAME" == "" ]; do
	read  -p "Escriba el nombre de la aplicacion a borrar :" DELETE_APP_NAME
done


REPEAT_DELETE_APP_NAME=""
while [ "$REPEAT_DELETE_APP_NAME" == "" ]; do
	read  -p "Vuelva a escribir el nombre de la aplicacion :" REPEAT_DELETE_APP_NAME
done



if [ "$DELETE_APP_NAME" != "${REPEAT_DELETE_APP_NAME}" ]; then
	echo "El nombre de la aplicacion no coincide"
  exit 0
fi


YES_DELETE_APP=""
while [ "$YES_DELETE_APP" == "" ]; do
	read  -p "¿Esta Seguro que desea borrar la aplicación con todos sus entornos? Se borrarán todos los datos (yes/otra cosa):" YES_DELETE_APP
done
echo

if [ "$YES_DELETE_APP" != "yes" ]; then
  echo "No se borró la aplicacion. La respues no fue 'yes'"
  exit 0
fi


    APP_NAME=$DELETE_APP_NAME

    set +e
    for APP_ENVIRONMENT in ${ENVIRONMENTS}; do
      sub_stop

      set +e
      docker network disconnect ${APP_NAME}-${APP_ENVIRONMENT} nginx-proxy
      docker network rm ${APP_NAME}-${APP_ENVIRONMENT}
    done
	 set -e
    rm -rf $BASE_PATH/apps/$APP_NAME
    rm -f $BASE_PATH/config/$APP_NAME.app.config

   echo "Aplicacion Borrada"

}



start_database() {

  local REAL_HARD=0

  if [ "$HARD_START" == "1" ] || [ -z "$(ls -A $APP_BASE_PATH/database)" ]; then
		echo "Inicio Borrando de la base de datos"
    REAL_HARD=1
  fi

  if [ "$(docker network ls | grep  webapp-${APP_NAME}-${APP_ENVIRONMENT})" == "" ]; then
    docker network create webapp-${APP_NAME}-${APP_ENVIRONMENT}
  fi

  if [ "$(docker network inspect webapp-${APP_NAME}-${APP_ENVIRONMENT} | grep  nginx-proxy)" == "" ]; then
    docker network connect webapp-${APP_NAME}-${APP_ENVIRONMENT} nginx-proxy
  fi

  if [ "$REAL_HARD" == "1" ]; then
      rm -rf $APP_BASE_PATH/database/*
      rm -rf $APP_BASE_PATH/database_logs/*
  fi


  docker container run \
    -d \
    --name database-${APP_NAME}-${APP_ENVIRONMENT} \
    --restart always \
    --network=webapp-${APP_NAME}-${APP_ENVIRONMENT} \
    --mount type=bind,source="$APP_BASE_PATH/database",destination="/var/lib/mysql" \
    --mount type=bind,source="$APP_BASE_PATH/database_logs",destination="/var/log" \
    --mount type=bind,source="$APP_BASE_PATH/database_backup",destination="/home" \
    -e TZ=Europe/Madrid \
    -e MYSQL_ROOT_PASSWORD=root \
    -e MYSQL_DATABASE=${APP_NAME} \
    -e MYSQL_USER=${APP_NAME} \
    -e MYSQL_PASSWORD=${APP_NAME} \
    -e MYSQL_ROOT_HOST=% \
    ${NAME_DOCKER_IMAGE_MYSQL} \
    --lower_case_table_names=1 --max_allowed_packet=64M

  echo "Esperando a que arranque la base de datos..."
  sleep 10

  #Para que Jenkins tenga permisos en el log
  chmod ugo+r $APP_BASE_PATH/database_logs/*.log

  echo "Base de datos arrancada"
}


start_webapp() {

load_project_properties

  local REAL_HARD=0

  if [ "$HARD_START" == "1" ] || [ -z "$(ls -A $APP_BASE_PATH/web_app)" ]; then
		  echo "Inicio Borrando de la app web"
      REAL_HARD=1
  fi

  if [ "$APP_ENVIRONMENT" == "PRODUCCION" ]; then
    VIRTUAL_HOST=$DOMAIN_NAME_PRODUCCION
  elif [ "$APP_ENVIRONMENT" == "PREPRODUCCION" ]; then
    VIRTUAL_HOST=$DOMAIN_NAME_PREPRODUCCION
  elif [ "$APP_ENVIRONMENT" == "PRUEBAS" ]; then
    VIRTUAL_HOST=$DOMAIN_NAME_PRUEBAS
  else
    echo "Entorno erroneo $APP_ENVIRONMENT"
    exit 1
  fi


  if [ "$(docker network ls | grep  webapp-${APP_NAME}-${APP_ENVIRONMENT})" == "" ]; then
    docker network create webapp-${APP_NAME}-${APP_ENVIRONMENT}
  fi

  if [ "$(docker network inspect webapp-${APP_NAME}-${APP_ENVIRONMENT} | grep  nginx-proxy)" == "" ]; then
    docker network connect webapp-${APP_NAME}-${APP_ENVIRONMENT} nginx-proxy
  fi

  #Siempre se borra el directorio temp excepto la carpeta javamelody
  rm -rf $APP_BASE_PATH/web_temp/!("javamelody")


  if [ "$REAL_HARD" == "1" ]; then
      rm -rf $APP_BASE_PATH/web_app/*
      rm -rf $APP_BASE_PATH/web_logs/*
      rm -rf $APP_BASE_PATH/web_temp/*

      #Crear la app ROOT por defecto
      mkdir -p $APP_BASE_PATH/web_app/ROOT/{META-INF,WEB-INF}
      echo "<html><body>La aplicacion '${APP_NAME}' en el entorno de '${APP_ENVIRONMENT}' aun no esta instalada</body></html>" > $APP_BASE_PATH/web_app/ROOT/index.html
      echo '<?xml version="1.0" encoding="UTF-8"?><Context path=""/>' > $APP_BASE_PATH/web_app/ROOT/META-INF/context.xml
      find $APP_BASE_PATH/web_app -type d -exec chmod 777 {} \;
      find $APP_BASE_PATH/web_app -type f -exec chmod 666 {} \;
  fi

  docker container run \
    -d \
    --name tomcat-${APP_NAME}-${APP_ENVIRONMENT} \
    --expose 8080 \
    --restart always \
    --network=webapp-${APP_NAME}-${APP_ENVIRONMENT} \
    --hostname=tomcat-${APP_NAME}-${APP_ENVIRONMENT} \
    --mount type=bind,source="$APP_BASE_PATH/web_app",destination="/usr/local/tomcat/webapps" \
    --mount type=bind,source="$APP_BASE_PATH/web_logs",destination="/usr/local/tomcat/logs" \
    --mount type=bind,source="$APP_BASE_PATH/web_temp",destination="/usr/local/tomcat/temp" \
    -e TZ=Europe/Madrid \
    -e VIRTUAL_HOST=$VIRTUAL_HOST  \
    -e VIRTUAL_PORT=8080 \
    -e LETSENCRYPT_HOST=$VIRTUAL_HOST \
    -e LETSENCRYPT_EMAIL=${SERVICES_MASTER_EMAIL} \
    ${NAME_DOCKER_IMAGE_TOMCAT}

   echo "Web App arrancada"
}





sub_start(){

  check_app_name_environment_arguments

  
  start_database
  start_webapp

	sed -i "s/${APP_ENVIRONMENT}_ENABLE_WEBAPP=.*/${APP_ENVIRONMENT}_ENABLE_WEBAPP=1/g" $BASE_PATH/config/$APP_NAME.app.config

  echo "Arrancada aplicación ${APP_NAME}-${APP_ENVIRONMENT}"

}
  



sub_stop() {
  check_app_name_environment_arguments

  set +e
  docker container stop tomcat-${APP_NAME}-${APP_ENVIRONMENT}
  docker container stop database-${APP_NAME}-${APP_ENVIRONMENT}

  docker container rm tomcat-${APP_NAME}-${APP_ENVIRONMENT}
  docker container rm database-${APP_NAME}-${APP_ENVIRONMENT}

	sed -i "s/${APP_ENVIRONMENT}_ENABLE_WEBAPP=.*/${APP_ENVIRONMENT}_ENABLE_WEBAPP=0/g" $BASE_PATH/config/$APP_NAME.app.config
  set -e


  echo "Parada aplicación ${APP_NAME}-${APP_ENVIRONMENT}"
}



sub_restart_hard(){
  check_app_name_environment_arguments

  echo "Restart Hard"
  HARD_START=1

  sub_stop
  sub_start

}

sub_restart(){
  check_app_name_environment_arguments

  sub_stop
  sub_start

}










sub_restore_database(){

  check_app_name_environment_arguments

  load_project_properties

  if [ "$4" == "DIA" ]  || [ "$4" == "" ]; then
    PERIODO="DIA"
	
    if  [ "$5" == "" ]; then
      NUMERO=$(date +%u)
    else
      NUMERO=$5
    fi
  else
    echo debe ser DIA,  o vacio pero es $4
    sub_help
    exit 1
  fi	
  
  if [ "$6" == "" ]; then
    REAL_FILE_ENVIRONMENT=${APP_ENVIRONMENT}
  else
    REAL_FILE_ENVIRONMENT=$6
  fi

	if [ "$REAL_FILE_ENVIRONMENT" !=  "PRODUCCION" ] && [ "$REAL_FILE_ENVIRONMENT" != "PREPRODUCCION" ] && [ "$REAL_FILE_ENVIRONMENT" != "PRUEBAS" ]; then
		echo "El entorno del fichero de backup no es valido: $REAL_FILE_ENVIRONMENT"
		sub_help
		exit 1
	fi

	if [ "$APP_ENVIRONMENT" ==  "PRODUCCION" ] && [ "$REAL_FILE_ENVIRONMENT" !=  "PRODUCCION" ]; then
		echo "El entorno de produccion solo se puede restaurar desde un backup de produccion"
		sub_help
		exit 1
	fi






  FILE_NAME=${APP_NAME}-${REAL_FILE_ENVIRONMENT}-$PERIODO-$NUMERO-backup.zip
  URL_FTP_FILE=ftp://$FTP_BACKUP_HOST/$FTP_BACKUP_ROOT_PATH/$FILE_NAME
  echo decargando fichero de backup $URL_FTP_FILE
  rm -f $APP_BASE_PATH/database_backup/$FILE_NAME
  rm -f $APP_BASE_PATH/database_backup/backup.sql

  sshpass -p "$SFTP_BACKUP_PASSWORD" scp -o StrictHostKeyChecking=no -P "$SFTP_BACKUP_PORT" "$SFTP_BACKUP_USER"@"$SFTP_BACKUP_HOST":"$SFTP_BACKUP_ROOT_PATH/$FILE_NAME" "$APP_BASE_PATH/database_backup"
  #wget --user=$FTP_BACKUP_USER --password=$FTP_BACKUP_PASSWORD -P $APP_BASE_PATH/database_backup  $URL_FTP_FILE


  unzip -t $APP_BASE_PATH/database_backup/$FILE_NAME
  unzip -d $APP_BASE_PATH/database_backup  $APP_BASE_PATH/database_backup/$FILE_NAME
  rm -f $APP_BASE_PATH/database_backup/$FILE_NAME

  sub_stop


  rm -rf $APP_BASE_PATH/database/*
  start_database
  echo "Esperando 10 seg hasta que arranque" 
  sleep 10
  echo "Iniciando restauracion de la base de datos....." 
  cat $APP_BASE_PATH/database_backup/backup.sql | docker exec -i database-${APP_NAME}-${APP_ENVIRONMENT} /usr/bin/mysql -u root --password=root ${APP_NAME}
  rm -f $APP_BASE_PATH/database_backup/backup.sql
  echo "Base de datos restaurada" 
  sub_restart

  echo "Restore database completado"
}

sub_backup_database(){

  check_app_name_environment_arguments

  load_project_properties

  FILE_NAME_DIA=${APP_NAME}-${APP_ENVIRONMENT}-DIA-$(date +%u)-backup.zip


  rm -f $APP_BASE_PATH/database_backup/backup.sql
  rm -f $APP_BASE_PATH/database_backup/${APP_NAME}-${APP_ENVIRONMENT}*.zip
  echo "Iniciando export de la base de datos"
  docker exec database-${APP_NAME}-${APP_ENVIRONMENT} /usr/bin/mysqldump -u root --password=root ${APP_NAME} > $APP_BASE_PATH/database_backup/backup.sql

  zip -j $APP_BASE_PATH/database_backup/$FILE_NAME_DIA $APP_BASE_PATH/database_backup/backup.sql
  unzip -t $APP_BASE_PATH/database_backup/$FILE_NAME_DIA


echo "Subiendo copia por SFTP $APP_BASE_PATH/database_backup/$FILE_NAME_DIA"
sshpass -p "$SFTP_BACKUP_PASSWORD" scp -o StrictHostKeyChecking=no -P "$SFTP_BACKUP_PORT" "$APP_BASE_PATH/database_backup/$FILE_NAME_DIA" "$SFTP_BACKUP_USER"@"$SFTP_BACKUP_HOST":"$SFTP_BACKUP_ROOT_PATH/$FILE_NAME_DIA"
echo "Terminada copia por SFTP"

rm $APP_BASE_PATH/database_backup/$FILE_NAME_DIA 


echo "Backup database completado y subido"



}

sub_deploy() {

  check_app_name_environment_arguments

  load_project_properties

  rm -rf $APP_BASE_PATH/dist/*



encode_url_password $GIT_REPOSITORY_PRIVATE

pushd .
cd $APP_BASE_PATH/dist
echo "#!"/bin/bash > dist.sh


echo  "cd /opt/dist" >> dist.sh
echo  "rm -rf *" >> dist.sh
echo  "git clone -q $(encode_url_password $GIT_REPOSITORY_PRIVATE)" >> dist.sh

for i in `seq 1 9`;
do
  GIT_REPOSITORY_SOURCE_CODE=$(eval echo \$GIT_REPOSITORY_SOURCE_CODE_$i)

  if  [ ! "$GIT_REPOSITORY_SOURCE_CODE" == "" ]; then
    TARGET_DIR_REPOSITORY_SOURCE_CODE=$(eval echo \$TARGET_DIR_REPOSITORY_SOURCE_CODE_$i)
    GIT_BRANCH_SOURCE_CODE=$(eval echo \$GIT_BRANCH_SOURCE_CODE_$i)

    if [ "${APP_ENVIRONMENT}" == "PRODUCCION" ]; then
	BRANCH=$(echo $GIT_BRANCH_SOURCE_CODE | cut -d "," -f1)
    elif [ "${APP_ENVIRONMENT}" == "PREPRODUCCION" ]; then
        BRANCH=$(echo $GIT_BRANCH_SOURCE_CODE | cut -d "," -f2)
    elif [ "${APP_ENVIRONMENT}" == "PRUEBAS" ]; then
        BRANCH=$(echo $GIT_BRANCH_SOURCE_CODE | cut -d "," -f3)
    else
        echo "El nombre del entorno no es válido es '${APP_ENVIRONMENT}'"
	exit -1
    fi

    echo  "git clone -b $BRANCH $GIT_REPOSITORY_SOURCE_CODE  /opt/dist/$TARGET_DIR_REPOSITORY_SOURCE_CODE" >> dist.sh
  fi
done 

echo  "cd /opt/dist/$TARGET_DIR_REPOSITORY_SOURCE_CODE_1" >> dist.sh
echo  "./ant.sh -f dist.xml distDocker" >> dist.sh
echo  "cp dist/ROOT.war /opt/dist" >> dist.sh

chmod ugo+rx dist.sh

popd

  set +e
	docker container stop dist-${APP_NAME}-${APP_ENVIRONMENT}
	docker container rm dist-${APP_NAME}-${APP_ENVIRONMENT}
  set -e

  docker run \
  --name dist-${APP_NAME}-${APP_ENVIRONMENT} \
  --mount type=bind,source="$APP_BASE_PATH/dist",destination="/opt/dist" \
  -e APP_ENVIRONMENT=${APP_ENVIRONMENT} \
  -e TZ=Europe/Madrid \
  ${NAME_DOCKER_IMAGE_JDK_BUILDER} \
  /opt/dist/dist.sh

  docker container rm dist-${APP_NAME}-${APP_ENVIRONMENT}
  

  sub_stop

  rm -rf $APP_BASE_PATH/web_app/*
  cp $APP_BASE_PATH/dist/ROOT.war $APP_BASE_PATH/web_app

  rm -rf $APP_BASE_PATH/dist/*

  sub_start

   echo "Deploy completado"
}

sub_delete_logs() {
  check_app_name_environment_arguments
  find $APP_BASE_PATH/web_logs/* -mtime +15 -delete
  find $APP_BASE_PATH/database_logs/* -mtime +15 -delete

   echo "Logs borrados"
}

log_separators() {

	echo
	echo "***************************************************"
	echo "***************************************************"
	echo "***************************************************"
	echo "***************************************************"
	echo "***************************************************"
	echo "***************************************************"
	echo "***************************************************"
	echo
}

sub_docker_stats() {
	docker stats --no-stream | head -1 | sort -k2 && docker stats --no-stream | tail -n+2 | sort -k2
}

sub_docker_logs() {

	echo "******************BEGIN:docker logs nginx-proxy **************************"
	echo
	docker logs nginx-proxy
	echo -en "\e[0m"
	echo
	echo "******************END:docker logs nginx-proxy **************************"
	log_separators

	echo "******************BEGIN:docker logs letsencript **************************"
	echo
	docker logs letsencript
	echo -en "\e[0m"
	echo
	echo "******************END:docker logs letsencript **************************"
	log_separators

	echo "******************BEGIN:fail2ban **************************"
	echo
	fail2ban-client status
	echo -en "\e[0m"
	echo
	echo "******************END:fail2ban **************************"
	log_separators

}


subcommand=$1
case $subcommand in
    "" | "-h" | "--help")
        sub_help
        ;;
    *)
        sub_${subcommand} $@
        if [ $? = 127 ]; then
            echo "Error: '$subcommand' no es una suborden valida." >&2
            exit 1
        fi
        ;;
esac


