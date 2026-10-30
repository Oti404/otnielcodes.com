# server/Dockerfile în repo-ul proiectului: API Node pe portul 3000, non-root.
# Cerințe pentru backend: ascultă pe process.env.PORT (3000), are GET /api/health
# (200 când merge, inclusiv conexiunea la DB) și scrie fișierele urcate în /app/uploads.
# Pune node_modules și .env în server/.dockerignore.
FROM node:22.23.4-bookworm-slim

ENV NODE_ENV=production \
    PORT=3000 \
    UPLOAD_DIR=/app/uploads \
    NODE_OPTIONS=--max-old-space-size=128

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
# Cu Prisma: decomentează (și instalează openssl în imagine dacă îl cere Prisma).
# COPY prisma ./prisma
# RUN npx prisma generate
COPY . .
RUN mkdir -p /app/uploads && chown -R node:node /app

USER node
EXPOSE 3000
CMD ["node", "index.js"]
