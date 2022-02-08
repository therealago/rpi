#!/bin/bash

echo .... RaspAP Install
echo .. Enable wireless operation
sudo rfkill unblock wlan
echo .. Install packages
sudo apt-get install lighttpd git hostapd dnsmasq iptables-persistent vnstat qrencode php7.3-cgi
echo .. Enable PHP
sudo lighttpd-enable-mod fastcgi-php    
sudo service lighttpd force-reload
sudo systemctl restart lighttpd.service
echo .. Create the web application
sudo rm -rf /var/www/html
sudo git clone https://github.com/RaspAP/raspap-webgui /var/www/html
echo . Copy an extra lighttpd config file
WEBROOT="/var/www/html"
CONFSRC="$WEBROOT/config/50-raspap-router.conf"
LTROOT=$(grep "server.document-root" /etc/lighttpd/lighttpd.conf | awk -F '=' '{print $2}' | tr -d " \"")
HTROOT=${WEBROOT/$LTROOT}
HTROOT=$(echo "$HTROOT" | sed -e 's/\/$//')
awk "{gsub(\"/REPLACE_ME\",\"$HTROOT\")}1" $CONFSRC > /tmp/50-raspap-router.conf
sudo cp /tmp/50-raspap-router.conf /etc/lighttpd/conf-available/
echo . Link it into conf-enabled and restart the web service
sudo ln -s /etc/lighttpd/conf-available/50-raspap-router.conf /etc/lighttpd/conf-enabled/50-raspap-router.conf
sudo systemctl restart lighttpd.service
echo . Add the www-data user to sudoers
cd /var/www/html
sudo cp installers/raspap.sudoers /etc/sudoers.d/090_raspap

echo .... Configuration directories
sudo mkdir /etc/raspap/
sudo mkdir /etc/raspap/backups
sudo mkdir /etc/raspap/networking
sudo mkdir /etc/raspap/hostapd
sudo mkdir /etc/raspap/lighttpd
sudo cp raspap.php /etc/raspap 

echo .... Set permissions
sudo chown -R www-data:www-data /var/www/html
sudo chown -R www-data:www-data /etc/raspap

echo .... Control scripts
sudo mv installers/*log.sh /etc/raspap/hostapd 
sudo mv installers/service*.sh /etc/raspap/hostapd
sudo chown -c root:www-data /etc/raspap/hostapd/*.sh 
sudo chmod 750 /etc/raspap/hostapd/*.sh 
sudo cp installers/configport.sh /etc/raspap/lighttpd
sudo chown -c root:www-data /etc/raspap/lighttpd/*.sh
sudo mv installers/raspapd.service /lib/systemd/system
sudo systemctl daemon-reload
sudo systemctl enable raspapd.service

echo .... Default configuration
sudo mv /etc/default/hostapd ~/default_hostapd.old
sudo cp /etc/hostapd/hostapd.conf ~/hostapd.conf.old
sudo cp config/default_hostapd /etc/default/hostapd
sudo cp config/hostapd.conf /etc/hostapd/hostapd.conf
sudo cp config/090_raspap.conf /etc/dnsmasq.d/090_raspap.conf
sudo cp config/090_wlan0.conf /etc/dnsmasq.d/090_wlan0.conf
sudo cp config/dhcpcd.conf /etc/dhcpcd.conf
sudo cp config/config.php /var/www/html/includes/
sudo cp config/defaults.json /etc/raspap/networking/
sudo systemctl stop systemd-networkd
sudo systemctl disable systemd-networkd
sudo cp config/raspap-bridge-br0.netdev /etc/systemd/network/raspap-bridge-br0.netdev
sudo cp config/raspap-br0-member-eth0.network /etc/systemd/network/raspap-br0-member-eth0.network 

echo .... Optimize PHP
sudo sed -i -E 's/^session\.cookie_httponly\s*=\s*(0|([O|o]ff)|([F|f]alse)|([N|n]o))\s*$/session.cookie_httponly = 1/' /etc/php/7.3/cgi/php.ini
sudo sed -i -E 's/^;?opcache\.enable\s*=\s*(0|([O|o]ff)|([F|f]alse)|([N|n]o))\s*$/opcache.enable = 1/' /etc/php/7.3/cgi/php.ini
sudo phpenmod opcache

echo .... Routing and IP masquerading - Deactivated
# echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/90_raspap.conf > /dev/null
# sudo sysctl -p /etc/sysctl.d/90_raspap.conf
# sudo /etc/init.d/procps restart
# echo .. To enable traffic between clients on the WLAN and the internet
# sudo iptables -t nat -A POSTROUTING -j MASQUERADE
# sudo iptables -t nat -A POSTROUTING -s 192.168.50.0/24 ! -d 192.168.50.0/24 -j MASQUERADE
# sudo iptables-save | sudo tee /etc/iptables/rules.v4

echo .... Enable hostapd
sudo systemctl unmask hostapd.service
sudo systemctl enable hostapd.service

echo .... Reboot - default SSID is raspi-webgui
sudo systemctl reboot
