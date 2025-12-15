FROM node:20-alpine

WORKDIR /app

COPY package.json ./

RUN npm install --omit=dev

COPY src ./src
COPY tsconfig.json ./

RUN npm install --include=dev && npm run build && npm prune --omit=dev

ENV PORT=8080
EXPOSE 8080

CMD ["node", "dist/server.js"]
