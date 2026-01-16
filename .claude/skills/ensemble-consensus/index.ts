#!/usr/bin/env bun
/**
 * Ensemble Consensus - Multi-Model Voting System
 *
 * Dispatches prompts to multiple LLMs in parallel, collects responses,
 * analyzes consensus, and synthesizes the best answer.
 */

import { execSync, spawn } from "child_process";
import { existsSync, readFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

// Types
interface ModelResponse {
  model: string;
  response: string;
  timeMs: number;
  success: boolean;
  error?: string;
}

interface ConsensusResult {
  consensus: "high" | "medium" | "low" | "none";
  score: number;
  synthesizedAnswer: string;
  agreements: string[];
  disagreements: Array<{ topic: string; positions: Record<string, string>; recommendation?: string }>;
  responses: ModelResponse[];
  totalTimeMs: number;
}

interface EnsembleOptions {
  prompt: string;
  context?: string;
  models?: string[];
  mode?: "default" | "code-review" | "security" | "architecture" | "quick";
  threshold?: number;
  judge?: string;
  timeout?: number;
  verbose?: boolean;
}

// Model presets for different modes
const MODE_PRESETS: Record<string, string[]> = {
  default: ["gpt4o", "sonnet", "gemini"],
  "code-review": ["gpt4o", "sonnet", "o1-mini"],
  security: ["gpt4o", "o1-mini", "sonnet"],
  architecture: ["o1", "sonnet", "gemini-pro"],
  quick: ["haiku", "gpt4-mini", "gemini-flash"],
};

// System prompts for different modes
const MODE_PROMPTS: Record<string, string> = {
  default: "You are an expert assistant. Provide a clear, well-reasoned answer.",
  "code-review": `You are a senior software engineer conducting a code review.
Focus on:
- Bugs and potential issues
- Security vulnerabilities
- Performance concerns
- Code quality and maintainability
- Best practices
Be specific and actionable.`,
  security: `You are a security expert conducting a security audit.
Focus on:
- Injection vulnerabilities (SQL, XSS, command injection)
- Authentication/authorization issues
- Data exposure risks
- Dependency vulnerabilities
- OWASP Top 10 issues
Rate severity: CRITICAL, HIGH, MEDIUM, LOW.`,
  architecture: `You are a senior software architect evaluating design decisions.
Consider:
- Scalability and performance
- Maintainability and complexity
- Team capabilities
- Cost and time constraints
- Future flexibility
Provide clear trade-offs and recommendations.`,
  quick: "Provide a concise, direct answer.",
};

const NAVI_LLM_PATH = join(homedir(), ".claude/skills/navi-llm/index.ts");

/**
 * Dispatch a prompt to a single model using navi-llm
 */
async function dispatchToModel(
  model: string,
  prompt: string,
  systemPrompt: string,
  timeout: number
): Promise<ModelResponse> {
  const startTime = Date.now();

  try {
    // Escape the prompts for shell
    const escapedPrompt = prompt.replace(/"/g, '\\"').replace(/\$/g, '\\$');
    const escapedSystem = systemPrompt.replace(/"/g, '\\"').replace(/\$/g, '\\$');

    const result = execSync(
      `bun "${NAVI_LLM_PATH}" ${model} "${escapedPrompt}" --system "${escapedSystem}" --json`,
      {
        encoding: "utf-8",
        timeout,
        maxBuffer: 10 * 1024 * 1024, // 10MB buffer
        env: { ...process.env },
      }
    );

    const timeMs = Date.now() - startTime;

    // Parse JSON response
    try {
      const parsed = JSON.parse(result);
      return {
        model,
        response: parsed.response || parsed.content || result,
        timeMs,
        success: true,
      };
    } catch {
      // If not JSON, use raw response
      return {
        model,
        response: result.trim(),
        timeMs,
        success: true,
      };
    }
  } catch (error: any) {
    return {
      model,
      response: "",
      timeMs: Date.now() - startTime,
      success: false,
      error: error.message || "Unknown error",
    };
  }
}

/**
 * Dispatch prompt to all models in parallel
 */
async function dispatchToAllModels(
  models: string[],
  prompt: string,
  systemPrompt: string,
  timeout: number
): Promise<ModelResponse[]> {
  const promises = models.map((model) =>
    dispatchToModel(model, prompt, systemPrompt, timeout)
  );

  return Promise.all(promises);
}

/**
 * Analyze consensus using a judge model
 */
async function analyzeConsensus(
  responses: ModelResponse[],
  originalPrompt: string,
  judgeModel: string
): Promise<{
  consensus: "high" | "medium" | "low" | "none";
  score: number;
  synthesizedAnswer: string;
  agreements: string[];
  disagreements: Array<{ topic: string; positions: Record<string, string>; recommendation?: string }>;
}> {
  const successfulResponses = responses.filter((r) => r.success);

  if (successfulResponses.length === 0) {
    return {
      consensus: "none",
      score: 0,
      synthesizedAnswer: "All models failed to respond.",
      agreements: [],
      disagreements: [],
    };
  }

  if (successfulResponses.length === 1) {
    return {
      consensus: "low",
      score: 0.3,
      synthesizedAnswer: successfulResponses[0].response,
      agreements: ["Only one model responded successfully"],
      disagreements: [],
    };
  }

  // Build analysis prompt
  const analysisPrompt = `You are analyzing responses from multiple AI models to find consensus.

ORIGINAL QUESTION:
${originalPrompt}

MODEL RESPONSES:
${successfulResponses.map((r, i) => `
--- ${r.model.toUpperCase()} ---
${r.response}
`).join("\n")}

Analyze these responses and provide:
1. A CONSENSUS SCORE from 0.0 to 1.0 (1.0 = perfect agreement)
2. A SYNTHESIZED ANSWER that combines the best insights from all models
3. KEY AGREEMENTS - points where models agree
4. KEY DISAGREEMENTS - points where models differ, with recommendations

Output in this exact JSON format:
{
  "score": 0.85,
  "synthesizedAnswer": "The combined best answer...",
  "agreements": ["Point 1", "Point 2"],
  "disagreements": [
    {
      "topic": "Token expiry time",
      "positions": {"gpt4o": "15 minutes", "sonnet": "1 hour"},
      "recommendation": "Use 15-30 minutes with refresh tokens"
    }
  ]
}`;

  try {
    const result = execSync(
      `bun "${NAVI_LLM_PATH}" ${judgeModel} "${analysisPrompt.replace(/"/g, '\\"').replace(/\$/g, '\\$')}" --json`,
      {
        encoding: "utf-8",
        timeout: 60000,
        maxBuffer: 10 * 1024 * 1024,
      }
    );

    // Extract JSON from response
    const jsonMatch = result.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      const parsed = JSON.parse(jsonMatch[0]);
      const score = typeof parsed.score === "number" ? parsed.score : 0.5;

      return {
        consensus: score >= 0.8 ? "high" : score >= 0.6 ? "medium" : score >= 0.4 ? "low" : "none",
        score,
        synthesizedAnswer: parsed.synthesizedAnswer || "Unable to synthesize answer",
        agreements: parsed.agreements || [],
        disagreements: parsed.disagreements || [],
      };
    }
  } catch (error) {
    console.error("Judge analysis failed:", error);
  }

  // Fallback: simple synthesis
  return {
    consensus: "medium",
    score: 0.6,
    synthesizedAnswer: successfulResponses[0].response,
    agreements: ["Multiple models provided similar responses"],
    disagreements: [],
  };
}

/**
 * Main ensemble consensus function
 */
export async function getConsensus(options: EnsembleOptions): Promise<ConsensusResult> {
  const {
    prompt,
    context,
    models = MODE_PRESETS[options.mode || "default"],
    mode = "default",
    threshold = 0.7,
    judge = "sonnet",
    timeout = 30000,
    verbose = false,
  } = options;

  const startTime = Date.now();
  const systemPrompt = MODE_PROMPTS[mode] || MODE_PROMPTS.default;
  const fullPrompt = context ? `${prompt}\n\nContext:\n${context}` : prompt;

  // Dispatch to all models in parallel
  if (verbose) {
    console.log(`\nDispatching to ${models.length} models: ${models.join(", ")}`);
  }

  const responses = await dispatchToAllModels(models, fullPrompt, systemPrompt, timeout);

  // Analyze consensus
  const analysis = await analyzeConsensus(responses, prompt, judge);

  return {
    ...analysis,
    responses,
    totalTimeMs: Date.now() - startTime,
  };
}

/**
 * Format result for CLI output
 */
function formatResult(result: ConsensusResult, verbose: boolean): string {
  const successCount = result.responses.filter((r) => r.success).length;
  const totalCount = result.responses.length;

  const consensusEmoji = {
    high: "🟢",
    medium: "🟡",
    low: "🟠",
    none: "🔴",
  };

  let output = `
═══════════════════════════════════════════════════════════════════
                    ENSEMBLE CONSENSUS RESULT
═══════════════════════════════════════════════════════════════════

${consensusEmoji[result.consensus]} CONSENSUS: ${result.consensus.toUpperCase()} (${Math.round(result.score * 100)}%)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SYNTHESIZED ANSWER:
${result.synthesizedAnswer}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
`;

  if (result.agreements.length > 0) {
    output += `
AGREEMENTS:
${result.agreements.map((a) => `✓ ${a}`).join("\n")}
`;
  }

  if (result.disagreements.length > 0) {
    output += `
DISAGREEMENTS:
${result.disagreements.map((d) => {
  const positions = Object.entries(d.positions)
    .map(([model, pos]) => `  ${model}: ${pos}`)
    .join("\n");
  return `⚡ ${d.topic}\n${positions}${d.recommendation ? `\n  → Recommendation: ${d.recommendation}` : ""}`;
}).join("\n\n")}
`;
  }

  output += `
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

MODEL RESPONSES (${successCount}/${totalCount} succeeded):
┌─────────────┬──────────┬────────────────────────────────────────┐
│ Model       │ Time     │ Status                                 │
├─────────────┼──────────┼────────────────────────────────────────┤
${result.responses.map((r) => {
  const status = r.success ? "✓ Success" : `✗ ${r.error?.slice(0, 30) || "Failed"}`;
  return `│ ${r.model.padEnd(11)} │ ${(r.timeMs / 1000).toFixed(1)}s     │ ${status.padEnd(38)} │`;
}).join("\n")}
└─────────────┴──────────┴────────────────────────────────────────┘

Total time: ${(result.totalTimeMs / 1000).toFixed(1)}s
`;

  if (verbose) {
    output += `
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                    INDIVIDUAL RESPONSES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
${result.responses.filter((r) => r.success).map((r) => `
--- ${r.model.toUpperCase()} (${(r.timeMs / 1000).toFixed(1)}s) ---
${r.response}
`).join("\n")}
`;
  }

  return output;
}

// CLI interface
async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args.includes("--help") || args.includes("-h")) {
    console.log(`
Ensemble Consensus - Multi-Model Voting

Usage:
  bun ensemble-consensus/index.ts "<prompt>" [options]
  bun ensemble-consensus/index.ts --code-review "<code>"
  bun ensemble-consensus/index.ts --security "<code>"
  bun ensemble-consensus/index.ts --architecture "<question>"

Options:
  --models "m1,m2,m3"   Custom model list (default: gpt4o,sonnet,gemini)
  --mode <mode>         Preset mode: default, code-review, security, architecture, quick
  --threshold <0-1>     Consensus threshold (default: 0.7)
  --judge <model>       Model to judge consensus (default: sonnet)
  --timeout <ms>        Per-model timeout (default: 30000)
  --json                Output as JSON
  --verbose             Show individual responses
  --help                Show this help

Examples:
  bun index.ts "What's the best way to implement auth?"
  bun index.ts --code-review "$(cat src/auth.ts)"
  bun index.ts --security "$(cat package.json)" --verbose
  bun index.ts --architecture "REST vs GraphQL?" --models "o1,opus,gpt4o"
`);
    process.exit(0);
  }

  // Parse arguments
  let prompt = "";
  let mode: EnsembleOptions["mode"] = "default";
  let models: string[] | undefined;
  let threshold = 0.7;
  let judge = "sonnet";
  let timeout = 30000;
  let verbose = false;
  let jsonOutput = false;

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (arg === "--code-review") {
      mode = "code-review";
      if (args[i + 1] && !args[i + 1].startsWith("--")) {
        prompt = args[++i];
      }
    } else if (arg === "--security") {
      mode = "security";
      if (args[i + 1] && !args[i + 1].startsWith("--")) {
        prompt = args[++i];
      }
    } else if (arg === "--architecture") {
      mode = "architecture";
      if (args[i + 1] && !args[i + 1].startsWith("--")) {
        prompt = args[++i];
      }
    } else if (arg === "--quick") {
      mode = "quick";
    } else if (arg === "--models") {
      models = args[++i].split(",").map((m) => m.trim());
    } else if (arg === "--mode") {
      mode = args[++i] as EnsembleOptions["mode"];
    } else if (arg === "--threshold") {
      threshold = parseFloat(args[++i]);
    } else if (arg === "--judge") {
      judge = args[++i];
    } else if (arg === "--timeout") {
      timeout = parseInt(args[++i]);
    } else if (arg === "--verbose" || arg === "-v") {
      verbose = true;
    } else if (arg === "--json") {
      jsonOutput = true;
    } else if (!arg.startsWith("--")) {
      prompt = arg;
    }
  }

  if (!prompt) {
    console.error("Error: No prompt provided");
    process.exit(1);
  }

  // Check navi-llm exists
  if (!existsSync(NAVI_LLM_PATH)) {
    console.error(`Error: navi-llm skill not found at ${NAVI_LLM_PATH}`);
    console.error("Please ensure the navi-llm skill is installed.");
    process.exit(1);
  }

  try {
    const result = await getConsensus({
      prompt,
      models,
      mode,
      threshold,
      judge,
      timeout,
      verbose,
    });

    if (jsonOutput) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(formatResult(result, verbose));
    }

    // Exit with appropriate code based on consensus
    process.exit(result.consensus === "none" ? 1 : 0);
  } catch (error) {
    console.error("Error:", error);
    process.exit(1);
  }
}

main();
