# Immagine del backend di sincronizzazione (Node 20).
FROM docker.io/library/node:20-alpine

WORKDIR /app
ENV NODE_ENV=production

# Installa solo le dipendenze di produzione (sfrutta la cache dei layer).
COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

# Codice sorgente.
COPY src ./src

EXPOSE 3000
# Esegui come utente non-root (presente nell'immagine node).
USER node

CMD ["node", "src/index.js"]
