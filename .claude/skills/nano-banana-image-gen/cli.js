#!/usr/bin/env node

/**
 * Nano Banana CLI - Image generation made easy
 *
 * Usage:
 *   nano-banana generate "prompt"                       Generate a new image
 *   nano-banana edit image.png "prompt"                 Edit an existing image
 *   nano-banana combine img1.png img2.png "prompt"      Combine multiple images
 *
 * Options:
 *   --pro                                   Use high-quality Pro model
 *   --output, -o <path>                     Custom output path
 */

import { GoogleGenAI } from "@google/genai";
import fs from "fs";
import path from "path";
import os from "os";
import { config } from "dotenv";

// Load .env from multiple locations (in priority order):
// 1. Current working directory
// 2. Global config ~/.config/nano-banana/.env
// 3. Environment variable (already set)

const localEnvPath = path.join(process.cwd(), ".env");
const globalEnvPath = path.join(os.homedir(), ".config", "nano-banana", ".env");

let envLoaded = false;

// Try local .env first
if (fs.existsSync(localEnvPath)) {
  config({ path: localEnvPath });
  envLoaded = true;
}

// Try global config if no local and no env var yet
if (!envLoaded && !process.env.GEMINI_API_KEY && fs.existsSync(globalEnvPath)) {
  config({ path: globalEnvPath });
  envLoaded = true;
}

// Show helpful message if no API key found
if (!process.env.GEMINI_API_KEY) {
  console.error(`Note: GEMINI_API_KEY not found. Checked:`);
  console.error(`  - ${localEnvPath}`);
  console.error(`  - ${globalEnvPath}`);
  console.error(`  - Environment variable`);
}

const MODELS = {
  standard: "gemini-2.0-flash-exp",
  pro: "gemini-2.0-flash-exp" // Can be updated when pro model is available
};

function parseArgs(args) {
  const result = {
    command: null,
    prompt: null,
    imagePath: null,
    imagePaths: [],  // For combine command
    usePro: false,
    output: null
  };

  let i = 0;
  while (i < args.length) {
    const arg = args[i];

    if (arg === "--pro") {
      result.usePro = true;
    } else if (arg === "--output" || arg === "-o") {
      result.output = args[++i];
    } else if (!result.command) {
      result.command = arg;
    } else if (result.command === "edit" && !result.imagePath) {
      result.imagePath = arg;
    } else if (result.command === "combine") {
      // For combine: collect image paths until we hit the prompt (last non-option arg)
      if (arg.endsWith('.png') || arg.endsWith('.jpg') || arg.endsWith('.jpeg') || arg.endsWith('.webp')) {
        result.imagePaths.push(arg);
      } else if (!result.prompt) {
        result.prompt = arg;
      }
    } else if (!result.prompt) {
      result.prompt = arg;
    }
    i++;
  }

  return result;
}

function showHelp() {
  console.log(`
Nano Banana CLI - AI Image Generation

Usage:
  nano-banana generate "your prompt"                        Generate a new image
  nano-banana edit ./image.png "your prompt"                Edit an existing image
  nano-banana combine img1.png img2.png ... "your prompt"   Combine multiple images

Options:
  --pro              Use high-quality model
  --output, -o       Custom output filename

Examples:
  nano-banana generate "a sunset over mountains"
  nano-banana generate "a portrait of a woman" --pro
  nano-banana edit ./photo.png "add a red hat"
  nano-banana edit ./image.png "make it more colorful" -o result.png
  nano-banana combine lady1.png lady2.png "show them side by side"
  nano-banana combine cat.png dog.png bird.png "all three pets playing together" -o pets.png
`);
}

async function generateImage(prompt, usePro, outputPath) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.error("Error: GEMINI_API_KEY not found in .env file");
    process.exit(1);
  }

  const ai = new GoogleGenAI({ apiKey });
  const model = usePro ? MODELS.pro : MODELS.standard;

  console.log(`Generating image${usePro ? " (Pro)" : ""}...`);
  console.log(`Prompt: ${prompt}\n`);

  const response = await ai.models.generateContent({
    model: model,
    contents: prompt,
    config: {
      responseModalities: ["Text", "Image"],
    },
  });

  for (const part of response.candidates[0].content.parts) {
    if (part.inlineData) {
      const buffer = Buffer.from(part.inlineData.data, "base64");
      const filename = outputPath || `generated-${Date.now()}.png`;
      fs.writeFileSync(filename, buffer);
      console.log(`Image saved: ${filename}`);
      return filename;
    }
  }

  console.error("No image was generated");
  return null;
}

