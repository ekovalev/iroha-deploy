#!/bin/sh

SCRIPT_DIR=$(pwd)
MAIN_YML="$SCRIPT_DIR/ansible/roles/iroha-docker/tasks/main.yml"
EXPAND_1="$SCRIPT_DIR/ansible/playbooks/iroha-expand/host_vars/tag_name_iroha_expand1.yml"
EXPAND_2="$SCRIPT_DIR/ansible/playbooks/iroha-expand/host_vars/tag_name_iroha_expand2.yml"
USER=eugene # ekovalev
SSH_HOST=localhost # iroha-expand1.dev.iroha.tech
LOCALHOST_1=iroha-expand1.dev.internal
LOCALHOST_2=iroha-expand2.dev.internal
CONTAINER_PFX_1="iroha-" # "c_iroha_expand1_dev_internal_1000"
CONTAINER_PFX_2="iroha-" # "c_iroha_expand2_dev_internal_1000"
ON_TWO_HOSTS=false
DOCKER=/usr/local/bin/docker

uncomment()
{
    gsed -i '1,13 s/# //g' $MAIN_YML
}

comment()
{
    gsed -i '1,13 s/# //g' $MAIN_YML
    gsed -i '1,7 s/^/# /' $MAIN_YML
    gsed -i '9,13 s/^/# /' $MAIN_YML
}

run_playbook()
{
    docker-compose up ansible
}

create_config()
{
    let x=$1
    echo "#IROHA" > $EXPAND_1
    echo "iroha_replicas: $x" >> $EXPAND_1
    echo "iroha_custom_hostnames: false" >> $EXPAND_1
    echo "iroha_hostnames:" >> $EXPAND_1
    for (( i=1; i<=$x; i++ ))
    do
        echo "  - \"$LOCALHOST_1\"" >> $EXPAND_1
    done
    cat >> $EXPAND_1 <<- EOM


iroha_service_host: True
iroha_service_account: 'admin@nbc'
iroha_service_account_keys: ['72a9eb49c0cd469ed64f653e33ffc6dde475a6b9fd8be615086bce7c44b5a8f8']
EOM
}

fetch_logs()
{
    x=$1
    y=$2

    if [[ -z $y ]] || [ $y -eq 0 ]
    then
        for (( i=0; i<=$x-1; i++ ))
        do
            screen -S "fetch_log_extend1_1000${i}" -dm 
            screen -S "fetch_log_extend1_1000${i}" -X stuff "ssh -i ~/.ssh/id_rsa $USER@$SSH_HOST $DOCKER logs ${CONTAINER_PFX_1}${i} -f | tee logs/extend1_1000${i}.log\r"
            if $ON_TWO_HOSTS
            then
                screen -S "fetch_log_extend2_1000${i}" -dm 
                screen -S "fetch_log_extend2_1000${i}" -X stuff "ssh -i ~/.ssh/id_rsa $USER@$SSH_HOST $DOCKER logs ${CONTAINER_PFX_1}${i} -f | tee logs/extend2_1000${i}.log\r"
            fi
        done
    fi

    for (( i=$x; i<=$x+$y-1; i++ ))
    do
        screen -S "fetch_log_extend1_1000${i}" -dm 
        screen -S "fetch_log_extend1_1000${i}" -X stuff "ssh -i ~/.ssh/id_rsa $USER@$SSH_HOST $DOCKER logs ${CONTAINER_PFX_1}${i} -f | tee logs/extend1_1000${i}.log\r"
    done
}

close_screens()
{
    x=$1
    for (( i=0; i<=$x-1; i++ ))
    do
        screen -S "fetch_log_extend1_1000${i}" -X stuff ^C
        screen -S "fetch_log_extend1_1000${i}" -X quit
    done
}

N=$1
if [[ -z $N ]]; then
    N=4
fi

echo "N nodes = $N"

# Re-create logs folder
rm -rf logs
mkdir logs

# Stop Iroha running containers running locally, if any
echo 'Stop running containers, if any'
docker-compose -f /opt/iroha-deploy/docker-compose.yml down
docker stop $(docker ps | grep 'iroha' | cut -d' ' -f1)

echo 'Removing stale docker volumes'
docker volume rm $(docker volume ls -q | grep 'iroha_block_store')

# # Delete local Iroha networks in docker, if any
# echo 'Deleting Iroha networks in docker, if any'
# docker network rm $(docker network ls | grep iroha-net | cut -d' ' -f1)
# docker network rm $(docker network ls | grep iroha-db-net | cut -d' ' -f1)

# [1] Deploy Iroha from scratch
uncomment
create_config $N
echo 'Deploying Iroha anew'
run_playbook

echo 'Fetching logs for deployed peers'
sleep 10
fetch_logs $N 0
