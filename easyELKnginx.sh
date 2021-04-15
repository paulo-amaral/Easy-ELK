#!/bin/bash
#This script is used to install ELK STACK and map database GeoLite2
#Elasticsearch requires Java 8 or later. Use the official Oracle distribution or an open-source distribution such as OpenJDK.
#Author : Paulo Amaral 
#Email :  paulo.security@gmail.com

#Get domain name
MYDOMAIN=$(hostname -d)


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
    echo -n "Updating Packages \n"
    echo "-----------------------------------------"
    apt-get -y update
}

#Check NGINX Packages
check_nginx() {
    echo -n "Checking if NGINX is installed \n"
    echo    "--------------------------------"
    NGINX=$(dpkg-query -W -f='${Status}' nginx 2>/dev/null | grep -c "ok installed")
    if [ $NGINX -eq 0 ] ; then
        echo "NGINX is not installed - Installing NGINX now - Please wait \n"
        apt install -y nginx
    else
        echo "NGINX is installed "
    fi
}

#check if java installed
#ELK deployment requires that Java 8 or 11 is installed. Run the below commands to install OpenJDK 11
check_java() {
    clear
    echo -n "checking if java is installed \n"
    echo    "--------------------------------"
    JAVA=$(which java | wc -l)
    JAVA_REQ=$(java -version 2> /tmp/version && awk '/version/ { gsub(/"/, "", $NF); print ( $NF < 1.8 ) ? "YES" : "NO" }' /tmp/version)
    if [ $JAVA -eq 0 ] ; then
        #install java
        echo "Installing Java 8 - Please wait "
        echo "--------------------------------"
        apt-get install -y python-software-properties wget curl software-properties-common apt-transport-https
        echo deb http://http.debian.net/debian jessie-backports main >> /etc/apt/sources.list
        apt-get update && apt-get install -t jessie-backports openjdk-8-jdk
        #update-alternatives --config java
        #Elasticsearch requires Java 8 or later
        elif [ "$JAVA_REQ" = 'YES' ]; then
        apt-get update && apt-get install -y openjdk-8-jdk
    fi
}

#Install and Configure Elasticsearch
install_elasticsearch() {
    clear
    echo -n "Installing elasticsearch \n"
    echo    "---------------------------"
    #import PGP key
    echo "$(tput setaf 1) ---- Setting up public signing key ----"
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
    #update apt sources list
    echo "$(tput setaf 1) ---- Saving Repository Definition to /etc/apt/sources/list.d/elastic-7.x.list ----"
    echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | tee -a /etc/apt/sources.list.d/elastic-7.x.list
    echo "$(tput setaf 1) ---- Installing the Elasticsearch Debian Package ----"
    apt-get update && apt-get install -y elasticsearch
    #Elasticsearch is not started automatically after installation
    echo -n "Updating start daemon \n"
    echo    "---------------------------"
    CMD=$(command -v systemctl)
    if [ $CMD > /dev/null ] ; then
        systemctl daemon-reload
        systemctl enable elasticsearch.service
    else
        update-rc.d elasticsearch defaults 95 10
    fi
}

configure_elasticsearch() {
    clear
    echo -n "Configuring elasticsearch \n"
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
    echo "$(tput setaf 1) ---- starting elasticsearch ----"
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
    echo "$(tput setaf 1) ---- check if elasticsearch is running ----"
    SVC='elasticsearch'
    if ps ax | grep -v grep | grep $SVC > /dev/null ; then
        echo "Elasticsearch service is running"
    else
        echo "Elasticsearch Server is stopped - please check your installation"
        exit 1
    fi
}

#Install and Configure Kibana with NGINX
install_kibana() {
    clear
    echo -n "Installing kibana \n"
    echo    "---------------------------"
    #get eth IP
    IP=$(ip addr show |grep "inet " |grep -v 127.0.0. |head -1|cut -d" " -f6|cut -d/ -f1)
    #install package
    apt-get install -y kibana
    echo "$(tput setaf 1) ---- Setting up public signing key ----"
    cd /etc/kibana || exit
    #server.port: 5601
    sed -i "/server.port:/s/^#//g" /etc/kibana/kibana.yml
    #The default is 'localhost', which usually means remote machines will not be able to connect.
    #server.host: "localhost"
    sed -i "/server.host/aserver.host: ${IP}"  /etc/kibana/kibana.yml
    #Elastic url
    sed -i '/elasticsearch.url:/s/^#//g' /etc/kibana/kibana.yml
    #start kibana
    echo -n "Updating start daemon Kibana \n"
    echo    "---------------------------"
    CMD=$(command -v systemctl)
    if [ $CMD > /dev/null ] ; then
        systemctl daemon-reload
        systemctl enable --now kibana.service
    else
        update-rc.d kibana defaults 95 10
        service kibana start
    fi
         
}


#Create nginx config file for kibana
#Please edit ServerName and ServerAdmin
configure_kibana() {
    clear
    echo -n "Configuring Kibana \n"
    echo    "---------------------------"
    echo "admin:$(openssl passwd -apr1)" | tee -a /etc/nginx/htpasswd.users
        # echo -e "You need to set a username and password to login."
        # read -p "Please enter a username : " user
        # htpasswd -c /etc/nginx/conf.d/kibana.htpasswd $user
touch /etc/nginx/sites-available/kibana
cat > /etc/nginx/sites-available/kibana <<\EOF
server {
     listen 80;
     server_name $HOSTNAME;
     auth_basic "Kibana";
     auth_basic_user_file /etc/nginx/htpasswd.users;
     error_log   /var/log/nginx/kibana.error.log;
     access_log  /var/log/nginx/kibana.access.log;
     location / {
        proxy_pass http://127.0.0.1:5601;
        rewrite ^/(.*) /$1 break;
        proxy_ignore_client_abort on;
        proxy_set_header  X-Real-IP  $remote_addr;
        proxy_set_header  X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header  Host $http_host;
     }
 }
EOF
ln -s /etc/nginx/sites-available/kibana /etc/nginx/sites-enabled/
        #check if KIBANA port is active
        KBSVC='kibana'
        if ps ax | grep -v grep | grep $KBSVC > /dev/null ; then
            echo "Kibana service is running \n"
        else
            echo "Kibana Server is stopped - please check your installation"
            exit 1  
        fi
        service nginx reload
}

#Install and Configure Logstash
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
    curl -O "http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.mmdb.gz"
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
configure_elasticsearch #parei aqui
install_kibana
configure_kibana
install_logstash
test_elasticsearch_port
