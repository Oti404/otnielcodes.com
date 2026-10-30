# Dockerfile (rădăcina repo-ului proiectului): build Angular, servire cu nginx non-root pe 8080.
FROM node:22.23.4-alpine3.24 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npx ng build --configuration production \
 && mkdir /out && cp -r dist/*/browser/. /out/

FROM nginxinc/nginx-unprivileged:1.30.6-alpine3.24
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /out /usr/share/nginx/html
USER 101
EXPOSE 8080
