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
    "enableAppiumBehavior": "true",
    "automationName": "PerfectoMobile",
    "deviceName": "$deviceId"
  }
}
EOF
)

connectDevtunnelcapabilities=$(cat <<EOF
{
  "script": "mobile:devtunnel:execute",
  "args": [
    {
      "action": "start",
      "os": "$os"
    }
  ]
}
EOF
)

DisconectDevtunnelcapabilities=$(cat <<EOF
{
  "script": "mobile:devtunnel:execute",
  "args": [
    {
      "action": "stop"
    }
  ]
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
     curl -s --header "Content-Type: application/json" --request POST --data "$DisconectDevtunnelcapabilities" "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session/$ID/execute" > /dev/null
     curl -s  --request DELETE  "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session/$ID" > /dev/null
     sed -i.bak "/$ID/d" ./lastSessionID.txt
     printf "\nsession stopped\n" && exit 0
}


_stopnow() {

  test -f stopnow && echo "Stopping!" && rm stopnow && cleanup
}

printError(){
  printf "%s\n" "${red}$1${end}"
}

checkErrorAndExit(){
  if echo "$1" | grep -q "$2"; then
  printError "$3" && exit 0
  fi
}

checkErrorAndCleanUp(){
  if echo "$1" | grep -q "$2"; then
  printError "$3" && printf "%s\n" "${red}closing, please wait${end}" && cleanup
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

checkForErrorsAndCleanup(){
  checkErrorAndCleanUp "$1" "No\ SSH\ credentials" "No SSH credentials, deviceId $deviceId"
  checkErrorAndCleanUp "$1" "Failed\ to\ execute\ start\ tunnel\ script" "Failed to execute start tunnel script, deviceId $deviceId"
}

connectMac(){
  ERRORSUBSTRING='LSOpenURLsWithRole'
  RES=$(open "$Value" 2>&1)
  i="0"
  while [[ "$RES" == *"$ERRORSUBSTRING"* && $i -lt 10 ]]
  do
    i=$((i+1))
    echo "failed to open url, retrying."
    sleep 2
    RES=$(open "$Value" 2>&1)
  done
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

printf "%s\n" "${grn}starting Device session${end}"
SessionStartPostResponse=$(curl -s --header "Content-Type: application/json" --request POST --data "$OpenSessioncapabilities" "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session")
#echo "$SessionStartPostResponse"
checkForErrors "$SessionStartPostResponse"


ID=$(echo "$SessionStartPostResponse"| sed -e 's/.*sessionId":"\([^"]*\).*/\1/')

printf "%s\n" "$ID" >> lastSessionID.txt

printf "%s\n" "${grn}starting devTunnel connection${end}"
connectDevtunnelPostResponse=$(curl -s --header "Content-Type: application/json" --request POST --data "$connectDevtunnelcapabilities" "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session/$ID/execute")

checkForErrorsAndCleanup "$connectDevtunnelPostResponse"

checkIfDeviceIsIOS() {
  decoded=$(echo $value | base64 -d)
  modified=$decoded
  decodedValueDb=$(echo "$decoded" | jq -r '.db')
  decodedValueDa=$(echo "$decoded" | jq -r '.da')
  if [ "$decodedValueDa" != "null" -a ${#decodedValueDb} -le 15 ]; then
    modified=$(echo "$decoded"| sed -e 's/\"d\":\"0\"/\"d\":\"1\"/')
  fi
  encoded=$(echo $modified | base64)
}

Value=$(echo "$connectDevtunnelPostResponse"| sed -e 's/.*value":"\([^"]*\).*/\1/')


printf "%s\n" "${grn}opening devtunnel application${end}"



if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if xhost >& /dev/null ; then
           "$Value"
        else
            value=$(echo "$connectDevtunnelPostResponse" | jq '.value' | sed -e 's/.*\?d=\(.*\)"/\1/')

            checkIfDeviceIsIOS

            perfectoDevTunnel='/usr/local/etc/stunnel/PerfectoDevTunnel.jar'

            output=$(java -Djdk.http.auth.tunneling.disabledSchemes=\"\" -jar $perfectoDevTunnel "$encoded" 2>&1)

            printf "%s\n" "${output}"

            errors=$(echo "$output" | tail -n1 | grep Error | grep -v handshake | grep -v proxy)

            if [ -z "$errors" ]; then
              printf "%s\n" "${grn} ${end}"
            else
              printf "%s\n" "${red}Can not establish connection${end}"
              printf "%s\n" "${red}[ERROR]${errors}${end}"
              cleanup
            fi
          fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
        connectMac
elif [[ "$OSTYPE" == "cygwin" ]]; then
        cygstart "$Value"
elif [[ "$OSTYPE" == "msys" ]]; then
        start "$Value"
elif [[ "$OSTYPE" == "win32" ]]; then
        start "$Value"
elif [[ "$OSTYPE" == "freebsd"* ]]; then
        echo "freebsd"
fi

printf "%s\n" "${grn}connection established${end}"

while sleep 20
do
  keepAlivePostResponse=$(curl -s --header "Content-Type: application/json" --request POST --data "$KeepAliveCapabilities" "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session/$ID/execute")
  _stopnow
done

