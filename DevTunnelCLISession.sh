#!/bin/bash


red=$'\e[1;31m'
grn=$'\e[1;32m'
end=$'\e[0m'

filename='token.txt'
token=$(head -n 1 $filename)
domain=$1
deviceId=$2
os=$3

OpenSessioncapabilities=$(cat <<EOF
{
  "desiredCapabilities": {
    "securityToken": "$token",
    "deviceName": "$deviceId"
  }
}
EOF
)

KeepAliveCapabilities=$(cat <<EOF
{
  "script": "keep-alive",
  "args": [
    {
      "action": "stop"
    }
  ]
}
EOF
)


trap cleanup SIGTERM SIGINT SIGQUIT SIGHUP


cleanup()
{
     printf "closing session, please wait\n"
     curl -s  --request DELETE  "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session/$ID" > /dev/null
     sed -i.bak "/$ID/d" ./lastSessionID.txt
     printf "\nsession stopped\n" && exit 0 || return 0
}


_stopnow() {

  test -f stopnow && echo "Stopping!" && rm stopnow && cleanup
}

if [ -z "$domain" ]
then
      echo "domain is empty"&& exit 0
fi
if [ -z "$token" ]
then
      echo "token is empty"&& exit 0
fi
if [ -z "$os" ]
then
      echo "os is empty"&& exit 0
fi


test -f stopnow && rm stopnow

printError(){
  printf "%s\n" "${red}$1${end}"
}

checkErrorAndExit(){
  if echo "$1" | grep -q "$2"; then
  printError "$3" && exit 0
  fi
}

checkForErrors(){
  checkErrorAndExit "$1" "Device\ not\ found" "device $deviceId not found"
  checkErrorAndExit "$1" "device\ is\ in\ use" "device $deviceId is in use"
  checkErrorAndExit "$1" "Invalid\ refresh\ token" "Invalid token"
  checkErrorAndExit "$1" "not\ connected" "device $deviceId not connected"
  checkErrorAndExit "$1" "Internal\ Server\ Error" "cloud $domain not found"
  checkErrorAndExit "$1" "unknown\ error" "unknown error, device $deviceId"
  checkErrorAndExit "$1" "Unable\ to\ authenticate" "unable to authenticate request, device $deviceId"
}

printf "%s\n" "${grn}starting Device session${end}"
SessionStartPostResponse=$(curl -s --header "Content-Type: application/json" --request POST --data "$OpenSessioncapabilities" "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session")


checkForErrors "$SessionStartPostResponse"

ID=$(echo "$SessionStartPostResponse"| sed -e 's/.*sessionId":"\(.*\)","value".*/\1/')

printf "%s\n" "${grn}$ID${end}"

printf "%s\n" "$ID" >> lastSessionID.txt



while sleep 20
do
  keepAlivePostResponse=$(curl -s --header "Content-Type: application/json" --request POST --data "$KeepAliveCapabilities" "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session/$ID/execute")
  _stopnow
done

