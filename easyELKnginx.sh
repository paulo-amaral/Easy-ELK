#!/bin/bash
#This script is used to install ELK STACK and map database GeoLite2
#Elasticsearch requires Java 8 or later. Use the official Oracle distribution or an open-source distribution such as OpenJDK.
#Author : Paulo Amaral 
#Email :  paulo.security@gmail.com
## Changelog ##
# 1- ALERT OF GEOMAP DOWNLOAD - url which no longer works and needs a license key obviously now! 
#    the databse is archived >> check https://forum.matomo.org/t/maxmind-is-changing-access-to-free-geolite2-databases/35439/2


#Get hostname and domain name
HOSTNAME=$(uname -n)

#Get Debian version
VERSION=$(lsb_release --codename --short)

#Verify running as root:
check_user() {
    USER_ID=$(/usr/bin/id -u)
    return $USER_ID
}

if [ "$USER_ID" > 0 ]; then
    echo "You must be a root user" 2>&1
    exit 1
fi

#Update system packages
update_system_packages() {
    printf "\033[32m Updating packages and install dependencies\033[0m\n"
    echo "-----------------------------------------------------"
    apt -y update
    apt install -y  software-properties-common wget curl software-properties-common apt-transport-https
}

#Be sure you have GNUPG installed.
check_gnupg(){
  printf "\033[32m Checking if GNUPG is installed\033[0m\n"
    echo "-----------------------------------------"
    GNUPG=$(which gpg)
    if [ $GNUPG >/dev/null ]; then
        echo -n "GNUPG already Installed\n"
        else
        echo -e " Error: GNUPG is not installed. Installing\n"
        apt -y install gnupg2
    fi
}


#Check NGINX Packages
check_nginx() {
    printf "\033[32m Checking if NGINX is installed \033[0m\n"
    echo    "--------------------------------"
    NGINX=$(dpkg-query -W -f='${Status}' nginx 2>/dev/null | grep -c "ok installed")
    if [ $NGINX -eq 0 ] ; then
        echo "NGINX is not installed - Installing NGINX now - Please wait \n"
        apt install -y nginx
    else
        echo "NGINX is already installed\n"
    fi
}

#check if java installed
#ELK deployment requires that Java 8 or 11 is installed. Run the below commands to install OpenJDK 11
check_java() {
    printf "\033[32m Checking if java is installed \033[0m\n"
    echo    "--------------------------------"
    JAVA=$(which java | wc -l)
    if [ $JAVA -eq 1 ];  then
        printf "\033[34m Java Installed :)\n \034[0m "
        java -version 2>&1 | awk -F '"' '/version/ {print $2}'
        else
        #install java
        echo "Installing Java - Please wait "
        echo "--------------------------------"
        echo deb http://http.debian.net/debian $VERSION-backports main >> /etc/apt/sources.list
        apt update && apt install -t $VERSION-backports openjdk-11-jdk
        fi
}

#Install and Configure Elasticsearch
install_elasticsearch() {
    printf "\033[32m Install Elasticsearch \033[0m\n"
    echo    "-----------------------------"
    #import PGP key
    printf "\033[32m---- Setting up public signing key ---- \033[0m\n"
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
    #update apt sources list
    printf "\033[32m ---- Saving Repository Definition to /etc/apt/sources/list.d/elastic-7.x.list ---- \033[0m\n"
    echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-7.x.list
    printf "\033[32m---- Installing the Elasticsearch Debian Package ----\033[0m\n"
    apt-get update && apt-get install -y elasticsearch
}

configure_elasticsearch() {
    printf "\033[32m Configuring elasticsearch \033[0m\n"
    echo    "---------------------------"
    cd /etc/elasticsearch/ || exit
    #bootstrap.memory_lock: true
    sed -i '/bootstrap.memory_lock:/s/^#//g' elasticsearch.yml
    #network.host: localhost
    sed -i '/network.host/anetwork.host: localhost'  elasticsearch.yml
    #http.port: 9200
    sed -i '/http.port:/s/^#//g' elasticsearch.yml
    #LimitMEMLOCK=infinity
    sed -i '/LimitMEMLOCK=/s/^#//g' /usr/lib/systemd/system/elasticsearch.service
    #MAX_LOCKED_MEMORY=unlimited
    sed -i '/MAX_LOCKED_MEMORY=/s/^#//g' /etc/default/elasticsearch
    printf "\033[0m\n---- starting elasticsearch ----\033[0m\n"
    #start service
    CMD=$(command -v systemctl)
    if [ $CMD > /dev/null ] ; then
        systemctl daemon-reload
        systemctl enable --now elasticsearch
    else
        update-rc.d elasticsearch defaults 95 10
        service elasticsearch start
    fi
    sleep 60
    #check if service is running
    printf " ---- check if elasticsearch is running ----"
    SVC='elasticsearch'
    if ps ax | grep -v grep | grep $SVC > /dev/null ; then
        echo "\033[32m-----Elasticsearch service is running----\033[0m\n"
    else
        echo "\033[31m----Elasticsearch Server is stopped - please check your installation----\033[0m\n"
        exit 1
    fi
}

