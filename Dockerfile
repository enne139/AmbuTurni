# Immagine della versione web: build Flutter multi-stage, nginx serve solo
# i file statici prodotti. Vedi .gitea/workflows/build-web.yml per come
# viene costruita e pubblicata.

# Stage 1: build della web app. Stessa immagine e versione pinnata di
# .gitea/workflows/build-android.yml (Flutter/SDK preinstallati, build
# riproducibili — aggiornarla a mano quando si aggiorna Flutter in locale).
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build
WORKDIR /app
COPY . .
# I binari SQLite WASM non sono versionati (vedi .gitignore): vanno
# rigenerati a ogni build, come in locale dopo un clone pulito.
RUN flutter pub get \
    && dart run sqflite_common_ffi_web:setup \
    && flutter build web --release

# Stage 2: solo nginx + i file statici, niente toolchain Flutter nell'immagine finale.
FROM nginx:alpine
COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
