FROM node:22-alpine

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY src ./src
RUN mkdir -p /var/lib/lumanest && chown -R node:node /var/lib/lumanest

USER node
EXPOSE 8787 8788
CMD ["node", "src/server.mjs"]
