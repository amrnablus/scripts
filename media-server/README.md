# media-server

Docker-based media stack: VPN-isolated Deluge, Jellyfin, and the Servarr suite
(Sonarr/Radarr/Prowlarr) wired together for fully automated TV/movie
acquisition.

## Layout

- `deluge-vpn/` -- Gluetun (ProtonVPN WireGuard, kill-switch firewall,
  NAT-PMP port forwarding) + Deluge sharing its network namespace, so all
  torrent traffic is routed through the VPN tunnel with no leak path.
  `scripts/setup.sh` runs once at container start (linuxserver.io
  `/custom-cont-init.d` convention) and installs `configure_port.sh` as a
  1-minute cron job, which keeps Deluge's listen port in sync with
  whatever port Proton's NAT-PMP client forwards (it changes on
  reconnect/restart).
- `jellyfin/` -- media server, watches `~/Downloads/torrents` and (once
  wired up) `~/media/tv` / `~/media/movies`.
- `arr-stack/` -- Prowlarr (indexer manager) + Sonarr (TV) + Radarr
  (movies), each bound to `127.0.0.1` only and joined to the
  `deluge-vpn` project's Docker network so they can reach Deluge's WebUI
  by container name (`gluetun:8112`) without exposing anything to the
  LAN. Prowlarr syncs its indexers into both apps automatically via the
  Applications feature.

## Setup

1. `cd deluge-vpn && cp .env.example .env` and fill in a real
   `WIREGUARD_PRIVATE_KEY` (from ProtonVPN's WireGuard config generator --
   Plus tier required for P2P/BitTorrent) and a non-default
   `DELUGE_PASSWORD`.
2. `docker compose up -d` in `deluge-vpn/`, then `jellyfin/`, then
   `arr-stack/` (in that order -- `arr-stack` depends on `deluge-vpn`'s
   network already existing, named `deluge-vpn_default`).
3. In Sonarr/Radarr, add Deluge as a download client (host `gluetun`,
   port `8112`) and in Prowlarr, connect both as Applications with
   `fullSync` so indexers propagate automatically.

## Notes

- `.env` files are gitignored -- never commit VPN keys or app passwords.
- Deluge's WebUI password is shared with Sonarr's and Radarr's download
  client configs; if you rotate it, update all three.
- `host.docker.internal` is deliberately avoided throughout -- containers
  that need to talk to each other are put on the same Docker network
  instead.
