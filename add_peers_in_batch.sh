#!/bin/sh

SCRIPT_DIR=$(pwd)
MAIN_YML="$SCRIPT_DIR/ansible/roles/iroha-docker/tasks/main.yml"
EXPAND_1="$SCRIPT_DIR/ansible/playbooks/iroha-expand/host_vars/tag_name_iroha_expand1.yml"
EXPAND_2="$SCRIPT_DIR/ansible/playbooks/iroha-expand/host_vars/tag_name_iroha_expand2.yml"

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
    x=$1
    echo "#IROHA" > $EXPAND_1
    echo "iroha_replicas: $x" >> $EXPAND_1
    echo "iroha_custom_hostnames: true" >> $EXPAND_1
    echo "iroha_hostnames:" >> $EXPAND_1
    for (( i=1; i<=$x; i++ ))
    do
        echo '  - "iroha-expand1.dev.internal"' >> $EXPAND_1
    done
    cat >> $EXPAND_1 <<- EOM


iroha_service_host: True
iroha_service_account: 'admin@nbc'
iroha_service_account_keys: ['72a9eb49c0cd469ed64f653e33ffc6dde475a6b9fd8be615086bce7c44b5a8f8']
EOM
}

create_config_expand2()
{
    x=$1
    echo "#IROHA" > $EXPAND_2
    echo "iroha_replicas: $x" >> $EXPAND_2
    echo "iroha_custom_hostnames: true" >> $EXPAND_2
    echo "iroha_hostnames:" >> $EXPAND_2
    for (( i=1; i<=$x; i++ ))
    do
        echo '  - "iroha-expand2.dev.internal"' >> $EXPAND_2
    done
    cat >> $EXPAND_2 <<- EOM


kafka_host: 'iroha-expand2.dev.internal'
kafka_zookeeper_host: 'iroha-expand2.dev.internal'
EOM
}

fetch_logs()
{
    x=$1
    y=$2
    for (( i=1; i<=$x; i++ ))
    do
        screen -S "fetch_log_extend1_1000${i}" -dm 
        screen -S "fetch_log_extend1_1000${i}" -X stuff "ssh -i ~/.ssh/id_rsa ekovalev@iroha-expand1.dev.iroha.tech docker logs c_iroha_expand1_dev_internal_1000${i} -f | tee logs/extend1_1000${i}.log\r"
        screen -S "fetch_log_extend2_1000${i}" -dm 
        screen -S "fetch_log_extend2_1000${i}" -X stuff "ssh -i ~/.ssh/id_rsa ekovalev@iroha-expand2.dev.iroha.tech docker logs c_iroha_expand2_dev_internal_1000${i} -f | tee logs/extend2_1000${i}.log\r"
    done
    sleep 120
    for (( i=$x+1; i<=$x+$y; i++ ))
    do
        screen -S "fetch_log_extend1_1000${i}" -dm 
        screen -S "fetch_log_extend1_1000${i}" -X stuff "ssh -i ~/.ssh/id_rsa ekovalev@iroha-expand1.dev.iroha.tech docker logs c_iroha_expand1_dev_internal_1000${i} -f | tee logs/extend1_1000${i}.log\r"
    done
}

close_screens()
{
    x=$1
    y=$2
    for (( i=1; i<=$x; i++ ))
    do
        screen -S "fetch_log_extend1_1000${i}" -X stuff ^C
        screen -S "fetch_log_extend1_1000${i}" -X quit
        screen -S "fetch_log_extend2_1000${i}" -X stuff ^C
        screen -S "fetch_log_extend2_1000${i}" -X quit
    done

    for (( i=$x+1; i<=$x+$y; i++ ))
    do
        screen -S "fetch_log_extend1_1000${i}" -X stuff ^C
        screen -S "fetch_log_extend1_1000${i}" -X quit
    done
    screen -S "run_playbook" -X quit
}

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

# [1] Deploy Iroha from scratch
uncomment
create_config_expand1 $N
create_config_expand2 $N
echo 'Deploying Iroha anew'
run_playbook

# [2] Run roles to add M peers to the initial set of 2*N ones
comment
create_config_expand1 $(( $N + $M ))
echo 'Running addPear scenario in a screen session'
screen -S "run_playbook" -dm
screen -S "run_playbook" -X stuff 'docker-compose up ansible\r'

# [3]
echo 'Running fetch_logs script'
fetch_logs $N $M

# sleep 90
# close_screens $N $M