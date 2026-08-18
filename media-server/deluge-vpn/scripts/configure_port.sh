#!/bin/bash
until [ -f /gluetun/forwarded_port ]; do
  echo "waiting for /gluetun/forwarded_port to be available"
  sleep 2
done

FORWARDED_PORT=$(cat /gluetun/forwarded_port)

cookie=$(curl -s -v -H "Content-Type: application/json" \
  -d '{"method": "auth.login", "params": ["'"$DELUGE_PASSWORD"'"], "id": 1}' \
  http://localhost:8112/json 2>&1 | grep -i '< set-cookie' | cut -d':' -f2 | cut -d';' -f1)

# deluge-web only proxies core.* RPC methods once explicitly connected to a
# daemon host; that connection doesn't persist across container restarts, so
# reconnect every run before touching core.set_config.
host_id=$(curl -s -H "cookie:$cookie" -H "Content-Type: application/json" \
  -d '{"method": "web.get_hosts", "params": [], "id": 1}' \
  http://localhost:8112/json | python3 -c "import json,sys; print(json.load(sys.stdin)['result'][0][0])")

curl -s -H "cookie:$cookie" -H "Content-Type: application/json" \
  -d '{"method": "web.connect", "params": ["'"$host_id"'"], "id": 1}' \
  http://localhost:8112/json >/dev/null

curl -s -H "cookie:$cookie" -H "Content-Type: application/json" \
  -d '{"method": "core.set_config", "params": [{"listen_ports": ['"$FORWARDED_PORT"', '"$FORWARDED_PORT"'], "random_port": false}], "id": 1}' \
  http://localhost:8112/json

echo "set Deluge listen port to $FORWARDED_PORT"
