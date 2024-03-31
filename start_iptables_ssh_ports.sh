#!/bin/bash

# Установка зависимостей
apt update
apt -y install iptables iptables-persistent
apt -y install sudo

if  [ "$uid" = "0" ]
then
    echo "--->Запустите скрипт от имени root пользователя"
    exit

else
    # Создание пользователя с правами рут.
    echo "Введите логин создаваемого пользователя:"
    read input_login
    sudo adduser $input_login
    usermod -aG sudo $input_login
    echo "Общее количество пользователей с правами root: $(getent group sudo)"
    echo -e "Пользователь \033[1;32m$input_login\033[0m с правами root успешно создан."

    # Конфигурирование sshd запрет рутлогина.
    sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    # Авторизация по ключам
    ###sed -i 's/^#PubkeyAuthentication \(no\|yes\)/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
    ###sed -i 's/^#PasswordAuthentication \(no\|yes\)/PasswordAuthentication no/g' /etc/ssh/sshd_config
    systemctl restart sshd

    # Определяем сетевые интерфесы которые будут использоваться в iptables
    echo "Необходимо определить используемые сетевые интерфейсы:"
    echo "$(ip -br a show)"
    echo "Укажите внешний сетевой интерфейс:"
    read input_external
    echo "Укажите внутренний сетевой интерфейс:"
    read input_internal
    echo "Введите новый порт для SSH подключений (по умолчанию используется порт 22):"
    read input_ssh_port

    # Чистим существующую таблицу
    iptables -F

    # Дефолтная политика для входящих/исходящих/пересылаемых пакетов
    iptables -P INPUT DROP
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD DROP

    # Разрешаем на локальной петле
    iptables -A INPUT -i lo -j ACCEPT

    # Разрешаем все уже поднятые соединения
    iptables -A INPUT -p all -m state --state ESTABLISHED,RELATED -j ACCEPT

    # Предварительно необходимо поменять SSH.
    iptables -A INPUT -i ${input_internal} -p tcp -m tcp --dport ${input_ssh_port} -j ACCEPT
    iptables -A INPUT -i ${input_external} -p tcp -m tcp --dport ${input_ssh_port} -j ACCEPT
    sed -i "s/#Port 22/Port $input_ssh_port/" /etc/ssh/sshd_config
    iptables -A INPUT -i ${input_external} -p tcp -m multiport --dports 1711,4201,5059,5060,6050,8338,8431,8442,8342,8340,8332,8331,8336,8445 -m comment --comment "for main Service" -j ACCEPT
    iptables -A INPUT -i ${input_external} -p tcp -m tcp --dport 80 -j ACCEPT -m comment --comment "http"
    iptables -A INPUT -i ${input_external} -p tcp -m tcp --dport 443 -j ACCEPT -m comment --comment "https"
    iptables -A INPUT -i ${input_external} -p udp -m multiport --dports 5060,6050,10000:65535 -m comment --comment "media for MainService" -j ACCEPT

    # Опциональные порты для работы мобильных транков и голосового бота .( использовались для демостенда)
    iptables -A INPUT -s 192.168.0.1/32 -i ${input_external} -m comment --comment "ziax chatbot" -j ACCEPT
    iptables -A INPUT -s 192.168.0.1/32 -i ${input_external} -m comment --comment ziax -j ACCEPT
    iptables -A INPUT -s 192.168.0.1/32 -i ${input_external} -m comment --comment mobile -j ACCEPT
    iptables -A INPUT -s 192.168.0.1/32 -i ${input_external} -m comment --comment "textbot " -j ACCEPT

    systemctl restart sshd
    netfilter-persistent save
    systemctl enable netfilter-persistent
    echo "--->IPtables сконфигурирована, создан пользователь, запрещен логин рутом"
fi