#!/bin/bash

red=$'\e[31m'
grn=$'\e[32m'
end=$'\e[0m'

perfectoDevTunnel='/usr/local/etc/stunnel/PerfectoDevTunnel.jar'
jsonFile="account.json"
domain="king"
liveViewUrl="https://king.app.perfectomobile.com/executions"

Help() {
  echo "This script opens a session in Perfecto for a specific device, starts the DevTunnel for that session and keeps alive the DevTunnel connection until closed."
  echo "After running the script, it will be left opened, and by canceling the process (Ctrl-C) it will close the connection from Perfecto."
  echo
  echo "Syntax: ./DevTunnel.sh -d <deviceId> -o <deviceOS> [-dm <domain>] [-s <sessionId>]"
  echo
  echo "Options:"
  echo "    -d | --device-id      Device id"
  echo "    -o | --device-os      Device OS"
  echo "    -dm | --domain        [OPT] Perfecto's domain (default: 'king')"
  echo "    -s | --session-id     [OPT] Session id, sent only if wanting to delete the session"
  echo
}

if [ ! -f "$jsonFile" ]; then
  printf "%s\n\n" "${red}[ERROR] Account information not provided${end}"
  printf "%s\n" "The json file with your account (account.json) does not exist."
  printf "%s\n" "Copy the template and fill it with your Perfecto values (token)."
  exit 1
fi

token=$(jq '.token' $jsonFile)
token=${token//\"/}

if [ -z "$token" ]; then
  printf "%s\n\n" "${red}[ERROR] The token is not found or empty in $jsonFile${end}"
  printf "%s\n" "The json file with your account (account.json) exists but does not contain the token value."
  exit 1
fi

if [ -z "$JAVA11" ]; then
  printf "%s\n\n" "${red}[ERROR] This scripts needs to run with a specific Java version.${end}"
  printf "%s\n" "Please, export a variable named \"JAVA11\" that points to your Java path."
  printf "%s\n" "Example: export JAVA11=/Library/Java/JavaVirtualMachines/jdk-11.0.19.jdk/Contents/Home/bin/java"
  exit 1
fi

while [ "$1" != "" ]; do
  case $1 in
  -d | --device-id)
    shift
    deviceId=$1
    ;;
  -o | --device-os)
    shift
    deviceOS=$1
    ;;
  -dm | --domain)
    shift
    domain=$1
    ;;
  -s | --session-id)
    shift
    sessionId=$1
    ;;
  -h | --help)
    Help && exit 0
    ;;
  *)
    Help && exit 1
    ;;
  esac
  shift
done

if [ -z "$deviceId" ]; then
  printf "%s\n\n" "${red}[ERROR] Device id is a required parameter.${end}"
  Help && exit 1
fi
if [ -z "deviceOS" ]; then
  printf "%s\n\n" "${red}[ERROR] Device OS is a required parameter.${end}"
  Help && exit 1
fi
if [ -z "$OSTYPE" ]; then
  printf "%s\n\n" "${red}[ERROR] OS is not defined in the environment variable OSTYPE.${end}"
  Help && exit 1
fi

