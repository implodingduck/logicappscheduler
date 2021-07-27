#! /bin/bash
sudo apt update
sudo apt install -y nginx 
sudo systemctl status nginx
sudo ufw allow 'Nginx Full'
sudo systemctl enable nginx

#Change sshd port to 2266 and restart it
sudo systemctl stop sshd.service
sudo cat <<EOF >> /etc/ssh/sshd_config 

# WTH: Change to run on a custom port for security reasons
Port 2266
EOF
sudo systemctl start sshd.service

COMPUTERNAME=$(hostname)
echo "Hello from $COMPUTERNAME" > /var/www/html/index.html