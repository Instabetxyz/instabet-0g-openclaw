# AGENTS.md — Instabet OpenClaw Agent

## Overview

This is a Docker-based autonomous trading agent that:
1. Runs a 0G Compute broker for LLM inference
2. Uses OpenClaw gateway with an `instabet-trader` skill
3. Fetches prediction markets from Instabet API and places bets based on expected value

## Project Structure

```
/zg-broker/           # 0G Compute broker service
  setup.mjs           # Node.js script to fund wallet + start inference proxy
  Dockerfile
/workspace/
  openclaw.json       # OpenClaw gateway configuration
  skills/instabet-trader/
    SKILL.md          # Trading skill definition
/entrypoint.sh        # Container startup script
Dockerfile            # Main agent container
docker-compose.yml    # Service orchestration
.env.example          # Environment template
```

## Build, Run & Test Commands

### Quick Start

```bash
# 1. Copy and configure environment
cp .env.example .env
# Edit .env with your keys

# 2. Build and start all services
docker compose up --build

# 3. View logs
docker compose logs -f
```

### Running Single Test (Manual Trading Cycle)

```bash
# Execute the trading skill manually
docker compose exec instabet-agent openclaw cron run <jobId>

# List cron jobs to find the job ID
docker compose exec instabet-agent openclaw cron list

# View agent logs
docker compose logs instabet-agent
```

### OpenClaw CLI Commands

```bash
# List cron jobs
openclaw cron list

# Run a specific cron job manually
openclaw cron run <jobId>

# View gateway logs
openclaw logs --follow

# Access gateway web UI
# http://localhost:18789 (password in OPENCLAW_PASSWORD)
```

### Development Commands

```bash
# Rebuild specific service
docker compose build instabet-agent
docker compose build zg-broker

# Restart a service
docker compose restart instabet-agent

# Access container shell
docker compose exec instabet-agent sh
```

## Code Style Guidelines

### JavaScript/Node.js

- **Language**: Node.js with ES modules (`import`/`export`)
- **Formatting**: 2-space indentation
- **Comments**: Use section headers with `// ── Description ──`
- **Async**: Use `async`/`await` over raw promises; use `try`/`catch` for error handling
- **Logging**: Use emoji prefixes (e.g., `console.log("✅ ...")`)

### Shell Scripting (entrypoint.sh)

- **Shell**: `/bin/sh` (POSIX-compatible)
- **Error handling**: Use `set -e` for fail-fast
- **Variables**: Use `${VAR:-default}` for defaults
- **Conditionals**: Use `[ ]` test syntax; quote variables

### Configuration Files

- **JSON**: Use 2-space indentation, trailing commas allowed
- **YAML**: Use 2-space indentation
- **Environment**: Use UPPER_SNAKE_CASE; document all required vars in `.env.example`

### Docker

- **Base image**: `node:24-alpine`
- **Workdir**: Use `/app` for application code
- **Volumes**: Define persistent volumes for state

### Error Handling

- Validate required environment variables at startup
- Log errors with context before exiting
- Graceful degradation: if optional service fails, warn and continue

### Imports & Dependencies

```javascript
// Node.js ES modules
import { ethers } from "ethers";
import { createZGComputeNetworkBroker } from "@0glabs/0g-serving-broker";
import { execSync, spawn } from "child_process";
```

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Files | kebab-case | `setup.mjs`, `entrypoint.sh` |
| Env vars | UPPER_SNAKE_CASE | `ZG_SERVICE_URL` |
| Skills | kebab-case | `instabet-trader` |
| Cron jobs | lowercase | `instabet-trader` |

### Environment Variables

Required for `instabet-agent`:
- `INSTABET_BASE_URL` — Instabet API URL
- `INSTABET_API_KEY` — API authentication
- `ZG_SERVICE_URL` — 0G proxy URL (http://zg-broker:3001)
- `ZG_API_KEY` — 0G proxy API key

Optional:
- `BET_AMOUNT` — Default 0.01
- `CONFIDENCE_THRESHOLD` — Default 0.65
- `CRON_INTERVAL` — Default `*/5 * * * *`
- `OPENCLAW_PASSWORD` — Gateway password

Required for `zg-broker`:
- `PRIVATE_KEY` — Wallet private key
- `ZG_PROVIDER_ADDRESS` — 0G provider address
- `ZG_NETWORK` — testnet or mainnet

## Testing & Debugging

```bash
# Check health
curl http://localhost:18789/health
curl http://localhost:3001/v1/proxy/models

# View broker logs
docker compose logs zg-broker

# Check environment in container
docker compose exec instabet-agent env

# Verify bet state
docker compose exec instabet-agent cat /root/.openclaw/workspace/data/bet_markets.json
```

## Key Files Reference

| File | Purpose |
|------|---------|
| `workspace/skills/instabet-trader/SKILL.md` | Trading skill definition |
| `workspace/openclaw.json` | OpenClaw configuration |
| `entrypoint.sh` | Agent startup & cron registration |
| `zg-broker/setup.mjs` | Broker wallet funding & proxy start |
