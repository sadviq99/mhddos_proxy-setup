#!/bin/bash

# Enable debug mode to see what we send to Telegram
set -x

# Get billing info only if DO variable set
if [ ! -z "$DIGITALOCEAN_TOKEN" ]; then
    BAL_RESPONSE=$(curl -s -X GET \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $DIGITALOCEAN_TOKEN" \
      "https://api.digitalocean.com/v2/customers/my/balance")
    BAL_BAL=$(echo $BAL_RESPONSE | jq '.month_to_date_balance' | bc)
    BAL_USG=$(echo $BAL_RESPONSE | jq '.month_to_date_usage' | bc)
fi

# Static link to targets health checks
HEALTH_URL="https://itarmy.com.ua/check/"

# Save large output to a file
LOGS=$(mktemp)
docker inspect --format='{{.LogPath}}' $(docker compose ps | tail -n -1 | awk '{print $1}') | xargs jq -r -j .log > $LOGS

# Get most important info
THREADS=$(grep -o Threads.* $LOGS| tail -n 1 | cut -d' ' -f 2)
PROXIES=$(grep -o Proxies.* $LOGS | tail -n 1 | cut -d' ' -f 2)
TOTAL=$(grep -o Total.* $LOGS | tail -n 1)
CONNECTIONS=$(echo $TOTAL | cut -d' ' -f 3 | sed s/,//)
REQUESTS=$(echo $TOTAL | cut -d' ' -f 5 | sed s/,//)
TRAFFIC=$(echo $TOTAL | cut -d' ' -f 7,8)

# Find the top 5 targets by traffic
ALL_TOTALS=$(grep Total $LOGS| wc -l)
ALL_TARGETS=$(awk -v start=$(($ALL_TOTALS-1)) '/Total/{n++;next};n==start;n==start+1{exit}' $LOGS | grep -o Target.*)
TARGETS_MB=$(echo "$ALL_TARGETS" | grep 'MB' | cut -d' ' -f 2,13,14 | sed s/,// | sort -u -k2 -n -r | awk -F' ' '!_[$1]++')
TARGETS_KB=$(echo "$ALL_TARGETS" | grep 'kBit' | cut -d' ' -f 2,13,14 | sed s/,// | sort -u -k2 -n -r | awk -F' ' '!_[$1]++')
TARGETS_B=$(echo "$ALL_TARGETS" | grep ' Bit' | cut -d' ' -f 2,13,14 | sed s/,// | sort -u -k2 -n -r | awk -F' ' '!_[$1]++')
TOP_5_TARGETS=$(echo -e "$TARGETS_MB\n$TARGETS_KB\n$TARGETS_B" | sed '/^$/d' | awk -F' ' '!_[$1]++' | head -n 5 | sed 's/ / \`(/' | sed 's/$/)\`/')

# Compose a message
message="*Host*: \`$(hostname)\`"
message+="%0A"
if [ ! -z "$DIGITALOCEAN_TOKEN" ]; then
    message+="*Balance/To pay*: \`$BAL_BAL\`/\`$BAL_USG\`"
    message+="%0A"
fi
message+="*Threads/Proxies*: \`$THREADS\`/\`$PROXIES\`"
message+="%0A"
message+="*Total connections*: \`$CONNECTIONS\`"
message+="%0A"
message+="*Total requests*: \`$REQUESTS\`"
message+="%0A"
message+="*Total traffic*: \`$TRAFFIC\`"
message+="%0A"
message+="*Top 5 targets by traffic*:"
message+="%0A"
message+="$TOP_5_TARGETS"

keyboard="{\"inline_keyboard\":[[{\"text\":\"Open health report\", \"url\":\"${HEALTH_URL}\"}]]}"

# Send to Telegram
curl -s --data "text=${message}" \
        --data "reply_markup=${keyboard}" \
        --data "chat_id=$TG_CHAT_ID" \
        --data "parse_mode=markdown" \
        "https://api.telegram.org/bot${TG_TOKEN}/sendMessage"

# Remove logs file
rm $LOGS
