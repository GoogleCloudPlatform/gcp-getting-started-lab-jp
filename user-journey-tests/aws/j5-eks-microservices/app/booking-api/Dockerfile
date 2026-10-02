# booking-api — Node 22 slim runtime (base verified 2026-07).
# npm ci against the committed lockfile for reproducible installs; runs as
# the image's non-root "node" user.
FROM node:22-slim
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY *.mjs ./
ENV PORT=8080
EXPOSE 8080
USER node
CMD ["node", "server.mjs"]
