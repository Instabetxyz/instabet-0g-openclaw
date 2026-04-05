#!/usr/bin/env node
/**
 * 0G Compute Broker Setup + Serve
 *
 * Uses the @0glabs/0g-serving-broker SDK directly — fully non-interactive.
 * Steps:
 *   1. Connect wallet to 0G network
 *   2. Create ledger account if needed and deposit funds
 *   3. Transfer funds to provider sub-account
 *   4. Start the OpenAI-compatible inference proxy via CLI
 */

import { ethers } from "ethers";
import { createZGComputeNetworkBroker } from "@0glabs/0g-serving-broker";
import { execSync, spawn } from "child_process";

// ── Config from environment ──────────────────────────────────────────────────
const {
  PRIVATE_KEY,
  ZG_PROVIDER_ADDRESS,
  ZG_NETWORK = "testnet",
  ZG_DEPOSIT_AMOUNT = "3",
  ZG_PROVIDER_FUND = "1",
  PROXY_PORT = "3001",
} = process.env;

if (!PRIVATE_KEY) {
  console.error("❌ PRIVATE_KEY is required");
  process.exit(1);
}
if (!ZG_PROVIDER_ADDRESS) {
  console.error("❌ ZG_PROVIDER_ADDRESS is required");
  process.exit(1);
}

// ── RPC endpoints ─────────────────────────────────────────────────────────────
const RPC_URLS = {
  mainnet: "https://evmrpc.0g.ai",
  testnet: "https://evmrpc-testnet.0g.ai",
};

const rpcUrl = RPC_URLS[ZG_NETWORK];
if (!rpcUrl) {
  console.error(`❌ Unknown ZG_NETWORK: "${ZG_NETWORK}". Use "testnet" or "mainnet"`);
  process.exit(1);
}

const depositAmount = parseFloat(ZG_DEPOSIT_AMOUNT);
const providerFund = parseFloat(ZG_PROVIDER_FUND);
const minSubAccountBalance = 1.0; // 0G minimum required by provider

