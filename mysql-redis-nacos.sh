#!/bin/bash

# 脚本编写人：Ronnie
# TG频道：https://t.me/cryptothrifts

# 检查是否以root用户运行
if [ "$(id -u)" != "0" ]; then
   echo "此脚本必须以root用户运行。" 1>&2
   exit 1
fi

######################
# 安装 MySQL 并配置
######################
install_mysql() {
    echo "安装 MySQL..."
    
    # 安装MySQL
    apt-get install -y mysql-server
    
    # 启动MySQL服务
    systemctl start mysql
    systemctl enable mysql

    # 设置MySQL root密码
    read -s -p "请输入MySQL root用户密码: " mysql_root_password
    echo
    mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysql_root_password}'; FLUSH PRIVILEGES;"

    # 配置MySQL监听端口
    read -p "请输入MySQL监听端口（默认3306）: " mysql_port
    mysql_port=${mysql_port:-3306}

    # 修改或添加port配置
    if grep -q "^# *port" /etc/mysql/mysql.conf.d/mysqld.cnf; then
        sed -i "s/^# *port.*/port = ${mysql_port}/" /etc/mysql/mysql.conf.d/mysqld.cnf
    elif grep -q "^port" /etc/mysql/mysql.conf.d/mysqld.cnf; then
        sed -i "s/^port.*/port = ${mysql_port}/" /etc/mysql/mysql.conf.d/mysqld.cnf
    else
        echo "port = ${mysql_port}" >> /etc/mysql/mysql.conf.d/mysqld.cnf
    fi

    # 允许MySQL外部连接（可选）
    read -p "是否允许MySQL被外部连接? (y/n): " allow_external
    if [ "$allow_external" == "y" ]; then
        sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf
        mysql -uroot -p"${mysql_root_password}" -e "CREATE USER 'root'@'%' IDENTIFIED BY '${mysql_root_password}'; GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION; FLUSH PRIVILEGES;"
    else
        sed -i "s/^bind-address.*/bind-address = 127.0.0.1/" /etc/mysql/mysql.conf.d/mysqld.cnf
    fi

    # 重启MySQL服务以应用新配置
    systemctl restart mysql

    echo "MySQL 安装和配置完成，监听端口: ${mysql_port}。"
}


######################
# 卸载 MySQL
######################
uninstall_mysql() {
    echo "卸载 MySQL..."

    # 停止MySQL服务
    systemctl stop mysql

    # 卸载MySQL和相关包
    apt-get remove --purge -y mysql-server mysql-client mysql-common
    apt-get autoremove -y
    apt-get autoclean

    # 删除MySQL数据和配置文件
    rm -rf /etc/mysql /var/lib/mysql /var/log/mysql

    echo "MySQL 卸载完成。"
}

######################
# 创建MySQL数据库和用户
######################
create_mysql_database_and_user() {
    echo "创建MySQL数据库和用户..."

    # 获取MySQL root用户密码
    read -s -p "请输入MySQL root用户密码: " mysql_root_password
    echo
    
    # 创建新数据库
    read -p "请输入新数据库名称: " new_database
    mysql -uroot -p"${mysql_root_password}" -e "CREATE DATABASE ${new_database};"

    # 创建新用户
    read -p "请输入新用户名称: " new_user
    read -s -p "请输入新用户密码: " new_user_password
    echo

    # 选择用户连接权限范围
    echo "请选择新用户的连接权限范围:"
    echo "1) 仅允许从本地主机连接 (localhost)"
    echo "2) 允许从任何主机连接 (%)"
    echo "3) 仅允许从特定IP地址连接"
    read -p "请输入选项 [1-3]: " connection_choice

    case $connection_choice in
        1)
            host="localhost"
            ;;
        2)
            host="%"
            ;;
        3)
            read -p "请输入允许连接的IP地址: " host
            ;;
        *)
            echo "无效的选项，默认使用localhost。"
            host="localhost"
            ;;
    esac

    # 创建用户并赋予权限
    mysql -uroot -p"${mysql_root_password}" -e "CREATE USER '${new_user}'@'${host}' IDENTIFIED BY '${new_user_password}';"
    mysql -uroot -p"${mysql_root_password}" -e "GRANT ALL PRIVILEGES ON ${new_database}.* TO '${new_user}'@'${host}'; FLUSH PRIVILEGES;"

    echo "MySQL 用户和数据库创建完成。"
}

