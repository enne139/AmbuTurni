# Immagine della versione web: build Flutter multi-stage + backend Go
# (backend/, elenco condiviso ospedali), serviti insieme da nginx — un solo
# container, nginx fa da reverse proxy su /api/ verso il backend. Vedi
# .github/workflows/build-web.yml per come viene costruita e pubblicata.

# Stage 1: build della web app. Stessa immagine e versione pinnata di
# .github/workflows/build-android.yml (Flutter/SDK preinstallati, build
# riproducibili — aggiornarla a mano quando si aggiorna Flutter in locale).
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build-web
WORKDIR /app
COPY . .
# I binari SQLite WASM non sono versionati (vedi .gitignore): vanno
# rigenerati a ogni build, come in locale dopo un clone pulito.
RUN flutter pub get \
    && dart run sqflite_common_ffi_web:setup \
    && flutter build web --release

# Stage 2: build del backend Go, binario statico (CGO_ENABLED=0: nessuna
# libc richiesta nell'immagine finale, che non ha un toolchain Go).
FROM golang:1.25-alpine AS build-backend
WORKDIR /app/backend
COPY backend/go.mod backend/go.sum ./
RUN go mod download
COPY backend/. .
RUN CGO_ENABLED=0 go build -o /ambuturni-backend .

# Stage 3: nginx (file statici Flutter + reverse proxy) e il binario del
# backend, avviati insieme da docker-entrypoint.sh. Niente toolchain
# Flutter/Go nell'immagine finale.
FROM nginx:alpine
COPY --from=build-web /app/build/web /usr/share/nginx/html
COPY --from=build-backend /ambuturni-backend /app/backend/ambuturni-backend
COPY --from=build-backend /app/backend/public /app/backend/public
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh
EXPOSE 80
# Configurazione del backend (DATABASE_URL, JWT_SECRET, ADMIN_USERNAME/
# PASSWORD...) passata come variabili d'ambiente al container in produzione,
# vedi backend/.env.example per l'elenco — qui non ci sono default sensati
# per DATABASE_URL: senza, il backend fallisce l'avvio (non l'immagine nginx,
# che serve comunque i file statici: vedi docker-entrypoint.sh).
ENTRYPOINT ["/docker-entrypoint.sh"]
