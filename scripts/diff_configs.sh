#!/bin/bash

# Function to compare two files
compare_files() {
    local remote_url=$1
    local local_path=$2

    # Download remote file to temporary location
    tmp_remote_file=$(mktemp)
    curl -sSL "$remote_url" -o "$tmp_remote_file"

    # Compare files and display both local and remote changes
    diff_result=$(diff -u "$local_path" "$tmp_remote_file")

    if [ -n "$diff_result" ]; then
        echo -e "Differences in $local_path:\n$diff_result"
    fi

    # Clean up temporary files
    rm -f "$tmp_remote_file"
}

# Compare configurations for Ubuntu Server 22.04

# DNS Servers Configuration
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/dns_servers.conf" "/etc/systemd/resolved.conf.d/dns_servers.conf"

# CPU Frequency Utilities Configuration
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/cpufrequtils" "/etc/default/cpufrequtils"

# Kernel System Configuration
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/sysctl.conf" "/etc/sysctl.conf"

# System Resource Limits Configuration
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limits.conf" "/etc/security/limits.conf"

# Nginx Configuration Script
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/nginx_conf.sh" "/root/nginx_conf.sh"

# Nginx Service Limits Configuration
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limit_nofile.conf" "/etc/systemd/system/nginx.service.d/limits.conf"

# Default Nginx Configuration
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/etc_default_nginx" "/etc/default/nginx"

# Nginx Additional Configuration
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/http.d/ppa_eilander_conf" "/etc/nginx/http.d/ppa_eilander.conf"

# MariaDB Service Limits Configuration
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limit_nofile.conf" "/etc/systemd/system/mariadb.service.d/limits.conf"

# MariaDB Server Configuration
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/mariadb_server.cnf" "/etc/mysql/mariadb.conf.d/50-server.cnf"

# PHP 8.2 FPM Pool Configuration
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/www_82.conf" "/etc/php/8.2/fpm/pool.d/www.conf"

# PHP 8.2 Additional Configuration
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/custom_dan.ini" "/etc/php/8.2/fpm/conf.d/custom_dan.ini"
