#!/usr/bin/env bun

import { execSync, spawnSync } from "child_process";
import { existsSync } from "fs";
import * as readline from "readline";

const SKILL_DIR = import.meta.dir;
const KEYMANAGER_MASTER_KEY = "1479863a-96d5-4a9d-9824-1996c21a2d36";
const KEYMANAGER_PATH = "/Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts";

const PROVIDERS = {
  openai: {
    name: "OpenAI",
    service: "openai",
    envVar: "OPENAI_API_KEY",
    keyPrefix: "sk-",
    getKeyUrl: "https://platform.openai.com/api-keys",
  },
  anthropic: {
    name: "Anthropic",
    service: "anthropic",
    envVar: "ANTHROPIC_API_KEY",
    keyPrefix: "sk-ant-",
    getKeyUrl: "https://console.anthropic.com/settings/keys",
  },
  google: {
    name: "Google (Gemini)",
    service: "gemini",
    envVar: "GEMINI_API_KEY",
    keyPrefix: "AI",
    getKeyUrl: "https://aistudio.google.com/app/apikey",
  },
};

// ============================================================================
// Helpers
// ============================================================================

function log(msg: string) {
  console.log(msg);
}

function success(msg: string) {
  console.log(`✅ ${msg}`);
}

function warn(msg: string) {
  console.log(`⚠️  ${msg}`);
}

function error(msg: string) {
  console.log(`❌ ${msg}`);
}

function info(msg: string) {
  console.log(`ℹ️  ${msg}`);
}

function getKeyFromManager(service: string): { key: string | null; description: string } {
  try {
    // Use find --service to get keys by service name (handles composite IDs like gemini_games)
    const result = execSync(
      `export KEYMANAGER_MASTER_KEY="${KEYMANAGER_MASTER_KEY}" && ${KEYMANAGER_PATH} find --service ${service}`,
      { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }
    );
    const keys = JSON.parse(result);
    if (!keys || keys.length === 0) return { key: null, description: "" };

    // Get the first matching key's ID, then fetch with --show-key
    const keyId = keys[0].id;
    const keyResult = execSync(
      `export KEYMANAGER_MASTER_KEY="${KEYMANAGER_MASTER_KEY}" && ${KEYMANAGER_PATH} get ${keyId} --show-key --format json`,
      { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }
    );
    const data = JSON.parse(keyResult);
    return { key: data.key || null, description: data.description || "" };
  } catch {
    return { key: null, description: "" };
  }
}

function addKeyToManager(service: string, key: string, description: string): boolean {
  try {
    execSync(
      `export KEYMANAGER_MASTER_KEY="${KEYMANAGER_MASTER_KEY}" && ${KEYMANAGER_PATH} add --service ${service} --key "${key}" --global --env production --description "${description}"`,
      { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }
    );
    return true;
  } catch {
    return false;
  }
}

function deleteKeyFromManager(service: string): boolean {
  try {
    execSync(
      `export KEYMANAGER_MASTER_KEY="${KEYMANAGER_MASTER_KEY}" && ${KEYMANAGER_PATH} delete ${service} --force`,
      { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }
    );
    return true;
  } catch {
    return false;
  }
}

async function prompt(question: string): Promise<string> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

async function promptYesNo(question: string, defaultYes = true): Promise<boolean> {
  const hint = defaultYes ? "[Y/n]" : "[y/N]";
  const answer = await prompt(`${question} ${hint}: `);
  if (answer === "") return defaultYes;
  return answer.toLowerCase().startsWith("y");
}

// ============================================================================
// Setup Steps
// ============================================================================

async function checkDependencies(): Promise<boolean> {
  log("\n📦 Checking dependencies...\n");

  // Check if node_modules exists
  if (!existsSync(`${SKILL_DIR}/node_modules`)) {
    info("Installing dependencies...");
    try {
      execSync("bun install", { cwd: SKILL_DIR, stdio: "inherit" });
      success("Dependencies installed");
    } catch {
      error("Failed to install dependencies");
      return false;
    }
  } else {
    success("Dependencies already installed");
  }

  return true;
}

async function checkProviders(): Promise<void> {
  log("\n🔑 Checking API keys...\n");

  const status: Record<string, { configured: boolean; isDemo: boolean }> = {};

  for (const [id, provider] of Object.entries(PROVIDERS)) {
    const { key, description } = getKeyFromManager(provider.service);

    if (!key) {
      status[id] = { configured: false, isDemo: false };
      warn(`${provider.name}: Not configured`);
    } else if (description.toLowerCase().includes("demo") || key.includes("demo")) {
      status[id] = { configured: true, isDemo: true };
      warn(`${provider.name}: Demo key (won't work)`);
    } else {
      status[id] = { configured: true, isDemo: false };
      success(`${provider.name}: Configured`);
    }
  }

  return;
}

