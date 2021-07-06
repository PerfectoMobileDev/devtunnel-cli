#!/bin/bash

filename='lastSessionID.txt'

if [ ! -f "$filename" ]; then
    echo "no sessions to clean" && exit 0
fi

domain=$1

Thirdcapabilities=$(cat <<EOF
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

n=1
while read line; do
# reading each line
echo "Line No. $n : $line"
curl -s --header "Content-Type: application/json" --request POST --data "$Thirdcapabilities" "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session/$line/execute" > /dev/null
curl -s  --request DELETE  "https://$domain.perfectomobile.com/nexperience/perfectomobile/wd/hub/session/$line" > /dev/null && printf "\nsession stopped\n"
n=$((n+1))
done < $filename

rm $filename


