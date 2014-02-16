#!/usr/bin/env bash

SCRIPT_DIR_NAME="$( cd "$( dirname "$0" )" && pwd )"

get_container_ip() {
    sudo docker inspect -format '{{ .NetworkSettings.IPAddress }}' ${1:-}
}

create_key_store() {
    KEY_STORE=$(sudo docker run -d key_store_img)
    KEY_STORE_IP=$(get_container_ip $KEY_STORE)
    for i in {1..10}
    do
		sleep 5
	    if [ $i == 3 ]; then
		    break
	    fi
	    echo $i
    done

    sudo docker run -i -t yar_img key_store_installer --log=info --create=true --host=$KEY_STORE_IP:5984
}

create_key_server() {
    echo "dave"
}

create_app_server() {
    PORT=8080
    APP_SERVER=$(sudo docker run -d -p $PORT:$PORT yar_img app_server --log=info --lon=$PORT)
    APP_SERVER_IP=$(get_container_ip $APP_SERVER)
    echo $APP_SERVER
#   curl http://$APPS_SERVER_IP:8080/dave.html
}

APP_SERVER=$(create_app_server)
echo $APP_SERVER
# APP_SERVER_IP=$(get_container_ip $APP_SERVER)
# echo $APP_SERVER_ID

# KEY_SERVER_ID=$(create_key_server) 