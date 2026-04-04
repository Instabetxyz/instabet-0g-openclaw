# ── Instabet Agent — OpenClaw + 0G Compute ──────────────────────────────────
# Runs the OpenClaw gateway with the instabet-trader skill.
# The 0G broker proxy runs as a sidecar (see docker-compose.yml).

FROM node:24-alpine

# ── System deps ───────────────────────────────────────────────────────────────
RUN apk add --no-cache \
    curl \
    bash \
    gettext \
    jq

# ── Install OpenClaw globally ─────────────────────────────────────────────────
RUN npm install -g openclaw@latest

# ── App directory ─────────────────────────────────────────────────────────────
WORKDIR /app

# Copy workspace (config + skills) into the image
COPY workspace/ ./workspace/

# Copy entrypoint
COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

# ── Volumes ───────────────────────────────────────────────────────────────────
# Persist cron jobs + bet state + openclaw auth across container restarts
VOLUME ["/root/.openclaw"]

# ── Ports ─────────────────────────────────────────────────────────────────────
EXPOSE 18789

# ── Entrypoint ────────────────────────────────────────────────────────────────
ENTRYPOINT ["./entrypoint.sh"]