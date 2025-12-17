FROM node:20-alpine

WORKDIR /repo/mcp-roadmap-server

COPY mcp-roadmap-server/package.json mcp-roadmap-server/package-lock.json ./
RUN npm ci --include=dev

COPY mcp-roadmap-server/tsconfig.json ./
COPY mcp-roadmap-server/src ./src
COPY mcp-roadmap-server/scripts ./scripts

# Schema generation reads OpenAPI specs from appPackage/
COPY appPackage /repo/appPackage

RUN npm run build && npm prune --omit=dev

EXPOSE 8081
ENV PORT=8081

CMD ["node", "dist/server.js"]
