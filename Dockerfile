# ── Stage 1: Base image ──────────────────────────────────────────
FROM node:20-alpine

# ── Stage 2: Set working directory ──────────────────────────────
WORKDIR /app

# ── Stage 3: Copy dependency files ──────────────────────────────
COPY package*.json ./

# ── Stage 4: Install dependencies ───────────────────────────────
RUN npm install --production

# ── Stage 5: Copy source code ───────────────────────────────────
COPY src/ ./src/

# ── Stage 6: Expose port ─────────────────────────────────────────
EXPOSE 3000

# ── Stage 7: Start command ───────────────────────────────────────
CMD ["node", "src/index.js"]