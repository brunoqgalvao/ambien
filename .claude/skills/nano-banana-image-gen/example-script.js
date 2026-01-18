/**
 * Nano Banana Image Generation - Example Script
 *
 * This script demonstrates both standard and Pro API usage.
 * Make sure to set your API keys in environment variables first.
 */

const { NanoBanana, NanoBananaPro } = require('nano-banana-sdk');
const fs = require('fs');
const path = require('path');

// Configuration
const OUTPUT_DIR = './generated-images';

// Ensure output directory exists
if (!fs.existsSync(OUTPUT_DIR)) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
}

/**
 * Generate image using standard Nano Banana API
 */
async function generateStandard(prompt, options = {}) {
  console.log('🍌 Generating with Nano Banana...');

  const client = new NanoBanana({
    apiKey: process.env.GEMINI_API_KEY
  });

  const result = await client.generate({
    prompt: prompt,
    width: options.width || 1024,
    height: options.height || 1024,
    steps: options.steps || 20,
    ...(options.imagePrompt && { imagePrompt: options.imagePrompt }),
    ...(options.strength && { strength: options.strength })
  });

  // Save image
  const timestamp = Date.now();
  const filename = `nano-banana-${timestamp}.png`;
  const filepath = path.join(OUTPUT_DIR, filename);

  if (result.imageUrl) {
    // If URL is returned, download it
    const response = await fetch(result.imageUrl);
    const buffer = await response.arrayBuffer();
    fs.writeFileSync(filepath, Buffer.from(buffer));
  } else if (result.imageData) {
    // If base64 data is returned
    const buffer = Buffer.from(result.imageData, 'base64');
    fs.writeFileSync(filepath, buffer);
  }

  console.log('✅ Image saved to:', filepath);
  return filepath;
}

/**
 * Generate image using Nano Banana Pro API
 */
async function generatePro(prompt, options = {}) {
  console.log('🍌✨ Generating with Nano Banana Pro...');

  const client = new NanoBananaPro({
    apiKey: process.env.GEMINI_API_KEY
  });

  const result = await client.generate({
    prompt: prompt,
    width: options.width || 2048,
    height: options.height || 2048,
    quality: options.quality || 'high',
    style: options.style || 'realistic',
    steps: options.steps || 50,
    ...(options.imagePrompt && { imagePrompt: options.imagePrompt }),
    ...(options.strength && { strength: options.strength })
  });

  // Save image
  const timestamp = Date.now();
  const filename = `nano-banana-pro-${timestamp}.png`;
  const filepath = path.join(OUTPUT_DIR, filename);

  const buffer = Buffer.from(result.imageData, 'base64');
  fs.writeFileSync(filepath, buffer);

  console.log('✅ Image saved to:', filepath);
  return filepath;
}

/**
 * Generate image with an image prompt (style transfer)
 */
async function generateWithImagePrompt(textPrompt, imagePromptPath, usePro = false) {
  console.log('🖼️  Loading image prompt...');

  const imageBuffer = fs.readFileSync(imagePromptPath);
  const imageBase64 = imageBuffer.toString('base64');

  const options = {
    imagePrompt: imageBase64,
    strength: 0.7
  };

  if (usePro) {
    return await generatePro(textPrompt, options);
  } else {
    return await generateStandard(textPrompt, options);
  }
}

// Main execution
async function main() {
  try {
    // Parse command line arguments
    const args = process.argv.slice(2);

    if (args.length === 0) {
      console.log('Usage:');
      console.log('  node example-script.js "your prompt here" [--pro] [--image-prompt path/to/image.jpg]');
      console.log('\nExamples:');
      console.log('  node example-script.js "a sunset over mountains"');
      console.log('  node example-script.js "a futuristic city" --pro');
      console.log('  node example-script.js "in this style" --image-prompt reference.jpg');
      process.exit(0);
    }

    const prompt = args[0];
    const usePro = args.includes('--pro');
    const imagePromptIndex = args.indexOf('--image-prompt');
    const imagePromptPath = imagePromptIndex !== -1 ? args[imagePromptIndex + 1] : null;

    // Validate API keys
    if (!process.env.GEMINI_API_KEY) {
      throw new Error('GEMINI_API_KEY environment variable is not set');
    }

    console.log(`\n${'='.repeat(50)}`);
    console.log('🍌 Nano Banana Image Generation');
    console.log(`${'='.repeat(50)}\n`);
    console.log('Prompt:', prompt);
    console.log('API:', usePro ? 'Nano Banana Pro' : 'Nano Banana');
    if (imagePromptPath) {
      console.log('Image Prompt:', imagePromptPath);
    }
    console.log();

    // Generate image
    let filepath;
    if (imagePromptPath) {
      filepath = await generateWithImagePrompt(prompt, imagePromptPath, usePro);
    } else if (usePro) {
      filepath = await generatePro(prompt);
    } else {
      filepath = await generateStandard(prompt);
    }

    console.log('\n✨ Generation complete!');
    console.log('📁 Output:', filepath);

  } catch (error) {
    console.error('\n❌ Error:', error.message);

    if (error.code === 'INVALID_API_KEY') {
      console.error('   → Check your API key configuration');
    } else if (error.code === 'RATE_LIMIT') {
      console.error('   → You have exceeded the rate limit, please wait');
    } else if (error.code === 'ENOENT') {
      console.error('   → Image prompt file not found');
    }

    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main();
}

// Export functions for use as a module
module.exports = {
  generateStandard,
  generatePro,
  generateWithImagePrompt
};
