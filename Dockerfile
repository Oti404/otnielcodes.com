# syntax=docker/dockerfile:1

# ---------- Stage 1: build Angular ----------
# Node 22 LTS: Node 20 a ajuns la end-of-life în aprilie 2026, iar Angular 21 suportă ^20.19 || ^22.12 || >=24.
FROM node:22.23.4-alpine3.24 AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY . .
RUN npm run build -- --configuration production

# ---------- Stage 2: servire statică, non-root ----------
FROM nginxinc/nginx-unprivileged:1.30.6-alpine3.24

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY nginx/security-headers.conf /etc/nginx/snippets/security-headers.conf
COPY --from=build /app/dist/otnielcodes-landing/browser /usr/share/nginx/html

# Imaginea rulează deja ca utilizatorul "nginx" (uid 101); îl declarăm explicit.
USER 101
EXPOSE 8080