OpenSessionCapabilities=$(cat <<EOF
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

ConnectDevTunnelCapabilities=$(cat <<EOF
{
  "script": "mobile:devtunnel:execute",
  "args": [
    {
      "action": "start",
      "os": "$deviceOS"
    }
  ]
}
EOF
)

DisconnectDevTunnelCapabilities=$(cat <<EOF
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

cleanUp() {
  printf "\n%s\n" "${grn}Closing session and disconnecting device. Please wait...${end}"

  curl -s \
    --header "Content-Type: application/json" \
    --request POST \
    --data "$DisconnectDevTunnelCapabilities" \
    "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session/$sessionId/execute" >/dev/null

  curl -s \
    --request DELETE \
    "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session/$sessionId" >/dev/null

  printf "%s\n" "${grn}Session stopped${end}"

  if [[ $# -ne 1 ]]; then
    exit 0
  else
    exit $1
  fi
}

checkErrorAndExit() {
  if echo "$1" | grep -q "$2"; then
    printf "%s\n" "${red}[ERROR] $3${end}" && exit 1
  fi
}

checkErrorAndCleanUp() {
  if echo "$1" | grep -q "$2"; then
    printf "%s\n" "${red}[ERROR] $3${end}"
    cleanUp 1
  fi
}

checkForErrorsOpenSession() {
  checkErrorAndExit "$1" "Device\ not\ found" "Device not found"
  checkErrorAndExit "$1" "device\ is\ in\ use" "Device is in use"
  checkErrorAndExit "$1" "Invalid\ refresh\ token" "Invalid token"
  checkErrorAndExit "$1" "not\ connected" "Device not connected"
  checkErrorAndExit "$1" "Internal\ Server\ Error" "Cloud $domain not found"
  checkErrorAndExit "$1" "unknown\ error" "Unknown error, device $deviceId"
  checkErrorAndExit "$1" "Unable\ to\ authenticate" "Unable to authenticate request, device $deviceId"

  status=$(echo "$openSessionResult" | jq -r '.status')
  message=$(echo "$openSessionResult" | jq -r '.value.message')
  if [ "$status" -ne 0 ]; then
    printf "%s\n" "${red}[ERROR][Status:$status] $message${end}" && exit 1
  fi
}

checkForErrorsConnectDevTunnel() {
  checkErrorAndCleanUp "$1" "No\ SSH\ credentials" "No SSH credentials, device $deviceId, sessionId $sessionId"
  checkErrorAndCleanUp "$1" "Failed\ to\ execute\ start\ tunnel\ script" "Failed to execute start tunnel script, device $deviceId, sessionId $sessionId"
}

checkForErrorsKeepAlive() {
  checkErrorAndCleanUp "$1" "error" "Error sent while keeping session alive, device $deviceId, sessionId $sessionId"
}

checkIfDeviceIsIOS() {
  decoded=$(echo "$value" | base64 -d)
  modified=$decoded
  decodedValueDb=$(echo "$decoded" | jq -r '.db')
  decodedValueDa=$(echo "$decoded" | jq -r '.da')
  if [ "$decodedValueDa" != "null" ] && [ ${#decodedValueDb} -le 15 ]; then
    modified=$(echo "$decoded" | sed -e 's/\"d\":\"0\"/\"d\":\"1\"/')
  fi
  value=$(echo "$modified" | base64)
}

connectUsingDevTunnel() {
  value=$(echo "$connectDevTunnelResult" | jq '.value' | sed -e 's/.*\?d=\(.*\)"/\1/')

  printf "%s\n" "DevTunnel encoded response: ${value}"

  checkIfDeviceIsIOS

  printf "%s\n" "${grn}Printing stunnel process${end}"
  stunnel=$(ps aux | grep stunnel)
  printf "%s\n" "${stunnel}"

  printf "%s\n" "${grn}Opening DevTunnel application${end}"

  log_file="/tmp/devtunnel-connection.log"
  output=$($JAVA11 -Djdk.http.auth.tunneling.disabledSchemes=\"\" -jar $perfectoDevTunnel "$value" >> ${log_file} 2>&1)
  printf "%s\n" "${output}"

  successfulLine=$(echo "$output" | grep "INFO: Done!")

  if [ -z "$successfulLine" ]; then
    errors=$(echo "$output" | grep -i Error)
    printf "%s\n" "${red}Can not establish connection${end}"
    printf "%s\n" "${red}[ERROR] ${errors}${end}"
    cleanUp 2
  else
    printf "%s\n" "${grn}Connection established${end}"
  fi
}

trap cleanUp SIGTERM SIGINT SIGQUIT SIGHUP

printf "%s\n" "${grn}Using Perfecto domain:${end} $domain"

# CLOSE SESSION IF PARAM IS SENT

if [ -n "$sessionId" ]; then
  printf "\n%s\n" "${grn}Ending session with id:${end} ${sessionId}"
  cleanUp
fi

# START SESSION

printf "\n%s\n" "${grn}Starting device session for device with id:${end} ${deviceId}"

openSessionResult=$(curl -s \
  --header "Content-Type: application/json" \
  --request POST \
  --data "$OpenSessionCapabilities" \
  "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session")
checkForErrorsOpenSession "$openSessionResult"

sessionId=$(echo "$openSessionResult" | sed -e 's/.*sessionId":"\([^"]*\).*/\1/')
if [ -n "$sessionId" ]; then
  printf "%s\n" "Session id: $sessionId"
  printf "%s\n" "Live view URL: $liveViewUrl"
fi

# START DEVTUNNEL

printf "\n%s\n" "${grn}Starting DevTunnel connection for session with id:${end} ${sessionId}"

connectDevTunnelResult=$(curl -s \
  --header "Content-Type: application/json" \
  --request POST \
  --data "$ConnectDevTunnelCapabilities" \
  "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session/$sessionId/execute")
checkForErrorsConnectDevTunnel "$connectDevTunnelResult"

value=$(echo "$connectDevTunnelResult"| sed -e 's/.*value":"\([^"]*\).*/\1/')

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  if xhost >& /dev/null ; then
    "$value"
  else
    connectUsingDevTunnel
  fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
  ERRORSUBSTRING='LSOpenURLsWithRole'
  RES=$(open "$value" 2>&1)
  i="0"
  while [[ "$RES" == *"$ERRORSUBSTRING"* && $i -lt 10 ]]
  do
    i=$((i+1))
    printf "%s\n" "${red}Failed to open url, retrying.${end}"
    sleep 2
    RES=$(open "$value" 2>&1)
  done
elif [[ "$OSTYPE" == "cygwin" ]]; then
  cygstart "$value"
elif [[ "$OSTYPE" == "msys" ]]; then
  start "$value"
elif [[ "$OSTYPE" == "win32" ]]; then
  start "$value"
elif [[ "$OSTYPE" == "freebsd"* ]]; then
  echo "freebsd"
fi

# KEEP ALIVE

printf "\n%s\n" "${grn}Starting keep alive process for session with id:${end} ${sessionId}"
printf "%s\n" "One call will be done every 20 seconds to maintain the session alive."

waitTime=20
accumulatedTime=0

while sleep 1; do
  if [ $accumulatedTime -ge $waitTime ]; then
    accumulatedTime=0
    printf "\n%s\n" "${grn}Keeping alive session with id:${end} ${sessionId}"
    keepAliveResult=$(curl -s \
      --header "Content-Type: application/json" \
      --request POST \
      --data "$KeepAliveCapabilities" \
      "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session/$sessionId/execute")
    checkForErrorsKeepAlive "$keepAliveResult"
    printf "%s\n" "${keepAliveResult}"
  else
    ((accumulatedTime += 1))
  fi
done