######################
# 修改MySQL数据库参数
######################
modify_mysql_parameters() {
    echo "修改MySQL数据库参数..."

    # 获取MySQL配置文件路径
    mysql_config_file="/etc/mysql/mysql.conf.d/mysqld.cnf"

    # 显示当前的配置参数
    echo "当前的MySQL配置参数如下："
    grep -E "^(bind-address|port|max_connections|innodb_buffer_pool_size)" $mysql_config_file

    # 提示用户输入新的参数值
    read -p "请输入新的MySQL监听端口（按Enter键跳过以保持当前设置）: " mysql_port
    if [ ! -z "$mysql_port" ];then
        sed -i "s/^port.*/port = ${mysql_port}/" $mysql_config_file
        echo "已将MySQL端口修改为: ${mysql_port}"
    fi

    read -p "请输入新的max_connections值（按Enter键跳过以保持当前设置）: " max_connections
    if [ ! -z "$max_connections" ];then
        sed -i "s/^max_connections.*/max_connections = ${max_connections}/" $mysql_config_file
        echo "已将max_connections修改为: ${max_connections}"
    fi

    read -p "请输入新的innodb_buffer_pool_size值（按Enter键跳过以保持当前设置，例如512M）: " innodb_buffer_pool_size
    if [ ! -z "$innodb_buffer_pool_size" ];then
        sed -i "s/^innodb_buffer_pool_size.*/innodb_buffer_pool_size = ${innodb_buffer_pool_size}/" $mysql_config_file
        echo "已将innodb_buffer_pool_size修改为: ${innodb_buffer_pool_size}"
    fi

    # 重启MySQL服务以应用新配置
    systemctl restart mysql

    echo "MySQL 参数修改完成。"
}

######################
# 安装 Redis 并配置
######################
install_redis() {
    echo "安装 Redis..."
    
    # 安装Redis
    apt-get install -y redis-server

    # 配置Redis监听端口
    read -p "请输入Redis监听端口（默认6379）: " redis_port
    redis_port=${redis_port:-6379}
    sed -i "s/^port .*/port ${redis_port}/" /etc/redis/redis.conf

    # 配置Redis密码
    read -s -p "请输入Redis密码: " redis_password
    echo
    sed -i "s/^# requirepass .*/requirepass ${redis_password}/" /etc/redis/redis.conf

    # 设置Redis最大内存
    read -p "请输入Redis最大内存（如1gb）: " redis_maxmemory
    sed -i "s/^# maxmemory .*/maxmemory ${redis_maxmemory}/" /etc/redis/redis.conf
    sed -i "s/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/" /etc/redis/redis.conf

    # 设置是否允许Redis外部连接
    read -p "是否允许Redis被外部连接? (y/n): " allow_redis_external
    if [ "$allow_redis_external" == "y" ];then
        sed -i "s/^bind .*/bind 0.0.0.0/" /etc/redis/redis.conf
    else
        sed -i "s/^bind .*/bind 127.0.0.1/" /etc/redis/redis.conf
    fi

    # 重启Redis服务以应用新配置
    systemctl restart redis-server
    systemctl enable redis-server

    echo "Redis 安装和配置完成，监听端口: ${redis_port}。"
}

######################
# 卸载 Redis
######################
uninstall_redis() {
    echo "卸载 Redis..."

    # 停止Redis服务
    systemctl stop redis-server

    # 卸载Redis和相关包
    apt-get remove --purge -y redis-server
    apt-get autoremove -y
    apt-get autoclean

    # 删除Redis数据和配置文件
    rm -rf /etc/redis /var/lib/redis

    echo "Redis 卸载完成。"
}

