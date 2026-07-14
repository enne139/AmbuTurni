#!/bin/sh
# Avvia il backend Go in sottofondo e nginx in primo piano (PID 1, riceve i
# segnali di `docker stop`). Se il backend fallisce l'avvio (es.
# DATABASE_URL non configurato) nginx continua comunque a servire i file
# statici della web app — solo le chiamate a /api/ falliranno, non l'intero
# container.
set -e

(cd /app/backend && ./ambuturni-backend) &

exec nginx -g 'daemon off;'
