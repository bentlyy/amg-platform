FROM node:20-bookworm-slim

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ \
  && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
COPY packages ./packages
COPY apps ./apps

RUN npm ci \
  && npm cache clean --force \
  && rm -rf /root/.npm/_logs
RUN npm run build

ENV NODE_ENV=production
EXPOSE 3000

RUN mkdir -p /app/data/core && chown -R node:node /app/data

USER node
CMD ["npm", "run", "start", "-w", "@amg/landing"]
