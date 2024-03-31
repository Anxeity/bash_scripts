#!/bin/bash

PSQLUSER="postgres"
PFRLUSER="postgres1"
PSQLPASSWORD="postgres"
PSQLHOST="localhost:5432"
DATABASE="postgres"
connect_db_cc=$(echo "psql -t postgresql://$PSQLUSER:$PSQLPASSWORD@$PSQLHOST/$DATABASE")

##### check_installation_PostgreSQL #####
check_psql_exists() {
	if ! apt list --installed | grep postgre >/dev/null; then
		echo "-----> ERROR: PostgreSQL не установлен. Дальнейшая установка производиться не будет."
		exit 1
	else
		echo -e "\033[1;32m -----> PostgreSQL уже установлен. Проверка наличия юзера ${PFRLUSER}.\033[0m"
		check_user_postgres
	fi
}

### check_postgres_user ###
check_user_postgres() {
	role_exists=$(psql -U ${PSQLUSER} -d ${DATABASE} -tAc "SELECT 1 FROM pg_roles WHERE rolname = '"$PFRLUSER"'")
	if [[ $role_exists -eq 1 ]]; then
		echo -e " -----> Юзер ${PFRLUSER} уже существует. Дальнейшая установка производиться не будет."
		check_postgres_version_upgrade
		check_apssetings_exists
		exit 1
	else
		echo -e "\033[1;32m -----> Юзер ${PFRLUSER} не существует. Проверяется наличие $DATABASE.\033[0m"
		check_psql_connection
	fi
}

##### check_database_connect #####
check_psql_connection() {
	echo "\q" | $connect_db_cc >/dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo -e "\033[1;32m -----> База данных ${DATABASE} отсутствует.\033[0m"
		create_database
	else
		echo -e " -----> База данных $DATABASE уже развернута. Дальнейшая установка производиться не будет."
		exit 1
	fi
}

### creation_database_atmccdb ###
create_database() {
	echo -e "\033[1;32m -----> Разворачивание базы данных $DATABASE.\033[0m"
	#######New_delimiters_for_hostname##############
	main_addr=$(hostname -I | sed 's/ /, /g' | sed 's/, $/ /')

	sed -i "80,98s|peer|trust|g" /etc/postgresql/15/main/pg_hba.conf
	sed -i "80,106s|scram-sha-256|md5|g" /etc/postgresql/15/main/pg_hba.conf
	sed -i "s|host    all             all             127.0.0.1/32            md5|host    all             all             0.0.0.0/0            md5|g" /etc/postgresql/15/main/pg_hba.conf
	sed -i "90a\host    all             all             127.0.0.1/32            trust" /etc/postgresql/15/main/pg_hba.conf
	sed -i "91a\host    all             all             ::1/128                 trust" /etc/postgresql/15/main/pg_hba.conf
	echo "--->Файл pg_hba.conf сконфигурирован."
	sed -i "60s|#listen_addresses = 'localhost'|listen_addresses = '127.0.0.1, localhost, ${main_addr}'|g" /etc/postgresql/15/main/postgresql.conf
	sed -i "s|#shared_preload_libraries = ''|shared_preload_libraries = 'pg_cron'  # (change requires restart)\ncron.database_name = 'postgres'|g" /etc/postgresql/15/main/postgresql.conf
	echo "--->Файл postgresql.conf сконфигурирован."

	touch ~/.pgpass | echo "localhost:5432:postgres:postgres:postgres" >~/.pgpass
	echo "--->Файл pgpass создан"

	#####################!POSTGRESQL_REBOOT!#####################

	/etc/init.d/postgresql restart

	#####################!EDIT_POSTGRESQL_DB!#####################
	echo "--->Начало развертывания базы данных postgres"

	psql -U postgres -c "ALTER USER postgres PASSWORD 'admin';" -c "CREATE DATABASE postgres;" -c "create role pfr1;"

	psql -U postgres -d postgres </var/postgres.sql

	psql -U postgres -d postgres -c "CREATE EXTENSION pg_cron;" -c "GRANT USAGE ON SCHEMA cron TO postgres;"

	echo "INSERT INTO cron.job (schedule,command,nodename,nodeport,"database",username,active,jobname) VALUES
	     ('10 22 * * *','call rtu.job_AddPartition();','localhost',5432,'postgres','postgres',true,'job_AddPartition'),
	     ('0 * * * *','call stat.Data_on_15min_calc();','localhost',5432,'postgres','postgres',true,'Data_on_15min_calc'),
         ('0 0 4 * *','call stat.job_AddPartition_Month();','localhost',5432,'postgres','postgres',true,'job_AddPartition_Month'),
	     ('3,18,33,48 * * * *','call stat.job_conversation_data_ext_calc();','localhost',5432,'postgres','postgres',true,'job_conversation_data_ext_calc'),
	     ('5,20,35,50 * * * *','call stat.job_conversation_data_user_first_calc();','localhost',5432,'postgres','postgres',true,'job_conversation_data_user_first_calc');" >cron_job.sql

	psql -U postgres -d postgres <cron_job.sql
	echo "--->Развертывание базы данных завершено."

	#####################!REMOVE_FILES_AND SETTINGS!#####################

	rm cron_job.sql
	rm psql_users
	echo "--->Установка базы данных успешно завершена."
	check_apssetings_exists
}

