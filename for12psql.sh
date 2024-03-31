#!/bin/bash

PSQLUSER="user"
PFRLUSER="user_last"
PSQLPASSWORD="userpass"
PSQLHOST="localhost:5432"
DATABASE="dbname"
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
		echo -e " -----> ERROR: Юзер ${PFRLUSER} уже существует. Дальнейшая установка производиться не будет."
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
		echo -e " -----> ERROR: База данных $DATABASE уже развернута. Дальнейшая установка производиться не будет."
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
	sed -i "s|#shared_preload_libraries = ''|shared_preload_libraries = 'pg_cron'  # (change requires restart)\ncron.database_name = 'dbname'|g" /etc/postgresql/15/main/postgresql.conf
	echo "--->Файл postgresql.conf сконфигурирован."

	touch ~/.pgpass | echo "localhost:5432:dbname:postgres:postgres" >~/.pgpass
	echo "--->Файл pgpass создан"

	#####################!POSTGRESQL_REBOOT!#####################

	/etc/init.d/postgresql restart

	#####################!EDIT_POSTGRESQL_DB!#####################
	echo "--->Начало развертывания базы данных dbname"

	psql -U postgres -c "ALTER USER postgres PASSWORD 'postgres';" -c "CREATE DATABASE dbname;" -c "create role pfr1;"

	psql -U postgres -d atmccdb </var/db/arm-backend/install_script/atmccdb.sql

	psql -U postgres -d atmccdb -c "CREATE EXTENSION pg_cron;" -c "GRANT USAGE ON SCHEMA cron TO postgres;"

	echo "INSERT INTO cron.job (schedule,command,nodename,nodeport,"database",username,active,jobname) VALUES
	     ('10 22 * * *','call rtu.job_AddPartition();','localhost',5432,'dbname','postgres',true,'job_AddPartition'),
	     ('0 * * * *','call stat.Data_on_15min_calc();','localhost',5432,'dbname','postgres',true,'Data_on_15min_calc'),
         ('0 0 4 * *','call stat.job_AddPartition_Month();','localhost',5432,'dbname','postgres',true,'job_AddPartition_Month'),
	     ('3,18,33,48 * * * *','call stat.job_conversation_data_ext_calc();','localhost',5432,'dbname','postgres',true,'job_conversation_data_ext_calc'),
	     ('5,20,35,50 * * * *','call stat.job_conversation_data_user_first_calc();','localhost',5432,'dbname','postgres',true,'job_conversation_data_user_first_calc');"  > cron_job.sql

	psql -U postgres -d dbname <cron_job.sql
	echo "--->Развертывание базы данных завершено."

	#####################!REMOVE_FILES_AND SETTINGS!#####################

	rm cron_job.sql
	rm psql_users
	echo "--->Установка базы данных успешно завершена."
	check_apssetings_exists
}

### check_apssetings_gile ###
check_apssetings_exists() {
	if [ ! -f "/var/www/appsettings.json" ]; then
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
	sed -i '10s|"Connection": "Host=127.0.0.1;Port=5432;Database=dbname;Username=postgres;Password=postgres",|"Connection": "Host='"$NEW_ADDR"';Port=5432;Database=dbname;Username=postgres;Password=postgres",|g' /var/www/arm-backend/deployment/appsettings.json
	sed -i '11s|"ConnectionReport": "Host=127.0.0.1;Port=5432;Database=dbname;Username=postgres;Password=postgres",|"ConnectionReport": "Host='"$NEW_ADDR"';Port=5432;Database=dbname;Username=postgres;Password=postgres",|g' /var/www/arm-backend/deployment/appsettings.json
	sed -i '20s|"Url": "ws://127.0.0.1:8335"|"Url": "ws://'"$NEW_ADDR"':8335"|g' /var/www/appsettings.json
	echo "--->Файл appsettings.json сконфигурирован."
}

###Main_cycle###
check_psql_exists
