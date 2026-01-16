#!/usr/bin/env bun

import { generateText, streamText } from "ai";
import { createOpenAI } from "@ai-sdk/openai";
import { createAnthropic } from "@ai-sdk/anthropic";
import { createGoogleGenerativeAI } from "@ai-sdk/google";
import { execSync } from "child_process";

// ============================================================================
// Configuration
// ============================================================================

const KEYMANAGER_MASTER_KEY = "1479863a-96d5-4a9d-9824-1996c21a2d36";
const KEYMANAGER_PATH = "/Users/brunogalvao/Documents/dev-bruno/api-key-manager/index.ts";

// Provider configurations with their models
const PROVIDERS: Record<string, ProviderConfig> = {
  openai: {
    service: "openai",
    envVar: "OPENAI_API_KEY",
    models: [
      { id: "gpt-4o", name: "GPT-4o", description: "Most capable, multimodal" },
      { id: "gpt-4o-mini", name: "GPT-4o Mini", description: "Fast and cheap" },
      { id: "gpt-4-turbo", name: "GPT-4 Turbo", description: "Previous flagship" },
      { id: "o1", name: "o1", description: "Reasoning model" },
      { id: "o1-mini", name: "o1 Mini", description: "Fast reasoning" },
      { id: "o3-mini", name: "o3 Mini", description: "Latest reasoning (if available)" },
    ],
    createProvider: (apiKey: string) => createOpenAI({ apiKey }),
  },
  anthropic: {
    service: "anthropic",
    envVar: "ANTHROPIC_API_KEY",
    models: [
      { id: "claude-opus-4-5-20251101", name: "Claude Opus 4.5", description: "Most capable" },
      { id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", description: "Balanced" },
      { id: "claude-3-5-sonnet-latest", name: "Claude 3.5 Sonnet", description: "Fast and capable" },
      { id: "claude-3-5-haiku-latest", name: "Claude 3.5 Haiku", description: "Fastest" },
    ],
    createProvider: (apiKey: string) => createAnthropic({ apiKey }),
  },
  google: {
    service: "gemini",
    envVar: "GEMINI_API_KEY",
    models: [
      { id: "gemini-2.0-flash-exp", name: "Gemini 2.0 Flash", description: "Latest multimodal" },
      { id: "gemini-1.5-pro", name: "Gemini 1.5 Pro", description: "Long context" },
      { id: "gemini-1.5-flash", name: "Gemini 1.5 Flash", description: "Fast" },
    ],
    createProvider: (apiKey: string) => createGoogleGenerativeAI({ apiKey }),
  },
};

// Model aliases for convenience
const MODEL_ALIASES: Record<string, { provider: string; model: string }> = {
  // OpenAI shortcuts
  "gpt4": { provider: "openai", model: "gpt-4o" },
  "gpt4o": { provider: "openai", model: "gpt-4o" },
  "gpt4-mini": { provider: "openai", model: "gpt-4o-mini" },
  "o1": { provider: "openai", model: "o1" },
  "o1-mini": { provider: "openai", model: "o1-mini" },
  "o3-mini": { provider: "openai", model: "o3-mini" },

  // Anthropic shortcuts
  "opus": { provider: "anthropic", model: "claude-opus-4-5-20251101" },
  "sonnet": { provider: "anthropic", model: "claude-sonnet-4-20250514" },
  "haiku": { provider: "anthropic", model: "claude-3-5-haiku-latest" },
  "claude": { provider: "anthropic", model: "claude-3-5-sonnet-latest" },

  // Google shortcuts
  "gemini": { provider: "google", model: "gemini-2.0-flash-exp" },
  "gemini-pro": { provider: "google", model: "gemini-1.5-pro" },
  "gemini-flash": { provider: "google", model: "gemini-1.5-flash" },
};

// ============================================================================
// Types
// ============================================================================

interface ModelInfo {
  id: string;
  name: string;
  description: string;
}

interface ProviderConfig {
  service: string;
  envVar: string;
  models: ModelInfo[];
  createProvider: (apiKey: string) => any;
}

interface KeyInfo {
  id: string;
  service: string;
  key: string;
  envVar: string;
}

// ============================================================================
// Key Management
// ============================================================================

function getKeyFromManager(service: string): string | null {
  try {
    // Use find --service to get keys by service name (handles composite IDs like gemini_games)
    const result = execSync(
      `export KEYMANAGER_MASTER_KEY="${KEYMANAGER_MASTER_KEY}" && ${KEYMANAGER_PATH} find --service ${service}`,
      { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }
    );
    const keys = JSON.parse(result);
    if (!keys || keys.length === 0) return null;

    // Get the first matching key's ID, then fetch with --show-key
    const keyId = keys[0].id;
    const keyResult = execSync(
      `export KEYMANAGER_MASTER_KEY="${KEYMANAGER_MASTER_KEY}" && ${KEYMANAGER_PATH} get ${keyId} --show-key --format json`,
      { encoding: "utf-8", stdio: ["pipe", "pipe", "pipe"] }
    );
    const data = JSON.parse(keyResult);
    return data.key || null;
  } catch {
    return null;
  }
}

function discoverAvailableProviders(): Map<string, string> {
  const available = new Map<string, string>();

  for (const [providerName, config] of Object.entries(PROVIDERS)) {
    // Try keymanager first
    const key = getKeyFromManager(config.service);
    if (key) {
      available.set(providerName, key);
      continue;
    }

    // Fall back to environment variable
    const envKey = process.env[config.envVar];
    if (envKey) {
      available.set(providerName, envKey);
    }
  }

  return available;
}

// ============================================================================
// Model Resolution
// ============================================================================

function resolveModel(modelInput: string): { provider: string; model: string } | null {
  // Check aliases first
  const lowerInput = modelInput.toLowerCase();
  if (MODEL_ALIASES[lowerInput]) {
    return MODEL_ALIASES[lowerInput];
  }

  // Check if it's a full model ID (provider/model or just model)
  if (modelInput.includes("/")) {
    const [provider, model] = modelInput.split("/", 2);
    if (PROVIDERS[provider]) {
      return { provider, model };
    }
  }

  // Try to find the model in any provider
  for (const [providerName, config] of Object.entries(PROVIDERS)) {
    const found = config.models.find(m =>
      m.id === modelInput || m.id.includes(modelInput)
    );
    if (found) {
      return { provider: providerName, model: found.id };
    }
  }

  return null;
}

// ============================================================================
// LLM Dispatch
// ============================================================================

async function dispatch(
  modelInput: string,
  prompt: string,
  options: {
    system?: string;
    stream?: boolean;
    maxTokens?: number;
    temperature?: number;
  } = {}
): Promise<string> {
  const availableProviders = discoverAvailableProviders();

  // Resolve the model
  const resolved = resolveModel(modelInput);
  if (!resolved) {
    throw new Error(`Unknown model: ${modelInput}. Use 'navi-llm models' to see available models.`);
  }

  const { provider, model } = resolved;

  // Check if we have the key for this provider
  const apiKey = availableProviders.get(provider);
  if (!apiKey) {
    throw new Error(`No API key found for provider '${provider}'. Add it with keymanager or set ${PROVIDERS[provider].envVar}`);
  }

  // Create the provider instance
  const providerInstance = PROVIDERS[provider].createProvider(apiKey);
  const llmModel = providerInstance(model);

  // Dispatch the request
  if (options.stream) {
    const result = await streamText({
      model: llmModel,
      prompt,
      system: options.system,
      maxTokens: options.maxTokens || 4096,
      temperature: options.temperature,
    });

    let fullText = "";
    for await (const chunk of result.textStream) {
      process.stdout.write(chunk);
      fullText += chunk;
    }
    console.log(); // newline at end
    return fullText;
  } else {
    const result = await generateText({
      model: llmModel,
      prompt,
      system: options.system,
      maxTokens: options.maxTokens || 4096,
      temperature: options.temperature,
    });

    return result.text;
  }
}

// ============================================================================
// CLI Commands
// ============================================================================

function showHelp() {
  console.log(`
navi-llm - Multi-LLM Dispatch for Claude Code

USAGE:
  navi-llm <model> "<prompt>"         Dispatch prompt to model
  navi-llm models                     List available models
  navi-llm providers                  Show configured providers
  navi-llm help                       Show this help

MODEL SHORTCUTS:
  gpt4, gpt4o, gpt4-mini, o1, o1-mini, o3-mini
  opus, sonnet, haiku, claude
  gemini, gemini-pro, gemini-flash

EXAMPLES:
  navi-llm gpt4o "Explain this error: ..."
  navi-llm gemini "Review this code for bugs"
  navi-llm haiku "Quick summary of: ..."
  navi-llm openai/gpt-4-turbo "Complex analysis..."

OPTIONS:
  --stream              Stream output (default: false)
  --system "..."        System prompt
  --max-tokens N        Max tokens (default: 4096)
  --temperature N       Temperature 0-2 (default: model default)
  --json                Output as JSON (for programmatic use)
`);
}

function showModels() {
  const availableProviders = discoverAvailableProviders();

  console.log("\n📦 AVAILABLE MODELS\n");

  for (const [providerName, config] of Object.entries(PROVIDERS)) {
    const hasKey = availableProviders.has(providerName);
    const status = hasKey ? "✅" : "❌";

    console.log(`${status} ${providerName.toUpperCase()} (${config.service})`);

    if (hasKey) {
      for (const model of config.models) {
        console.log(`   • ${model.id}`);
        console.log(`     ${model.name} - ${model.description}`);
      }
    } else {
      console.log(`   (No API key - add '${config.service}' via keymanager)`);
    }
    console.log();
  }

  console.log("SHORTCUTS:");
  console.log("  gpt4, gpt4o, gpt4-mini, o1, o1-mini");
  console.log("  opus, sonnet, haiku, claude");
  console.log("  gemini, gemini-pro, gemini-flash");
  console.log();
}

function showProviders() {
  const availableProviders = discoverAvailableProviders();

  console.log("\n🔑 CONFIGURED PROVIDERS\n");

  const result: Record<string, { available: boolean; models: string[] }> = {};

  for (const [providerName, config] of Object.entries(PROVIDERS)) {
    const hasKey = availableProviders.has(providerName);
    result[providerName] = {
      available: hasKey,
      models: hasKey ? config.models.map(m => m.id) : [],
    };

    const status = hasKey ? "✅" : "❌";
    console.log(`${status} ${providerName}: ${hasKey ? "configured" : "missing key"}`);
  }

  // Check for --json flag
  if (process.argv.includes("--json")) {
    console.log(JSON.stringify(result, null, 2));
  }
}

// ============================================================================
// Main
// ============================================================================

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === "help" || args[0] === "--help") {
    showHelp();
    return;
  }

  if (args[0] === "models") {
    showModels();
    return;
  }

  if (args[0] === "providers") {
    showProviders();
    return;
  }

  // Parse dispatch command
  const modelInput = args[0];

  // Find prompt (everything after model that's not a flag)
  let prompt = "";
  let system: string | undefined;
  let stream = false;
  let maxTokens = 4096;
  let temperature: number | undefined;
  let jsonOutput = false;

  for (let i = 1; i < args.length; i++) {
    const arg = args[i];

    if (arg === "--stream") {
      stream = true;
    } else if (arg === "--json") {
      jsonOutput = true;
    } else if (arg === "--system" && args[i + 1]) {
      system = args[++i];
    } else if (arg === "--max-tokens" && args[i + 1]) {
      maxTokens = parseInt(args[++i], 10);
    } else if (arg === "--temperature" && args[i + 1]) {
      temperature = parseFloat(args[++i]);
    } else if (!arg.startsWith("--")) {
      prompt = arg;
    }
  }

  if (!prompt) {
    console.error("Error: No prompt provided");
    console.error("Usage: navi-llm <model> \"<prompt>\"");
    process.exit(1);
  }

  try {
    const result = await dispatch(modelInput, prompt, {
      system,
      stream,
      maxTokens,
      temperature,
    });

    if (jsonOutput && !stream) {
      console.log(JSON.stringify({ model: modelInput, response: result }));
    } else if (!stream) {
      console.log(result);
    }
  } catch (error: any) {
    console.error(`Error: ${error.message}`);
    process.exit(1);
  }
}

main();