### check_apssetings_gile ###
check_apssetings_exists() {
	if [ ! -f "/var/appsettings.json" ]; then
		echo "-----> ERROR: Файл appsettings.json не найден."
		exit 1
	else
		echo -e "\033[1;32m -----> Файл appsettings.json найден.\033[0m"
		edit_apssetings
	fi
}

### configuration appsettings.json ###
edit_apssetings() {
	echo -e "\033[1;32m -----> Конфигурирование appsettings.json.\033[0m"
	NEW_ADDR=$(hostname -I | cut -f1 -d' ')
	sed -i '10s|"Connection": "Host=127.0.0.1;Port=5432;Database=postgres;Username=postgres;Password=postgres",|"Connection": "Host='"$NEW_ADDR"';Port=5432;Database=postgres;Username=postgres;Password=postgres",|g' /var/www/appsettings.json
	sed -i '11s|"ConnectionReport": "Host=127.0.0.1;Port=5432;Database=postgres;Username=postgres;Password=postgres",|"ConnectionReport": "Host='"$NEW_ADDR"';Port=5432;Database=postgres;Username=postgres;Password=postgres",|g' /var/www/appsettings.json
	sed -i '20s|"Url": "ws://127.0.0.1:8335"|"Url": "ws://'"$NEW_ADDR"':8335"|g' /var/www/arm-backend/deployment/appsettings.json
	echo "--->Файл appsettings.json сконфигурирован."
}

### checking psql version and update to 15 version ###
check_postgres_version_upgrade() {
	echo "--->Проверка версии СУБД...."
	PG_VERSION_FULL=$(psql -V | awk '{print $3}')
	PG_VERSION=$(psql -V | cut -d' ' -f3 | cut -d'.' -f1)
	if [ "$PG_VERSION" -eq 12 ]; then
		echo "--->Текущая версия PostgreSQL: $PG_VERSION_FULL"
		echo "--->Происходит обновление PostgreSQL до версии 15..."
		echo "--->Делаем дамп базы atmccdb в директорию /home"
		pg_dump -U postgres postgres >/home/postgresdump.dump
		echo "--->Обновляем репозиторий....."
		upgade_repositories
		echo "--->Устанавливаем postgresql версии 15....."
		install_psql_and_dependencies
		echo "--->Останавливаем postgresql....."
		stop_psql
		echo "--->Переименование кластера...."
		rename_psql_cluster
		echo "--->Обновление кластера....."
		upgrade_psql_cluster
		echo "--->Удаление старого кластера....."
		drop_old_cluster
		echo "--->Удаление старых компонентов Postgres....."
		delete_old_components
		echo "--->Обновление Postgres завершено."
	else [ "$PG_VERSION" -eq 15 ]
		echo "--->Текущая версия PostgreSQL: $PG_VERSION_FULL"
		echo "--->Версия 15 или новее уже установлена. Обновление не требуется."
	fi
}

upgade_repositories(){
	sudo aptitude update
	if [ $? -eq 0 ]; then
  		echo "--->Репозитории успешно обновлены"
	else
  		echo "--->ERROR: Ошибка при обновлении репозитория"
	fi
}

install_psql_and_dependencies(){
	sudo apt install postgresql-15 postgresql-client-15 postgresql-15-cron
	if [ $? -eq 0 ]; then
  		echo "--->PostgreSQL успешно установлен"
	else
  		echo "--->ERROR: Ошибка при установке PostgreSQL"
	fi
}

stop_psql(){
	sudo systemctl stop postgresql
	if [ $? -eq 0 ]; then
  		echo "--->PostgreSQL успешно остановлен"
	else
  		echo "--->ERROR: Ошибка при остановке PostgreSQL"
	fi
}

rename_psql_cluster(){
	sudo pg_renamecluster 15 main mainold
	if [ $? -eq 0 ]; then
  		echo "--->Кластер успешно переименован"
	else
  		echo "--->ERROR: Ошибка при переименовании"
	fi
}

upgrade_psql_cluster(){
	sudo pg_upgradecluster 12 main
	if [ $? -eq 0 ]; then
  		echo "--->Кластер успешно обновлен"
	else
  		echo "--->ERROR: Ошибка при обновлении кластера"
	fi
}

drop_old_cluster(){
	sudo pg_dropcluster --stop 12 main
	if [ $? -eq 0 ]; then
  		echo "--->Кластер успешно удален"
	else
  		echo "--->ERROR: Ошибка при удалении старого кластера"
	fi
}

drop_temprary_cluster(){
	sudo pg_dropcluster --stop 15 mainold
	if [ $? -eq 0 ]; then
  		echo "--->Кластер успешно удален"
	else
  		echo "--->ERROR: Ошибка при удалении старого кластера"
	fi
}

delete_old_components(){
	dpkg -r --force-depends postgresql-12 postgresql-12-cron postgresql-client-12
	if [ $? -eq 0 ]; then
  		echo "--->Компаненты успешно удалены"
	else
  		echo "--->ERROR: Ошибка при удалении старых компанентов"
	fi
}

###Main_cycle###
check_psql_exists