#Install and Configure Kibana with NGINX
install_kibana() {
    clear
    printf "\033[32m ---- Installing kibana ---- \033[0m\n"
    #get eth IP
    IP=$(ip addr show |grep "inet " |grep -v 127.0.0. |head -1|cut -d" " -f6|cut -d/ -f1)
    #install package
    apt-get install -y kibana
    printf "\033[32m  ---- Setting up public signing key ----\033[0m\n"
    cd /etc/kibana || exit
    #server.port: 5601
    sed -i "/server.port:/s/^#//g" /etc/kibana/kibana.yml
    #The default is 'localhost', which usually means remote machines will not be able to connect.
    #server.host: "localhost"
    sed -i "/server.host/aserver.host: ${IP}"  /etc/kibana/kibana.yml
    #Elastic url
    sed -i '/elasticsearch.url:/s/^#//g' /etc/kibana/kibana.yml
    #locale
    sed -i "i18n.locale:/s/^#//g" /etc/kibana/kibana.yml
    #start kibana
    printf "\033[32m ---- Updating start daemon Kibana ---- \033[0m\n"
    CMD=$(command -v systemctl)
    if [ $CMD > /dev/null ] ; then
        systemctl daemon-reload
        systemctl enable --now kibana.service
    else
        update-rc.d kibana defaults 95 10
        service kibana start
    fi
}

configure_kibana_auth() {
    printf "\033[32m ---- Configuring Kibana ---- \033[0m\n"
    admpwd="password"
    #touch /etc/nginx/htpasswd.users
    echo "---- configuring password for kibana nginx  for basic security ----\n"
    echo "admin:$(openssl passwd -apr1 $admpwd)" | tee -a /etc/nginx/.htpasswd.users
touch /etc/nginx/sites-available/kibana
cat > /etc/nginx/sites-available/kibana <<\EOF
server {
     listen 80;
     server_name $HOSTNAME;
     auth_basic "Kibana";
     auth_basic_user_file /etc/nginx/.htpasswd.users;
     error_log   /var/log/nginx/kibana.error.log;
     access_log  /var/log/nginx/kibana.access.log;
     location / {
        proxy_pass http://$IP:5601;
        rewrite ^/(.*) /$1 break;
        proxy_ignore_client_abort on;
        proxy_set_header  X-Real-IP  $remote_addr;
        proxy_set_header  X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header  Host $http_host;
               }
 }
EOF
        ln -s /etc/nginx/sites-available/kibana /etc/nginx/sites-enabled/
        mv /etc/nginx/sites-avaliable/default /tmp
        #check if KIBANA port is active
        KBSVC='kibana'
        if ps ax | grep -v grep | grep $KBSVC > /dev/null ; then
            printf "\033[0m\n ---- Kibana service is running --- \033[0m\n"
        else
            printf "\033[31m ---- Kibana Server is stopped - please check your installation \033[0m\n ---- "
            exit 1
        fi
        service nginx reload
}



install_logstash() {
    #install pacjage
    apt-get install -y logstash
    #create config file
    touch /etc/logstash/conf.d/logstash.conf
    cd /etc/logstash/conf.d/ || exit
    #start logstash
    systemctl daemon-reload
    systemctl start logstash.service
    systemctl enable logstash.service
    #install geolocation data for maps
    cd /etc/logstash || exit
    curl -O "https://web.archive.org/web/20191227182209/https://geolite.maxmind.com/download/geoip/database/GeoLite2-City.tar.gz"
    gunzip GeoLite2-City.mmdb.gz
}

test_elasticsearch_port(){
clear
    echo -n "Testing if Elasticsearch is Ruuning on port 9200 \n"
    echo    "---------------------------------------------------"   
PORT=9200
URL="http://localhost:$PORT"
# Check that Elasticsearch is running
curl -s $URL 2>&1 > /dev/null
if [ $? != 0 ]; then
    echo "Unable to contact Elasticsearch on port $PORT."
    echo "Please ensure Elasticsearch is running and can be reached at $URL"
    exit -1
    else
    echo -n "Service is Running \n"
    
fi
}

check_user
update_system_packages
check_nginx
check_java
install_elasticsearch
configure_elasticsearch 
install_kibana
configure_kibana_auth
install_logstash
test_elasticsearch_port