async function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function main() {
  console.log(`\n🔗 Connecting to 0G ${ZG_NETWORK} (${rpcUrl})...`);

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  console.log(`   Wallet address: ${wallet.address}`);

  // Check wallet balance for gas
  const walletBalance = await provider.getBalance(wallet.address);
  console.log(`   Wallet balance: ${ethers.formatEther(walletBalance)} 0G`);

  if (walletBalance === 0n) {
    console.warn(
      `⚠️  Wallet has 0 balance. Get testnet tokens at https://faucet.0g.ai`
    );
  }

  console.log("\n🏗️  Initializing 0G Compute Network broker...");
  const broker = await createZGComputeNetworkBroker(wallet);

  // ── Step 1: Check / create ledger account ──────────────────────────────────
  let ledger = null;
  try {
    ledger = await broker.ledger.getLedger();
    const total = parseFloat(ethers.formatEther(ledger.totalBalance));
    const available = parseFloat(ethers.formatEther(ledger.availableBalance));
    console.log(`✅ Ledger account exists`);
    console.log(`   Total balance:     ${total.toFixed(4)} 0G`);
    console.log(`   Available balance: ${available.toFixed(4)} 0G`);
  } catch (e) {
    // No ledger yet — need to deposit to create it
    console.log(`   No ledger account found — creating with ${depositAmount} 0G deposit...`);
  }

  // ── Step 2: Deposit if ledger is empty or doesn't exist ───────────────────
  const currentTotal = ledger
    ? parseFloat(ethers.formatEther(ledger.totalBalance))
    : 0;

  if (currentTotal < depositAmount * 0.5) {
    console.log(`\n💰 Depositing ${depositAmount} 0G into ledger...`);
    try {
      await broker.ledger.depositFund(depositAmount);
      console.log(`✅ Deposited ${depositAmount} 0G`);
      // Wait for tx to propagate
      await sleep(3000);
    } catch (e) {
      if (e.message?.includes("already exists") || e.message?.includes("already created")) {
        console.log(`   Ledger already exists, skipping deposit`);
      } else {
        console.warn(`⚠️  Deposit failed: ${e.message}`);
        console.warn(`   Continuing — there may already be sufficient funds`);
      }
    }
  } else {
    console.log(`✅ Ledger already has sufficient balance (${currentTotal.toFixed(4)} 0G)`);
  }

  // ── Step 3: Check provider sub-account and fund if needed ─────────────────
  console.log(`\n🔄 Checking provider sub-account (${ZG_PROVIDER_ADDRESS})...`);

  let subBalance = 0;
  try {
    const [subAccount] = await broker.inference.getAccountWithDetail(ZG_PROVIDER_ADDRESS);
    subBalance = parseFloat(ethers.formatEther(subAccount.balance));
    console.log(`   Sub-account balance: ${subBalance.toFixed(4)} 0G`);
  } catch (e) {
    console.log(`   No sub-account yet — will create on transfer`);
  }

  if (subBalance < minSubAccountBalance) {
    console.log(`   Transferring ${providerFund} 0G to provider sub-account...`);
    try {
      const fundWei = ethers.parseEther(String(providerFund));
      await broker.ledger.transferFund(ZG_PROVIDER_ADDRESS, "inference", fundWei);
      console.log(`✅ Transferred ${providerFund} 0G to provider`);
      await sleep(3000);
    } catch (e) {
      console.warn(`⚠️  Transfer failed: ${e.message}`);
      console.warn(`   If sub-account already has enough funds this is fine`);
    }
  } else {
    console.log(`✅ Provider sub-account already funded (${subBalance.toFixed(4)} 0G)`);
  }

  // ── Step 4: Write the CLI config file so 0g-compute-cli works non-interactively ──
  // The CLI stores network config in ~/.0g-compute-cli/config.json
  // We pre-write it so `inference serve` doesn't prompt for network selection
  const configDir = `${process.env.HOME || "/root"}/.0g-compute-cli`;
  const configPath = `${configDir}/config.json`;

  const networkConfigs = {
    testnet: {
      rpc: "https://evmrpc-testnet.0g.ai",
      ledgerCA: "0x0D2A3D43ad1f89aE0B6c90Ba47D85ac2e8d38a37",
      inferenceCA: "0x357D517E3B87E1E3E05B851F63de1Af9B90d61b0",
    },
    mainnet: {
      rpc: "https://evmrpc.0g.ai",
      ledgerCA: "0x6B68B5Db9C83f27bFD1a32aCbA1c3aDf38f0f5C3",
      inferenceCA: "0x49B8ad065E2E41f6E1A33C7C8E1B6c28B99C3db5",
    },
  };

  const netCfg = networkConfigs[ZG_NETWORK];

  const cliConfig = {
    network: {
      rpc: netCfg.rpc,
      contracts: {
        ledger: netCfg.ledgerCA,
        inference: netCfg.inferenceCA,
      },
    },
    privateKey: PRIVATE_KEY,
  };

  try {
    execSync(`mkdir -p ${configDir}`);
    const fs = await import("fs");
    fs.writeFileSync(configPath, JSON.stringify(cliConfig, null, 2));
    console.log(`\n✅ CLI config written to ${configPath}`);
  } catch (e) {
    console.warn(`⚠️  Could not write CLI config: ${e.message}`);
  }

  // ── Step 5: Start the inference proxy ─────────────────────────────────────
  console.log(`\n🚀 Starting 0G inference proxy on port ${PROXY_PORT}...`);
  console.log(`   Provider: ${ZG_PROVIDER_ADDRESS}`);
  console.log(`   Endpoint will be: http://localhost:${PROXY_PORT}/v1/proxy`);
  console.log("");

  const serve = spawn(
    "0g-compute-cli",
    ["inference", "serve", "--provider", ZG_PROVIDER_ADDRESS, "--port", PROXY_PORT],
    {
      stdio: "inherit",
      env: {
        ...process.env,
        // Pass private key so CLI can sign requests
        PRIVATE_KEY,
      },
    }
  );

  serve.on("error", (err) => {
    console.error("❌ Failed to start 0g-compute-cli:", err.message);
    process.exit(1);
  });

  serve.on("exit", (code) => {
    console.log(`0g-compute-cli exited with code ${code}`);
    process.exit(code ?? 1);
  });

  // Forward signals
  process.on("SIGTERM", () => serve.kill("SIGTERM"));
  process.on("SIGINT", () => serve.kill("SIGINT"));
}

main().catch((err) => {
  console.error("❌ Fatal error:", err);
  process.exit(1);
});
