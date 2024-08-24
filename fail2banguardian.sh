#!/bin/bash

# 开发者: 857
# Telegram 频道: https://t.me/cryptothrifts
# 功能: 自动安装、配置 fail2ban，支持多服务保护、设置封禁时长和失败条件、自定义防火墙规则、解封IP、邮件通知、Cloudflare集成等功能
# 适配操作系统: Ubuntu/Debian/CentOS

if [ "$EUID" -ne 0 ]; then
  echo "请以 root 用户身份运行此脚本。" 
  exit 1
fi

echo "开发人: 857"
echo "Telegram 频道: https://t.me/cryptothrifts"
echo "脚本功能: 自动安装、配置 fail2ban，支持多服务保护、设置封禁时长、失败条件、白名单、自定义防火墙规则、解封IP、邮件通知和Cloudflare集成等功能"
echo "适配操作系统: Ubuntu/Debian/CentOS"
echo "========================================"

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "无法检测操作系统类型，脚本停止。"
    exit 1
fi

install_fail2ban() {
    echo "开始安装 fail2ban..."
    
    case $OS in
        ubuntu|debian)
            sudo apt-get update
            sudo apt-get install -y fail2ban mailutils
            ;;
        centos|rhel|fedora)
            sudo yum install -y epel-release
            sudo yum install -y fail2ban mailx
            ;;
        *)
            echo "不支持的操作系统：$OS"
            exit 1
            ;;
    esac
}

configure_service() {
    local service_name=$1
    local port=$2
    local log_path=$3
    
    if ! grep -q "\[$service_name\]" /etc/fail2ban/jail.local; then
        sudo bash -c "cat >> /etc/fail2ban/jail.local <<EOL

[$service_name]
enabled = true
port = $port
logpath = $log_path
bantime = $BAN_TIME
findtime = $FIND_TIME
maxretry = $MAX_RETRY
ignoreip = $IGNORE_IPS
EOL"
    else
        echo "$service_name 已经配置，跳过。"
    fi
}

configure_service_protection() {
    echo "配置 fail2ban 来保护多个服务并自定义规则..."

    if [ ! -f /etc/fail2ban/jail.local ]; then
        sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    fi

    read -p "请输入封禁时长（秒，默认3600秒/1小时）: " BAN_TIME
    BAN_TIME=${BAN_TIME:-3600}
    
    read -p "请输入失败检测窗口时间（秒，默认600秒/10分钟）: " FIND_TIME
    FIND_TIME=${FIND_TIME:-600}

    read -p "请输入最大失败尝试次数（默认5次）: " MAX_RETRY
    MAX_RETRY=${MAX_RETRY:-5}
    
    read -p "请输入白名单IP（使用逗号分隔多个IP，默认无白名单）: " IGNORE_IPS

    sudo sed -i '/^\[DEFAULT\]/,/^\[.*\]/ s/^bantime = .*/bantime = '"$BAN_TIME"'/' /etc/fail2ban/jail.local
    sudo sed -i '/^\[DEFAULT\]/,/^\[.*\]/ s/^findtime = .*/findtime = '"$FIND_TIME"'/' /etc/fail2ban/jail.local
    sudo sed -i '/^\[DEFAULT\]/,/^\[.*\]/ s/^maxretry = .*/maxretry = '"$MAX_RETRY"'/' /etc/fail2ban/jail.local
    if [ -n "$IGNORE_IPS" ]; then
        if grep -q "^ignoreip = " /etc/fail2ban/jail.local; then
            sudo sed -i '/^\[DEFAULT\]/,/^\[.*\]/ s/^ignoreip = .*/ignoreip = '"$IGNORE_IPS"'/' /etc/fail2ban/jail.local
        else
            sudo sed -i '/^\[DEFAULT\]/ a\ignoreip = '"$IGNORE_IPS" /etc/fail2ban/jail.local
        fi
    fi

    echo "请选择要保护的服务（使用空格分隔多个选择）："
    echo "1) sshd"
    echo "2) nginx"
    echo "3) apache"
    echo "4) vsftpd"
    echo "5) postfix"
    echo "6) dovecot"
    echo "7) 自定义"
    read -p "请输入选项 (例如: 1 3 5): " SERVICES
    
    for SERVICE in $SERVICES; do
        case $SERVICE in
            1) configure_service "sshd" "ssh" "/var/log/auth.log" ;;
            2) configure_service "nginx-http-auth" "http,https" "/var/log/nginx/error.log" ;;
            3) configure_service "apache-auth" "http,https" "/var/log/apache2/error.log" ;;
            4) configure_service "vsftpd" "ftp,ftp-data" "/var/log/vsftpd.log" ;;
            5) configure_service "postfix" "smtp,ssmtp" "/var/log/mail.log" ;;
            6) configure_service "dovecot" "pop3,pop3s,imap,imaps" "/var/log/mail.log" ;;
            7)
                read -p "请输入要保护的自定义服务名称: " CUSTOM_SERVICE
                read -p "请输入服务监听的端口: " CUSTOM_PORT
                read -p "请输入服务的日志文件路径: " CUSTOM_LOG
                configure_service "$CUSTOM_SERVICE" "$CUSTOM_PORT" "$CUSTOM_LOG"
                ;;
            *)
                echo "无效选项：$SERVICE"
                ;;
        esac
    done

    echo "服务配置完成，重新启动 fail2ban..."
    sudo systemctl restart fail2ban
}

