#!/bin/bash

set -e # Exit on any error

# Check if running as root
if [[ $(id -u) -ne 0 ]]; then
  echo "This script must be run as root."
  exit 1
fi

# Check if it's a dedicated server
is_dedicated_server=false
if grep -qi 'physical' /sys/class/dmi/id/chassis_type; then
  is_dedicated_server=true
fi

# Function to install and configure cpufrequtils if it's a dedicated server
install_cpufrequtils() {
  if $is_dedicated_server; then
    apt update -y
    apt install cpufrequtils -y --no-install-recommends
    cpufreq-info
    cpufreq-set -g performance
    echo 'GOVERNOR="performance"' | tee /etc/default/cpufrequtils
  fi
}

# Function to create swap memory
create_swap_memory() {
  if [[ ! -f /swapfile ]]; then
    ram_size=$(free -b | awk '/^Mem:/ {print $2}')
    swap_size=$((ram_size < 32*1024**3 ? 2*ram_size : ram_size))

    fallocate -l $swap_size /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    cp /etc/fstab /etc/fstab.bak
    echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
  fi
}

# Parse command line options
while getopts ":h:s:t:" opt; do
  case $opt in
    h)  # Set hostname
      hostnamectl set-hostname "$OPTARG"
      hostnamectl status
      ;;
    s)  # Create swap memory
      create_swap_memory
      ;;
    t)  # Set time zone
      timedatectl set-timezone "$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

# Disable ufw
ufw disable

# Update and upgrade system
apt update -y
apt upgrade -y
apt autoremove --purge -y
apt autoclean -y
apt clean -y

# Remove tuned and install required packages
apt remove tuned -y
apt install wget unzip nano zip software-properties-common rsync --no-install-recommends -y

# Set DNS servers
mkdir -p /etc/systemd/resolved.conf.d/
rm -f /etc/systemd/resolved.conf.d/*
wget -O /etc/systemd/resolved.conf.d/dns_servers.conf https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/dns_servers.conf
systemctl restart systemd-resolved
resolvectl status

# Set sysctl parameters and limits
modprobe tcp_bbr
modprobe tls
wget -O /etc/sysctl.conf https://raw.githubusercontent.com/droplinxuser/server-configs-nginx/main/scripts/sysctl.conf
sysctl -e -p /etc/sysctl.conf

wget -O /etc/security/limits.conf https://github.com/droplinxuser/server-configs-nginx/raw/main/scripts/limits.conf
cat /etc/security/limits.conf

# Install and configure cpufrequtils
install_cpufrequtils

# Exit successfully
exit 0