async function editImage(imagePath, prompt, usePro, outputPath) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.error("Error: GEMINI_API_KEY not found in .env file");
    process.exit(1);
  }

  if (!fs.existsSync(imagePath)) {
    console.error(`Error: Image not found: ${imagePath}`);
    process.exit(1);
  }

  const ai = new GoogleGenAI({ apiKey });
  const model = usePro ? MODELS.pro : MODELS.standard;

  // Read and encode the source image
  const imageBuffer = fs.readFileSync(imagePath);
  const imageBase64 = imageBuffer.toString("base64");
  const mimeType = imagePath.endsWith(".jpg") || imagePath.endsWith(".jpeg")
    ? "image/jpeg"
    : "image/png";

  console.log(`Editing image${usePro ? " (Pro)" : ""}...`);
  console.log(`Source: ${imagePath}`);
  console.log(`Prompt: ${prompt}\n`);

  const response = await ai.models.generateContent({
    model: model,
    contents: [
      {
        parts: [
          { text: prompt },
          {
            inlineData: {
              mimeType: mimeType,
              data: imageBase64
            }
          }
        ]
      }
    ],
    config: {
      responseModalities: ["Text", "Image"],
    },
  });

  for (const part of response.candidates[0].content.parts) {
    if (part.inlineData) {
      const buffer = Buffer.from(part.inlineData.data, "base64");
      const filename = outputPath || `edited-${Date.now()}.png`;
      fs.writeFileSync(filename, buffer);
      console.log(`Image saved: ${filename}`);
      return filename;
    }
  }

  console.error("No image was generated");
  return null;
}

async function combineImages(imagePaths, prompt, usePro, outputPath) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    console.error("Error: GEMINI_API_KEY not found in .env file");
    process.exit(1);
  }

  // Validate all images exist
  for (const imgPath of imagePaths) {
    if (!fs.existsSync(imgPath)) {
      console.error(`Error: Image not found: ${imgPath}`);
      process.exit(1);
    }
  }

  const ai = new GoogleGenAI({ apiKey });
  const model = usePro ? MODELS.pro : MODELS.standard;

  console.log(`Combining ${imagePaths.length} images${usePro ? " (Pro)" : ""}...`);
  console.log(`Sources: ${imagePaths.join(", ")}`);
  console.log(`Prompt: ${prompt}\n`);

  // Build parts array with prompt and all images
  const parts = [{ text: prompt }];

  for (const imgPath of imagePaths) {
    const imageBuffer = fs.readFileSync(imgPath);
    const imageBase64 = imageBuffer.toString("base64");
    const mimeType = imgPath.endsWith(".jpg") || imgPath.endsWith(".jpeg")
      ? "image/jpeg"
      : "image/png";

    parts.push({
      inlineData: {
        mimeType: mimeType,
        data: imageBase64
      }
    });
  }

  const response = await ai.models.generateContent({
    model: model,
    contents: [{ parts }],
    config: {
      responseModalities: ["Text", "Image"],
    },
  });

  for (const part of response.candidates[0].content.parts) {
    if (part.inlineData) {
      const buffer = Buffer.from(part.inlineData.data, "base64");
      const filename = outputPath || `combined-${Date.now()}.png`;
      fs.writeFileSync(filename, buffer);
      console.log(`Image saved: ${filename}`);
      return filename;
    }
  }

  console.error("No image was generated");
  return null;
}

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0 || args.includes("--help") || args.includes("-h")) {
    showHelp();
    process.exit(0);
  }

  const parsed = parseArgs(args);

  try {
    if (parsed.command === "generate") {
      if (!parsed.prompt) {
        console.error("Error: Please provide a prompt");
        console.error('Usage: nano-banana generate "your prompt"');
        process.exit(1);
      }
      await generateImage(parsed.prompt, parsed.usePro, parsed.output);
    } else if (parsed.command === "edit") {
      if (!parsed.imagePath || !parsed.prompt) {
        console.error("Error: Please provide an image path and prompt");
        console.error('Usage: nano-banana edit ./image.png "your prompt"');
        process.exit(1);
      }
      await editImage(parsed.imagePath, parsed.prompt, parsed.usePro, parsed.output);
    } else if (parsed.command === "combine") {
      if (parsed.imagePaths.length < 2) {
        console.error("Error: Please provide at least 2 images to combine");
        console.error('Usage: nano-banana combine img1.png img2.png "your prompt"');
        process.exit(1);
      }
      if (!parsed.prompt) {
        console.error("Error: Please provide a prompt describing how to combine the images");
        console.error('Usage: nano-banana combine img1.png img2.png "your prompt"');
        process.exit(1);
      }
      await combineImages(parsed.imagePaths, parsed.prompt, parsed.usePro, parsed.output);
    } else {
      console.error(`Unknown command: ${parsed.command}`);
      showHelp();
      process.exit(1);
    }
  } catch (error) {
    console.error("Error:", error.message);
    process.exit(1);
  }
}

main();
