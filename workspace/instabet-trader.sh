#!/bin/bash

STATE_FILE="/root/.openclaw/workspace/data/bet_markets.json"
mkdir -p "$(dirname "$STATE_FILE")"

# Step 1: Load already-bet markets
ALREADY_BET=$(cat "$STATE_FILE" 2>/dev/null || echo '{"bet":[]}')
BET_IDS=$(echo "$ALREADY_BET" | jq -r '.bet[]')

# Step 2: Fetch open markets
MARKETS=$(curl -s \
  -H "x-api-key: ${INSTABET_API_KEY}" \
  "${INSTABET_BASE_URL}/markets?status=OPEN")

if [ -z "$MARKETS" ] || echo "$MARKETS" | grep -q '"error"'; then
  echo "ERROR: Failed to fetch markets"
  exit 1
fi

# Step 3: Filter out already-bet markets
UNBET_MARKETS=$(echo "$MARKETS" | jq --argjson ids "$(echo "$ALREADY_BET" | jq '.bet')" '
  [.[] | select(.id as $id | $ids | index($id) | not)]
')

COUNT=$(echo "$UNBET_MARKETS" | jq 'length')
if [ "$COUNT" -eq 0 ]; then
  echo "No new markets to analyze."
  exit 0
fi

# Step 4: Ask 0G LLM to reason — plain text in, plain text JSON out
PROMPT="Here are the open prediction markets to analyze:

$(echo "$UNBET_MARKETS" | jq '.')

Confidence threshold: ${CONFIDENCE_THRESHOLD}
Bet amount: ${BET_AMOUNT}

Analyze each market and return your decisions as a JSON array only."

RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${ZG_API_KEY}" \
  "${ZG_SERVICE_URL}/v1/proxy/chat/completions" \
  -d "$(jq -n \
    --arg prompt "$PROMPT" \
    '{
      model: "qwen/qwen-2.5-7b-instruct",
      max_tokens: 1024,
      messages: [{"role": "user", "content": $prompt}]
    }'
  )")

# Step 5: Parse LLM decisions
DECISIONS=$(echo "$RESPONSE" | jq -r '.choices[0].message.content' | \
  sed 's/```json//g' | sed 's/```//g' | tr -d '\n' | \
  python3 -c "import sys,json; print(json.dumps(json.loads(sys.stdin.read())))" 2>/dev/null)

if [ -z "$DECISIONS" ]; then
  echo "ERROR: Could not parse LLM response"
  echo "$RESPONSE"
  exit 1
fi

# Step 6: Place bets
NEW_BET_IDS=()
echo "=== Instabet Trading Cycle ==="
echo "Markets analyzed: $COUNT"

while IFS= read -r decision; do
  ID=$(echo "$decision" | jq -r '.id')
  SIDE=$(echo "$decision" | jq -r '.decision')
  CONFIDENCE=$(echo "$decision" | jq -r '.confidence')
  EV=$(echo "$decision" | jq -r '.ev')
  REASON=$(echo "$decision" | jq -r '.reasoning')

  if [ "$SIDE" = "SKIP" ]; then
    echo "  SKIP $ID — $REASON"
    NEW_BET_IDS+=("$ID")
    continue
  fi

  BET_RESULT=$(curl -s -X POST \
    -H "x-api-key: ${INSTABET_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"side\": \"$SIDE\", \"amount\": ${BET_AMOUNT}}" \
    "${INSTABET_BASE_URL}/markets/${ID}/bet")

  if echo "$BET_RESULT" | grep -q '"success":true\|"id":'; then
    echo "  ✓ $SIDE on market $ID (confidence: $CONFIDENCE, EV: $EV)"
  else
    echo "  ✗ ERROR on $ID: $BET_RESULT"
  fi

  NEW_BET_IDS+=("$ID")
done < <(echo "$DECISIONS" | jq -c '.[]')

# Step 7: Update state file
ALL_IDS=$(echo "$ALREADY_BET" | jq \
  --argjson new "$(printf '%s\n' "${NEW_BET_IDS[@]}" | jq -R . | jq -s .)" \
  '.bet + $new | unique')
echo "{\"bet\": $ALL_IDS}" > "$STATE_FILE"