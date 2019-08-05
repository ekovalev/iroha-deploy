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

create_config_expand1()
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

create_config_expand2()
{
    let x=$1
    echo "#IROHA" > $EXPAND_2
    echo "iroha_replicas: $x" >> $EXPAND_2
    echo "iroha_custom_hostnames: false" >> $EXPAND_2
    echo "iroha_hostnames:" >> $EXPAND_2
    for (( i=1; i<=$x; i++ ))
    do
        echo "  - \"$LOCALHOST_2\"" >> $EXPAND_2
    done
    cat >> $EXPAND_2 <<- EOM


# kafka_host: 'iroha-expand2.dev.internal'
# kafka_zookeeper_host: 'iroha-expand2.dev.internal'
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
    y=$2
    for (( i=0; i<=$x-1; i++ ))
    do
        screen -S "fetch_log_extend1_1000${i}" -X stuff ^C
        screen -S "fetch_log_extend1_1000${i}" -X quit
        screen -S "fetch_log_extend2_1000${i}" -X stuff ^C
        screen -S "fetch_log_extend2_1000${i}" -X quit
    done

    for (( i=$x; i<=$x+$y-1; i++ ))
    do
        screen -S "fetch_log_extend1_1000${i}" -X stuff ^C
        screen -S "fetch_log_extend1_1000${i}" -X quit
        screen -S "run_playbook_${i}" -X stuff ^C
        screen -S "run_playbook_${i}" -X quit
    done
}

add_peer_to_expand_1() {
    k=$(( $1 + 1 ))
    create_config_expand1 $k
    echo 'config expand1:'
    cat $EXPAND_1
    echo ''
    echo "Running addPear scenario in a screen session run_playbook_${k}"
    screen -S "run_playbook_${k}" -dm
    screen -S "run_playbook_${k}" -X stuff 'docker-compose up ansible\r'
}

# Check if there are any running screen sessions left
if [[ -z $(screen -ls | grep -i 'no sockets found') ]]; then
    echo "Terminate all screen sessions first"
    echo "Exiting"
    exit 0
fi

N=$1
if [[ -z $N ]]; then
    N=4
fi

M=$2
if [[ -z $M ]]; then
    M=3
fi
echo "N = $N, M = $M"

# Re-create logs folder
rm -rf logs
mkdir logs

# Stop Iroha running containers running locally, if any
echo 'Stop running containers, if any'
docker stop $(docker ps | grep 'iroha' | cut -d' ' -f1)

echo 'Removing stale docker volumes'
docker volume rm $(docker volume ls -q | grep 'iroha_block_store')

# # Delete local Iroha networks in docker, if any
# echo 'Deleting Iroha networks in docker, if any'
# docker network rm $(docker network ls | grep iroha-net | cut -d' ' -f1)
# docker network rm $(docker network ls | grep iroha-db-net | cut -d' ' -f1)

# [1] Deploy Iroha from scratch
uncomment
create_config_expand1 $N
create_config_expand2 $N
echo 'Deploying Iroha anew'
run_playbook

echo 'Fetching logs for deployed peers'
sleep 10
fetch_logs $N 0

# [2] Run roles to add M peers one by one with 120 seconds break
comment
let first=${N}
let last=${N}+${M}-1
for (( j=${first}; j<=${last}; j++ ))
do
    echo "adding peer number ${j}"
    add_peer_to_expand_1 ${j}
    sleep 100
done

# [3]
echo 'Running fetch_logs script for newly deployed peers'
fetch_logs $N $M

# sleep 90
# close_screens $N $M