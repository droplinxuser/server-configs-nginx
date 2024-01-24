#!/bin/bash

# Function to compare two files and output only added (+) and removed (-) lines
compare_files() {
    local remote_url=$1
    local local_path=$2

    # Download remote file to temporary location
    tmp_remote_file=$(mktemp)
    if ! curl -sSL "$remote_url" -o "$tmp_remote_file"; then
        echo "Error: Failed to download remote file from $remote_url."
        exit 1
    fi

    # Compare files and display only added (+) and removed (-) lines
    if ! command -v diff &> /dev/null; then
        echo "Error: diff command not found."
        exit 1
    fi

    diff_result=$(diff -u "$local_path" "$tmp_remote_file" | grep -E '^[+-]')

    if [ -n "$diff_result" ]; then
        printf "\n"
        printf "Differences in %s:\n%s\n" "$local_path" "$diff_result"
    fi

    # Clean up temporary files
    rm -f "$tmp_remote_file"
}

# Compare configurations for Ubuntu Server 22.04

# Define remote URLs and local paths
declare -A config_files=(
    ["dns_servers"]="https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/dns_servers.conf /etc/systemd/resolved.conf.d/dns_servers.conf"
    ["cpufrequtils"]="https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/cpufrequtils /etc/default/cpufrequtils"
    ["sysctl"]="https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/sysctl.conf /etc/sysctl.conf"
    ["limits"]="https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limits.conf /etc/security/limits.conf"
    ["nginx_conf.sh"]="https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/nginx_conf.sh /root/nginx_conf.sh"
    ["nginx_service_limits"]="https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limit_nofile.conf /etc/systemd/system/nginx.service.d/limits.conf"
    ["nginx_default"]="https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/etc_default_nginx /etc/default/nginx"
    ["nginx_additional"]="https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/http.d/ppa_eilander_conf /etc/nginx/http.d/ppa_eilander.conf"
    ["mariadb_service_limits"]="https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limit_nofile.conf /etc/systemd/system/mariadb.service.d/limits.conf"
    ["mariadb_server"]="https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/mariadb_server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf"
    ["php74ini"]="https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/custom_dan.ini /etc/php/7.4/fpm/conf.d/custom_dan.ini"
    ["php74fpm"]="https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/www_80.conf /etc/php/7.4/fpm/pool.d/www.conf"
)

# PHP Versions
php_versions=(0 1 2 3)

# Compare configurations
for file_name in "${!config_files[@]}"; do
    urls_and_paths=(${config_files[$file_name]})
    remote_url="${urls_and_paths[0]}"
    local_path="${urls_and_paths[1]}"
    compare_files "$remote_url" "$local_path"
done

# Compare PHP configurations for different versions
for version in "${php_versions[@]}"; do
    compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/www_8${version}.conf" "/etc/php/8.${version}/fpm/pool.d/www.conf"
    compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/custom_dan.ini" "/etc/php/8.${version}/fpm/conf.d/custom_dan.ini"
done
