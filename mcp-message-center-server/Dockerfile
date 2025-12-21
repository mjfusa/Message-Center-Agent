FROM node:20-alpine

WORKDIR /repo/mcp-message-center-server

COPY mcp-message-center-server/package.json mcp-message-center-server/package-lock.json ./
RUN npm ci --include=dev

COPY mcp-message-center-server/tsconfig.json ./
COPY mcp-message-center-server/src ./src
COPY mcp-message-center-server/scripts ./scripts

# Vendored OpenAPI spec used during build-time schema generation.
COPY mcp-message-center-server/openapi ./openapi

RUN npm run build && npm prune --omit=dev

ENV PORT=8080
EXPOSE 8080

CMD ["node", "dist/server.js"]