######################
# 安装 Nacos 并配置
######################
install_nacos() {
    echo "安装 Nacos..."
    
    # 安装所需的Java环境
    apt-get install -y openjdk-11-jdk

    # 下载Nacos
    wget https://github.com/alibaba/nacos/releases/download/2.2.3/nacos-server-2.2.3.tar.gz
    tar -zxvf nacos-server-2.2.3.tar.gz -C /usr/local/
    mv /usr/local/nacos /usr/local/nacos-server

    # 设置Nacos监听端口
    read -p "请输入Nacos监听端口（默认8848）: " nacos_port
    nacos_port=${nacos_port:-8848}

    # 修改Nacos的配置文件以更改监听端口
    sed -i "s/^server.port=.*/server.port=${nacos_port}/" /usr/local/nacos-server/conf/application.properties

    # 配置 Nacos 数据库
    echo "配置 Nacos 使用 MySQL 数据库"
    read -p "请输入 MySQL 数据库名称: " nacos_db_name
    read -p "请输入 MySQL 用户名: " nacos_db_user
    read -s -p "请输入 MySQL 用户密码: " nacos_db_password
    echo
    read -p "请输入 MySQL 服务器地址（如 localhost 或 IP 地址）: " mysql_host
    read -p "请输入 MySQL 端口（默认 3306）: " mysql_port
    mysql_port=${mysql_port:-3306}

    # 在 Nacos 配置文件中设置数据库连接信息
    cat <<EOT >> /usr/local/nacos-server/conf/application.properties
spring.datasource.platform=mysql
db.num=1
db.url.0=jdbc:mysql://${mysql_host}:${mysql_port}/${nacos_db_name}?characterEncoding=utf8&connectTimeout=1000&socketTimeout=3000&autoReconnect=true&useUnicode=true&useSSL=false&serverTimezone=UTC&allowPublicKeyRetrieval=true
db.user=${nacos_db_user}
db.password=${nacos_db_password}
EOT

    # 创建Nacos启动脚本
    cat <<EOT >> /etc/systemd/system/nacos.service
[Unit]
Description=Nacos Server
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/nacos-server/bin/startup.sh -m standalone
ExecStop=/usr/local/nacos-server/bin/shutdown.sh
User=root
Group=root
Restart=always

[Install]
WantedBy=multi-user.target
EOT

    # 重新加载服务并启动Nacos
    systemctl daemon-reload
    systemctl start nacos
    systemctl enable nacos

    echo "Nacos 安装和配置完成，监听端口: ${nacos_port}。"
}

######################
# 卸载 Nacos
######################
uninstall_nacos() {
    echo "卸载 Nacos..."

    # 停止Nacos服务
    systemctl stop nacos

    # 删除Nacos文件
    rm -rf /usr/local/nacos-server

    # 删除Nacos服务脚本
    rm /etc/systemd/system/nacos.service

    # 重新加载systemd守护进程
    systemctl daemon-reload

    echo "Nacos 卸载完成。"
}

######################
# 主菜单
######################
echo "请选择要执行的操作:"
echo "1) 安装 MySQL"
echo "2) 卸载 MySQL"
echo "3) 创建MySQL数据库和用户"
echo "4) 修改MySQL数据库参数"
echo "5) 安装 Redis"
echo "6) 卸载 Redis"
echo "7) 安装 Nacos"
echo "8) 卸载 Nacos"
echo "9) 安装 MySQL, Redis, Nacos"

read -p "请输入选项 [1-9]: " choice

case $choice in
    1)
        install_mysql
        ;;
    2)
        uninstall_mysql
        ;;
    3)
        create_mysql_database_and_user
        ;;
    4)
        modify_mysql_parameters
        ;;
    5)
        install_redis
        ;;
    6)
        uninstall_redis
        ;;
    7)
        install_nacos
        ;;
    8)
        uninstall_nacos
        ;;
    9)
        install_mysql
        install_redis
        install_nacos
        ;;
    *)
        echo "无效的选项。"
        ;;
esac

echo "脚本执行完成。"
