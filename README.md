# 🦞 Instabet Agent

Autonomous prediction market betting agent combining:
- **[OpenClaw](https://github.com/openclaw/openclaw)** — AI agent gateway with skills + cron scheduler
- **[0G Compute](https://docs.0g.ai/developer-hub/building-on-0g/compute-network/inference)** — Decentralised, verifiable LLM inference (on-chain payments)
- **[Instabet](https://github.com/instabetxyz/backend)** — Live-stream prediction markets

---

## How it works

```
Every N minutes (cron):
  1. Fetch open markets from Instabet API
  2. For each unbet market → query 0G Compute LLM (Qwen 2.5 7B)
  3. LLM reasons about EV: confidence vs implied odds
  4. If confidence ≥ threshold AND EV > 5% → place bet via API
  5. Persist bet state → wait for next cycle
```

## Architecture

```
docker compose up
│
├── zg-broker  (node:24-alpine)
│   ├── setup.mjs (SDK)  → funds ledger + provider sub-account non-interactively
│   └── 0g-compute-cli inference serve --port 3001
│       └── OpenAI-compatible proxy at :3001/v1/proxy
│
└── instabet-agent  (node:24-alpine + openclaw)
    ├── OpenClaw gateway :18789
    ├── instabet-trader skill (SKILL.md)
    └── cron job → isolated agent turn every N minutes
        ├── bash: GET /markets
        ├── LLM: reason YES/NO per market  ← goes through zg-broker
        ├── bash: POST /markets/:id/bet
        └── write: update bet_markets.json
```

---

## Quick start

```bash
# 1. Clone
git clone https://github.com/yourorg/instabet-agent
cd instabet-agent

# 2. Configure
cp .env.example .env
# Edit .env — fill in the 4 required values:
#   ZG_WALLET_PRIVATE_KEY, ZG_PROVIDER_ADDRESS, INSTABET_API_KEY, INSTABET_BASE_URL

# 3. Start
docker compose up --build

# 4. Watch
docker compose logs -f
```

### First run

On the first boot the `zg-broker` will:
1. Connect to 0G testnet
2. Deposit 0G tokens into your ledger account (if balance is low)
3. Transfer funds to the provider sub-account
4. Start the local inference proxy on `:3001`

This takes ~60–90 seconds. `instabet-agent` waits for the broker health check before starting.

---

## Configuration (`.env`)

| Variable | Required | Default | Description |
|---|---|---|---|
| `ZG_WALLET_PRIVATE_KEY` | ✅ | — | EVM wallet private key (needs 0G tokens) |
| `ZG_PROVIDER_ADDRESS` | ✅ | — | 0G Compute provider to use for inference |
| `ZG_NETWORK` | | `testnet` | `testnet` or `mainnet` |
| `ZG_DEPOSIT_AMOUNT` | | `5` | 0G to deposit on first run |
| `ZG_PROVIDER_FUND` | | `2` | 0G to transfer to provider sub-account |
| `INSTABET_BASE_URL` | ✅ | — | Instabet backend base URL |
| `INSTABET_API_KEY` | ✅ | — | Instabet API key |
| `BET_AMOUNT` | | `0.01` | Amount to bet per market |
| `CONFIDENCE_THRESHOLD` | | `0.65` | Min LLM confidence (0–1) to bet |
| `CRON_INTERVAL` | | `*/5 * * * *` | Cron schedule for trading loop |
| `OPENCLAW_PASSWORD` | | `change-me` | OpenClaw gateway UI password |

**Get testnet 0G tokens:** https://faucet.0g.ai

**Testnet provider address** (Qwen 2.5 7B): check https://compute-marketplace.0g.ai/inference

---

## Useful commands

```bash
# Live logs from both containers
docker compose logs -f

# Just the agent logs
docker compose logs -f instabet-agent

# Trigger a manual trading cycle NOW
docker compose exec instabet-agent openclaw cron list
docker compose exec instabet-agent openclaw cron run <jobId>

# Check cron run history
docker compose exec instabet-agent openclaw cron runs --id <jobId>

# Check 0G account balance
docker compose exec zg-broker node -e "
  import('@0glabs/0g-serving-broker').then(async ({createZGComputeNetworkBroker}) => {
    const {ethers} = await import('ethers');
    const p = new ethers.JsonRpcProvider('https://evmrpc-testnet.0g.ai');
    const w = new ethers.Wallet(process.env.PRIVATE_KEY, p);
    const b = await createZGComputeNetworkBroker(w);
    const l = await b.ledger.getLedger();
    console.log('Balance:', ethers.formatEther(l.totalBalance), '0G');
  });
"

# View bet history
docker compose exec instabet-agent cat /root/.openclaw/workspace/data/bet_markets.json

# Wipe bet history (start fresh)
docker compose exec instabet-agent sh -c "echo '{\"bet\":[]}' > /root/.openclaw/workspace/data/bet_markets.json"

# Stop everything
docker compose down

# Stop and wipe all persisted data (WARNING: resets everything)
docker compose down -v
```

---

## Switching models

To use a better model on mainnet (e.g. DeepSeek):

1. Set `ZG_NETWORK=mainnet` in `.env`
2. Update `ZG_PROVIDER_ADDRESS` to the DeepSeek mainnet provider
3. In `workspace/openclaw.json`, change the model id:
   ```json
   "primary": "0g/deepseek-chat-v3-0324"
   ```
   and in `models[0].id`:
   ```json
   "id": "deepseek-chat-v3-0324"
   ```

Available mainnet models: `deepseek-chat-v3-0324`, `gpt-oss-120b`, `GLM-5-FP8`

---

## File structure

```
instabet-agent/
├── docker-compose.yml                    ← orchestrates zg-broker + instabet-agent
├── Dockerfile                            ← openclaw agent image
├── entrypoint.sh                         ← startup: expand config, start gateway, register cron
├── .env.example                          ← environment variable template
├── zg-broker/
│   ├── Dockerfile                        ← broker image
│   ├── package.json
│   └── setup.mjs                         ← SDK-based non-interactive setup + proxy start
└── workspace/
    ├── openclaw.json                     ← OpenClaw config (model, cron, skills)
    ├── skills/
    │   └── instabet-trader/
    │       └── SKILL.md                  ← agent betting behavior prompt
    └── data/
        └── bet_markets.json              ← persisted bet state (auto-created)
```
