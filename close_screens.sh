#!/bin/sh

close_screens()
{
    x=$1
    y=$2
    for (( i=0; i<=$x-1; i++ ))
    do
        echo "Stopping screen session fetch_log_extend1_1000${i}"
        screen -S "fetch_log_extend1_1000${i}" -X stuff ^C
        screen -S "fetch_log_extend1_1000${i}" -X quit
        echo "Stopping screen session fetch_log_extend2_1000${i}"
        screen -S "fetch_log_extend2_1000${i}" -X stuff ^C
        screen -S "fetch_log_extend2_1000${i}" -X quit
    done

    for (( i=$x; i<=$x+$y-1; i++ ))
    do
        echo "Stopping screen session fetch_log_extend1_1000${i}"
        screen -S "fetch_log_extend1_1000${i}" -X stuff ^C
        screen -S "fetch_log_extend1_1000${i}" -X quit
        echo "Stopping screen session run_playbook_${i}"
        screen -S "run_playbook_${i}" -X stuff ^C
        screen -S "run_playbook_${i}" -X quit
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

echo 'Closing screen sessions'
close_screens $N $M