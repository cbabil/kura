FROM node:20-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --production

FROM node:20-slim
RUN groupadd -r stratura && useradd -r -g stratura stratura
WORKDIR /opt/stratura-supervisor
COPY --from=builder /app/node_modules ./node_modules
COPY src/ ./src/
COPY package.json ./
USER stratura
EXPOSE 48484
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:48484/v1/health',(r)=>{process.exit(r.statusCode===200?0:1)}).on('error',()=>process.exit(1))"
CMD ["node", "src/index.js"]
