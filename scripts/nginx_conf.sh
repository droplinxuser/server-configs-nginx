#!/bin/bash

cd ~
/usr/bin/rm -rf server-configs-nginx-main main.zip*
/usr/bin/wget -q https://github.com/droplinxuser/server-configs-nginx/archive/refs/heads/main.zip
/usr/bin/unzip -q main.zip
/usr/bin/rm -rf server-configs-nginx-main/{*.md,*.txt,.git*}
/usr/bin/rsync -a server-configs-nginx-main/ /etc/nginx/
service nginx restart; nginx -t
