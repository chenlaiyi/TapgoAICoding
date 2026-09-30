#!/bin/sh
set -eu
if [ "${RENEWED_LINEAGE:-}" != /etc/letsencrypt/live/tapgo-shared-relay ]; then exit 0; fi
install -o root -g tapgo-relay -m 0640 "$RENEWED_LINEAGE/fullchain.pem" /etc/tapgo-relay/fullchain.pem
install -o root -g tapgo-relay -m 0640 "$RENEWED_LINEAGE/privkey.pem" /etc/tapgo-relay/privkey.pem
systemctl try-restart tapgo-relay.service
/www/server/nginx/sbin/nginx -t
/www/server/nginx/sbin/nginx -s reload