async function configureProvider(providerId: string): Promise<boolean> {
  const provider = PROVIDERS[providerId as keyof typeof PROVIDERS];
  if (!provider) return false;

  log(`\n🔧 Configuring ${provider.name}...\n`);
  info(`Get your API key at: ${provider.getKeyUrl}`);
  log("");

  const key = await prompt(`Enter your ${provider.name} API key (or press Enter to skip): `);

  if (!key) {
    info(`Skipped ${provider.name}`);
    return false;
  }

  // Validate key format
  if (!key.startsWith(provider.keyPrefix)) {
    warn(`Key doesn't start with expected prefix '${provider.keyPrefix}'`);
    const proceed = await promptYesNo("Add anyway?", false);
    if (!proceed) return false;
  }

  // Delete existing key if present
  const existing = getKeyFromManager(provider.service);
  if (existing.key) {
    deleteKeyFromManager(provider.service);
  }

  // Add new key
  const added = addKeyToManager(provider.service, key, `${provider.name} API key`);
  if (added) {
    success(`${provider.name} key added`);
    return true;
  } else {
    error(`Failed to add ${provider.name} key`);
    return false;
  }
}

async function testProvider(providerId: string): Promise<boolean> {
  const provider = PROVIDERS[providerId as keyof typeof PROVIDERS];
  if (!provider) return false;

  log(`\n🧪 Testing ${provider.name}...`);

  try {
    const result = execSync(
      `bun ${SKILL_DIR}/index.ts ${providerId === "google" ? "gemini" : providerId} "Say 'OK' and nothing else"`,
      { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"], timeout: 30000 }
    );

    if (result.toLowerCase().includes("ok")) {
      success(`${provider.name} is working!`);
      return true;
    } else {
      success(`${provider.name} responded: ${result.trim().slice(0, 50)}`);
      return true;
    }
  } catch (e: any) {
    error(`${provider.name} failed: ${e.message?.slice(0, 100) || "Unknown error"}`);
    return false;
  }
}

async function interactiveSetup(): Promise<void> {
  log("\n" + "=".repeat(50));
  log("  🚀 navi-llm Setup");
  log("=".repeat(50));

  // Step 1: Dependencies
  const depsOk = await checkDependencies();
  if (!depsOk) {
    error("Setup failed at dependencies");
    process.exit(1);
  }

  // Step 2: Check current status
  await checkProviders();

  // Step 3: Configure missing/demo providers
  log("\n" + "-".repeat(50));
  const configure = await promptYesNo("\nWould you like to configure API keys?");

  if (configure) {
    for (const providerId of Object.keys(PROVIDERS)) {
      const { key, description } = getKeyFromManager(
        PROVIDERS[providerId as keyof typeof PROVIDERS].service
      );
      const needsConfig = !key || description.toLowerCase().includes("demo");

      if (needsConfig) {
        await configureProvider(providerId);
      } else {
        const reconfigure = await promptYesNo(
          `${PROVIDERS[providerId as keyof typeof PROVIDERS].name} is already configured. Reconfigure?`,
          false
        );
        if (reconfigure) {
          await configureProvider(providerId);
        }
      }
    }
  }

  // Step 4: Test providers
  log("\n" + "-".repeat(50));
  const test = await promptYesNo("\nWould you like to test the configured providers?");

  if (test) {
    for (const providerId of Object.keys(PROVIDERS)) {
      const { key, description } = getKeyFromManager(
        PROVIDERS[providerId as keyof typeof PROVIDERS].service
      );
      if (key && !description.toLowerCase().includes("demo")) {
        await testProvider(providerId);
      }
    }
  }

  // Done
  log("\n" + "=".repeat(50));
  success("Setup complete!");
  log("");
  log("Usage:");
  log("  bun ~/.claude/skills/navi-llm/index.ts models");
  log("  bun ~/.claude/skills/navi-llm/index.ts gpt4o \"Your prompt\"");
  log("  bun ~/.claude/skills/navi-llm/index.ts gemini \"Your prompt\"");
  log("=".repeat(50) + "\n");
}

async function quickStatus(): Promise<void> {
  log("\n🔍 navi-llm Status\n");

  for (const [id, provider] of Object.entries(PROVIDERS)) {
    const { key, description } = getKeyFromManager(provider.service);

    if (!key) {
      error(`${provider.name}: Not configured`);
    } else if (description.toLowerCase().includes("demo")) {
      warn(`${provider.name}: Demo key`);
    } else {
      success(`${provider.name}: Ready`);
    }
  }
  log("");
}

// ============================================================================
// Main
// ============================================================================

async function main() {
  const args = process.argv.slice(2);
  const command = args[0];

  switch (command) {
    case "status":
      await quickStatus();
      break;

    case "test":
      for (const providerId of Object.keys(PROVIDERS)) {
        await testProvider(providerId);
      }
      break;

    case "add":
      const provider = args[1];
      if (provider && PROVIDERS[provider as keyof typeof PROVIDERS]) {
        await configureProvider(provider);
      } else {
        log("Usage: setup.ts add <openai|anthropic|google>");
      }
      break;

    default:
      await interactiveSetup();
  }
}

main().catch(console.error);
