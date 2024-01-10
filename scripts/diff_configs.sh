#!/bin/bash

# Function to compare remote and local configurations
compare_configs() {
    remote_url="$1"
    local_file="$2"

    # Download the remote file to a temporary location
    temp_file=$(mktemp)
    curl -sS "$remote_url" -o "$temp_file"

    # Compare the files and display the difference if any
    if ! diff -q "$local_file" "$temp_file" > /dev/null; then
        echo "Difference found in $local_file:"
        diff -u "$local_file" "$temp_file"
        echo
    fi

    # Clean up the temporary file
    rm "$temp_file"
}


# Compare configurations
compare_configs "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/dns_servers.conf"        "/etc/systemd/resolved.conf.d/dns_servers.conf"
compare_configs "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/cpufrequtils"            "/etc/default/cpufrequtils"
compare_configs "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/sysctl.conf"             "/etc/sysctl.conf"
compare_configs "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limits.conf"             "/etc/security/limits.conf"
compare_configs "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/nginx_conf.sh"           "/root/nginx_conf.sh"
compare_configs "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limit_nofile.conf"       "/etc/systemd/system/nginx.service.d/limits.conf"
compare_configs "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/etc_default_nginx"       "/etc/default/nginx"
compare_configs "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/http.d/ppa_eilander_conf"        "/etc/nginx/http.d/ppa_eilander.conf"
compare_configs "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limit_nofile.conf"       "/etc/systemd/system/mariadb.service.d/limits.conf"
compare_configs "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/mariadb_server.cnf"      "/etc/mysql/mariadb.conf.d/50-server.cnf"
compare_configs "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/www_82.conf"             "/etc/php/8.2/fpm/pool.d/www.conf"
compare_configs "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/custom_dan.ini"          "/etc/php/8.2/fpm/conf.d/custom_dan.ini"


# Print message if no differences found
if [ -z "$(find /tmp -name 'diff*' -print -quit)" ]; then
    echo "No differences found in configurations."
fi
