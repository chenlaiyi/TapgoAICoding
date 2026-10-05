# Shared mobile relay

English | [中文](README.zh.md)

The public relay uses one A record for `relay.itapgo.com` and one wildcard A record for `*.remote.itapgo.com`. Nginx terminates HTTPS for both names. It passes `/~!frp` on the control name to the loopback FRP control port and device-host requests to the loopback FRP HTTP port. Desktop opens an outbound WSS connection on port 443 and forwards requests to its loopback Host on port 19388. The Host browser token, rather than the device hostname, authorizes phone requests.

The [FRP server configuration](shared-relay.frps.toml), [systemd unit](tapgo-relay.service), [Nginx configuration](public-mobile.nginx.conf), and [certificate renewal hook](tapgo-relay-cert-renew.sh) are deployed on the relay server. Certbot uses [the DNS hook](certbot-alidns-hook.py) for `relay.itapgo.com` and `*.remote.itapgo.com`; its Alibaba Cloud credentials are root-readable only. The certificate deploy hook copies the renewed certificate to the FRP service's readable directory and reloads Nginx. FRP's control and HTTP listeners remain on loopback.

An administrator places a relay token in a mode-600 file on each managed Mac, then configures `TAPGO_RELAY_DOMAIN=remote.itapgo.com`, `TAPGO_RELAY_SERVER=relay.itapgo.com`, and `TAPGO_RELAY_TOKEN_FILE=<absolute path>` in `~/.tapgo-aicoding/.env`. On launch, Desktop creates a stable random device ID under `~/.tapgo-aicoding/tapgo-mobile-relay`, starts its packaged frpc 0.71.0, and displays the resulting authenticated HTTPS link in **Connect iPhone**. The iOS app pairs through that link and distinguishes Macs by their device hostnames. Existing dedicated-host links remain usable until they are removed from the phone.

The shared FRP token permits any holder to register an available subdomain. Provision it only to managed Macs under one trusted administrator; do not distribute it to untrusted customer devices. A compromised token must be rotated on the server and every enrolled Mac. The phone link also grants access to Host sessions and command execution; treat it as a credential and re-pair after Host authentication expires.
