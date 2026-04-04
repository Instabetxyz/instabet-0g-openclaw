#!/bin/sh
set -e

echo "🦞 Instabet Agent — starting up..."

# ── Validate required env vars ───────────────────────────────────────────────
_missing=""
for var in ZG_SERVICE_URL ZG_API_KEY INSTABET_API_KEY INSTABET_BASE_URL; do
  eval val=\$$var
  if [ -z "$val" ]; then
    _missing="$_missing $var"
  fi
done

if [ -n "$_missing" ]; then
  echo "❌ Missing required environment variables:$_missing"
  echo "   Copy .env.example to .env and fill in all values."
  exit 1
fi

# ── Defaults ──────────────────────────────────────────────────────────────────
BET_AMOUNT="${BET_AMOUNT:-0.01}"
CONFIDENCE_THRESHOLD="${CONFIDENCE_THRESHOLD:-0.65}"
CRON_INTERVAL="${CRON_INTERVAL:-*/5 * * * *}"
OPENCLAW_PASSWORD="${OPENCLAW_PASSWORD:-instabet-agent-password}"

export BET_AMOUNT CONFIDENCE_THRESHOLD OPENCLAW_PASSWORD

echo "📋 Configuration:"
echo "   INSTABET_BASE_URL    = $INSTABET_BASE_URL"
echo "   ZG_SERVICE_URL       = $ZG_SERVICE_URL"
echo "   BET_AMOUNT           = $BET_AMOUNT"
echo "   CONFIDENCE_THRESHOLD = $CONFIDENCE_THRESHOLD"
echo "   CRON_INTERVAL        = $CRON_INTERVAL"

# ── Workspace & data directories ──────────────────────────────────────────────
mkdir -p /root/.openclaw/workspace/data
mkdir -p /root/.openclaw/workspace/skills
mkdir -p /root/.openclaw/cron

# ── Copy workspace into openclaw home (skills + data state) ──────────────────
# Sync skills always (they may have been updated in the image)
cp -r /app/workspace/skills/. /root/.openclaw/workspace/skills/

# Only copy openclaw.json if it doesn't already exist (preserve any runtime edits)
if [ ! -f /root/.openclaw/openclaw.json ]; then
  envsubst < /app/workspace/openclaw.json > /root/.openclaw/openclaw.json
  echo "✅ openclaw.json written"
else
  echo "✅ openclaw.json already exists — preserving (delete volume to reset)"
  # Still re-expand env vars in case credentials changed
  envsubst < /app/workspace/openclaw.json > /root/.openclaw/openclaw.json
fi

# ── Ensure bet state file exists ─────────────────────────────────────────────
if [ ! -f /root/.openclaw/workspace/data/bet_markets.json ]; then
  echo '{"bet":[]}' > /root/.openclaw/workspace/data/bet_markets.json
  echo "✅ Initialized bet_markets.json"
fi

# ── Start OpenClaw gateway in background ──────────────────────────────────────
echo ""
echo "🚀 Starting OpenClaw gateway on port 18789..."
openclaw gateway --port 18789 &
GATEWAY_PID=$!

# ── Wait for gateway HTTP to be ready ─────────────────────────────────────────
echo "⏳ Waiting for gateway to be ready..."
MAX_WAIT=60
COUNT=0
until curl -sf http://localhost:18789/health > /dev/null 2>&1 || [ $COUNT -ge $MAX_WAIT ]; do
  sleep 1
  COUNT=$((COUNT + 1))
  printf "."
done
echo ""

if [ $COUNT -ge $MAX_WAIT ]; then
  echo "⚠️  Gateway health check timed out after ${MAX_WAIT}s — attempting cron registration anyway"
else
  echo "✅ Gateway is ready (${COUNT}s)"
fi

sleep 1

# ── Register trading cron job (idempotent) ────────────────────────────────────
echo "⏰ Registering trading cron job..."
echo "   Schedule: $CRON_INTERVAL"

# Remove existing job with this name if present
EXISTING_ID=$(openclaw cron list 2>/dev/null | grep "instabet-trader" | awk 'NR==1{print $1}' || true)
if [ -n "$EXISTING_ID" ]; then
  echo "   Removing stale cron job: $EXISTING_ID"
  openclaw cron remove "$EXISTING_ID" 2>/dev/null || true
fi

# Add the trading cron job as an isolated session
openclaw cron add \
  --name "instabet-trader" \
  --cron "$CRON_INTERVAL" \
  --session isolated \
  --message "Run the Instabet trading cycle. You are an autonomous prediction market agent. Follow the instabet_trader skill: fetch open markets from the Instabet API, reason about each market using the EV framework, and place bets where you have sufficient conviction. Be thorough but concise." \
  --tools "bash,read,write"

echo "✅ Cron job registered"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 Instabet Agent is running!"
echo "   Trading loop every:  $CRON_INTERVAL"
echo "   Bet amount:          $BET_AMOUNT per market"
echo "   Min confidence:      $(awk "BEGIN{printf \"%.0f\", $CONFIDENCE_THRESHOLD * 100}")%"
echo "   Gateway UI:          http://localhost:18789"
echo ""
echo "💡 Commands:"
echo "   docker compose exec instabet-agent openclaw cron list"
echo "   docker compose exec instabet-agent openclaw cron run <jobId>"
echo "   docker compose exec instabet-agent openclaw logs --follow"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Keep container alive (gateway runs in background) ─────────────────────────
wait $GATEWAY_PID
