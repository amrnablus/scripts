#!/bin/bash
until [ -f /gluetun/forwarded_port ]; do
  echo "waiting for /gluetun/forwarded_port to be available"
  sleep 2
done

if ! command -v curl >/dev/null; then
  apk add --no-cache curl
fi

CRONTAB_FILE=/etc/crontabs/root
mkdir -p /etc/periodic/1min

cp -af /custom-cont-init.d/configure_port.sh /etc/periodic/1min/
chmod +x /etc/periodic/1min/configure_port.sh

if ! grep -q '1min' "$CRONTAB_FILE" 2>/dev/null; then
  echo "*       *       *       *       *       run-parts /etc/periodic/1min" >> "$CRONTAB_FILE"
fi

# run once immediately instead of waiting up to a minute for the first cron tick
/etc/periodic/1min/configure_port.sh
