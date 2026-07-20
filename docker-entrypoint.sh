#!/bin/sh
# Avvia il backend Go in sottofondo e nginx in primo piano (PID 1, riceve i
# segnali di `docker stop`). Se il backend fallisce l'avvio (es.
# DATABASE_URL non configurato) nginx continua comunque a servire i file
# statici della web app — solo le chiamate a /api/ falliranno, non l'intero
# container. Per questo NON c'è un HEALTHCHECK Docker sul container intero:
# farebbe riavviare anche nginx per un backend mal configurato, vanificando
# la scelta sopra.
set -e

# Il backend gira in un piccolo loop di riavvio: senza, un crash *dopo* un
# avvio riuscito (es. connessione al pool persa) lo lasciava morto in
# permanenza — nginx restava su, ma /api/* falliva silenziosamente finché
# qualcuno non riavviava a mano il container. Il backoff fisso di 2s è
# volutamente minimale (nessun caso reale in cui la causa del crash sparisca
# da sola più lentamente): se la causa è persistente (es. JWT_SECRET non
# configurato, che ora termina subito il processo) il loop continua a
# ritentare, visibile nei log invece di restare silenzioso.
(
  cd /app/backend
  while true; do
    ./ambuturni-backend
    echo "[entrypoint] backend Go terminato (exit $?): riavvio tra 2s..." >&2
    sleep 2
  done
) &

exec nginx -g 'daemon off;'
