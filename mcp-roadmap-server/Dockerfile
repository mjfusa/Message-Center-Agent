FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci --omit=dev

COPY tsconfig.json ./
COPY src ./src

RUN npm run build

EXPOSE 8081
ENV PORT=8081

CMD ["npm", "run", "start"]
