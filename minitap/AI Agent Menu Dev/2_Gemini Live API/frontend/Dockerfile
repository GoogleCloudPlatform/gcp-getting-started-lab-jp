FROM node:22-alpine AS base

# Builder image
FROM base AS builder

RUN apk add --no-cache libc6-compat
WORKDIR /build
COPY . .
RUN npm ci
RUN npm run build
RUN touch .env

# Production image
FROM base AS runner

WORKDIR /app
ENV NODE_ENV production

RUN addgroup --system --gid 1001 nodejs

RUN adduser --system --uid 1001 nextjs

COPY --from=builder /build/public ./public

RUN mkdir .next
RUN chown nextjs:nodejs .next

COPY --from=builder --chown=nextjs:nodejs /build/.env* ./
COPY --from=builder --chown=nextjs:nodejs /build/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /build/.next/static ./.next/static

USER nextjs

# PORT is overwritten in Cloud Run
ENV PORT 3000
ENV HOSTNAME "0.0.0.0"

CMD ["node", "server.js"]
