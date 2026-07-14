# Immagine di sviluppo/test del solo backend (Go). In produzione questo
# codice è compilato dentro l'immagine web (vedi il Dockerfile alla radice
# del repo): questo file serve solo per `docker compose up` in questa
# cartella, senza dover buildare tutta la web app Flutter.
FROM golang:1.25-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o /ambuturni-backend .

FROM alpine:3.20
WORKDIR /app
COPY --from=build /ambuturni-backend ./ambuturni-backend
COPY public ./public
EXPOSE 3000
USER nobody
CMD ["./ambuturni-backend"]
