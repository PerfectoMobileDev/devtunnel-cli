#!/bin/bash

red=$'\e[1;31m'
grn=$'\e[1;32m'
end=$'\e[0m'

domain=$1
os=$2
input="DeviceList.txt"

readLineIndex=0
while IFS= read -r line  || [ -n "$line" ]
do
  deviceIdArray[readLineIndex]=$line
  readLineIndex=$((readLineIndex+1))
done < "$input"


prep_term()
{
    unset term_kill_needed
    trap 'handle_term' TERM INT
}

handle_term()
{
    if [ "${term_child_pid[0]}" ]; then
        for ((i=0; i<readLineIndex; i++))
        do
          kill -TERM "${term_child_pid[$i]}" 2>/dev/null
        done
    else
        term_kill_needed="yes"
    fi
}

wait_term()
{
    if [ "${term_kill_needed}" ]; then
        for ((i=0; i<readLineIndex; i++))
        do
          kill -TERM "${term_child_pid[$i]}" 2>/dev/null
        done
    fi
    for ((i=0; i<readLineIndex; i++))
    do
      wait "${term_child_pid[$i]}" 2>/dev/null
    done
    trap - TERM INT
    for ((i=0; i<readLineIndex; i++))
    do
      wait "${term_child_pid[$i]}" 2>/dev/null
    done
}

prep_term
for ((i=0; i<readLineIndex; i++))
do
   echo "${deviceIdArray[$i]}"
   /bin/bash DevTunnelCLI.sh "$domain" "${deviceIdArray[$i]}" "$os" &
   term_child_pid[$i]=$!
   sleep 15
done
wait_term "$term_child_pid1" "$term_child_pid2"