setup_email_notification() {
    echo "设置邮件通知功能..."
    
    EMAIL="admin@example.com"
    read -p "请输入管理员邮箱以便接收通知（默认admin@example.com）： " EMAIL_INPUT
    EMAIL=${EMAIL_INPUT:-$EMAIL}

    case $OS in
        ubuntu|debian)
            sudo apt-get install -y mailutils
            ;;
        centos|rhel|fedora)
            sudo yum install -y mailx
            ;;
    esac

    if grep -q "^destemail = " /etc/fail2ban/jail.local; then
        sudo sed -i 's/^destemail = .*/destemail = '"$EMAIL"'/' /etc/fail2ban/jail.local
    else
        sudo bash -c "echo 'destemail = $EMAIL' >> /etc/fail2ban/jail.local"
    fi

    sudo bash -c "cat >> /etc/fail2ban/jail.local <<EOL

# 邮件通知相关配置
[DEFAULT]
sendername = Fail2Ban
mta = sendmail
action = %(action_mw)s
EOL"
}

add_custom_firewall_rule() {
    echo "添加自定义防火墙规则..."

    read -p "请输入要封禁的协议（如：tcp/udp，默认tcp）： " PROTOCOL
    PROTOCOL=${PROTOCOL:-tcp}

    read -p "请输入要封禁的端口（默认空，不封禁）： " PORT

    if [ -n "$PORT" ]; then
        if grep -q "\[custom-rule\]" /etc/fail2ban/jail.local; then
            sudo sed -i "/\[custom-rule\]/,+4s/^port = .*/port = $PORT/" /etc/fail2ban/jail.local
            sudo sed -i "/\[custom-rule\]/,+4s/^protocol = .*/protocol = $PROTOCOL/" /etc/fail2ban/jail.local
        else
            sudo bash -c "cat >> /etc/fail2ban/jail.local <<EOL

[custom-rule]
enabled = true
port = $PORT
protocol = $PROTOCOL
logpath = /var/log/custom.log
EOL"
        fi
    fi
}

unban_ip() {
    echo "解封指定的IP..."
    read -p "请输入要解封的IP地址：" UNBAN_IP
    sudo fail2ban-client unban $UNBAN_IP
}

start_fail2ban() {
    echo "启动 fail2ban..."
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
    sudo fail2ban-client status
}

restart_fail2ban() {
    echo "重启 fail2ban..."
    sudo systemctl restart fail2ban
}

stop_fail2ban() {
    echo "停止 fail2ban..."
    sudo systemctl stop fail2ban
}

uninstall_fail2ban() {
    echo "卸载 fail2ban..."
    
    case $OS in
        ubuntu|debian)
            sudo apt-get remove --purge -y fail2ban
            ;;
        centos|rhel|fedora)
            sudo yum remove -y fail2ban
            ;;
        *)
            echo "不支持的操作系统：$OS"
            exit 1
            ;;
    esac
}

integrate_cloudflare() {
    echo "配置 Cloudflare 集成..."
    
    read -p "请输入 Cloudflare API 密钥： " CLOUDFLARE_API_KEY
    read -p "请输入 Cloudflare 帐户邮箱： " CLOUDFLARE_EMAIL

    if grep -q "\[Definition\]" /etc/fail2ban/action.d/cloudflare.conf; then
        echo "Cloudflare 已经配置，跳过。"
    else
        sudo bash -c "cat > /etc/fail2ban/action.d/cloudflare.conf <<EOL
[Definition]
actionban = curl -s -X POST \"https://api.cloudflare.com/client/v4/user/firewall/access_rules/rules\" \
    -H \"X-Auth-Email: $CLOUDFLARE_EMAIL\" \
    -H \"X-Auth-Key: $CLOUDFLARE_API_KEY\" \
    --data '{\"mode\":\"block\",\"configuration\":{\"target\":\"ip\",\"value\":\"<ip>\"}}'
EOL"
    fi
}

view_logs() {
    sudo tail -f /var/log/fail2ban.log
}

while true; do
    echo "请选择一个操作："
    echo "1) 安装 fail2ban"
    echo "2) 配置服务保护"
    echo "3) 设置邮件通知"
    echo "4) 添加自定义防火墙规则"
    echo "5) 解封 IP 地址"
    echo "6) 启动 fail2ban"
    echo "7) 重启 fail2ban"
    echo "8) 停止 fail2ban"
    echo "9) 卸载 fail2ban"
    echo "10) 集成 Cloudflare"
    echo "11) 查看日志"
    echo "12) 退出"
    
    read -p "请输入选项 (1-12): " OPTION

    case $OPTION in
        1) install_fail2ban ;;
        2) configure_service_protection ;;
        3) setup_email_notification ;;
        4) add_custom_firewall_rule ;;
        5) unban_ip ;;
        6) start_fail2ban ;;
        7) restart_fail2ban ;;
        8) stop_fail2ban ;;
        9) uninstall_fail2ban ;;
        10) integrate_cloudflare ;;
        11) view_logs ;;
        12) exit 0 ;;
        *) echo "无效的选项，请重新选择。" ;;
    esac
done
