#!/bin/bash

# Function to compare two files
compare_files() {
    local remote_url=$1
    local local_path=$2

    # Check if local file exists
    if [ -e "$local_path" ]; then
        # Download remote file to temporary location
        tmp_remote_file=$(mktemp)
        curl -sSL "$remote_url" -o "$tmp_remote_file"

        # Compare files and display only the differing lines
        diff_result=$(diff --unchanged-line-format= --old-line-format= --new-line-format="%L" "$tmp_remote_file" "$local_path")

        if [ -z "$diff_result" ]; then
            echo "File $local_path is identical to the remote version."
        else
            echo -e "Differences in $local_path:\n$diff_result"
        fi

        # Clean up temporary files
        rm -f "$tmp_remote_file"
    else
        echo "Local file $local_path not found."
    fi

    # Download remote file to temporary location
    tmp_remote_file=$(mktemp)
    curl -sSL "$remote_url" -o "$tmp_remote_file"

    # Compare remote file with an empty local file
    diff_result=$(diff --unchanged-line-format= --old-line-format= --new-line-format="%L" "$tmp_remote_file" /dev/null)

    if [ -z "$diff_result" ]; then
        echo "Remote file $remote_url is identical to the local version."
    else
        echo -e "Differences in remote file $remote_url:\n$diff_result"
    fi

    # Clean up temporary files
    rm -f "$tmp_remote_file"
}

# Compare configurations for PHP 8.2, 8.1, 8.3
for version in 8.2 8.1 8.3; do
    path="/etc/php/$version/fpm/pool.d/www.conf"
    compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/www_82.conf" "$path"

    path="/etc/php/$version/fpm/conf.d/custom_dan.ini"
    compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/custom_dan.ini" "$path"
done

# Add more comparisons as needed for other files
# ...

# Additional comparisons
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/dns_servers.conf" "/etc/systemd/resolved.conf.d/dns_servers.conf"
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/cpufrequtils" "/etc/default/cpufrequtils"
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/sysctl.conf" "/etc/sysctl.conf"
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limits.conf" "/etc/security/limits.conf"
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/nginx_conf.sh" "/root/nginx_conf.sh"
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limit_nofile.conf" "/etc/systemd/system/nginx.service.d/limits.conf"
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/etc_default_nginx" "/etc/default/nginx"
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/http.d/ppa_eilander_conf" "/etc/nginx/http.d/ppa_eilander.conf"
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/limit_nofile.conf" "/etc/systemd/system/mariadb.service.d/limits.conf"
compare_files "https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/mariadb_server.cnf" "/etc/mysql/mariadb.conf.d/50-server.cnf"
