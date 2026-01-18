---
name: nano-banana-image-gen
description: Generate images using Nano Banana Pro and Nano Banana APIs via JavaScript/Node SDK. Use this skill when the user asks to generate images, create graphics, produce visual content, or interact with Nano Banana image generation APIs.
---

# Nano Banana Image Generation Skill

## Overview

This skill enables AI image generation through Google's Gemini image models:
- **Nano Banana** (gemini-2.0-flash-exp) - Fast, efficient generation
- **Nano Banana Pro** - Professional-grade, higher quality

Both use the official Google Generative AI SDK.

## CLI Tool (Recommended)

The easiest way to generate images is using the `nano-banana` CLI:

### Quick Start

```bash
# Generate a new image
nano-banana generate "a sunset over mountains"

# Edit an existing image
nano-banana edit ./image.png "add a red hat"

# Use Pro model for higher quality
nano-banana generate "detailed portrait" --pro

# Custom output filename
nano-banana generate "a cat" -o my-cat.png
```

### CLI Commands

| Command | Description |
|---------|-------------|
| `nano-banana generate "prompt"` | Generate a new image from text |
| `nano-banana edit image.png "prompt"` | Edit an existing image |
| `nano-banana --help` | Show help |

### CLI Options

| Option | Description |
|--------|-------------|
| `--pro` | Use high-quality Pro model |
| `--output, -o` | Custom output filename |

### Requirements

The CLI requires a `.env` file in the current directory with:
```
GEMINI_API_KEY=your-api-key
```

## Setup Instructions (Manual)

If you need to set up manually:

### 1. Install the SDK

```bash
npm install @google/genai dotenv
```

### 2. Configure API Keys

**Option A: .env File**
```
GEMINI_API_KEY=your-gemini-api-key
```

**Option B: Using keymanager skill**
The Gemini API key is already stored in keymanager and available for use.

## Usage Instructions

When a user requests image generation:

1. **Use the CLI** (preferred)
   - For new images: `nano-banana generate "prompt"`
   - For editing: `nano-banana edit image.png "prompt"`
   - Add `--pro` for higher quality

2. **Or write custom code** (for advanced use cases)
   - See code templates below

## Code Template

### Basic Nano Banana Generation (Fast)

```javascript
import { GoogleGenAI } from "@google/genai";
import fs from "fs";

async function generateImage(prompt) {
  const ai = new GoogleGenAI({});

  const response = await ai.models.generateContent({
    model: "gemini-2.5-flash-image",
    contents: prompt,
  });

  // Extract and save image
  for (const part of response.candidates[0].content.parts) {
    if (part.inlineData) {
      const buffer = Buffer.from(part.inlineData.data, "base64");
      fs.writeFileSync('output.png', buffer);
      return 'output.png';
    }
  }
}

generateImage("A portrait of a person")
  .then(file => console.log('Image saved:', file))
  .catch(err => console.error('Error:', err));
```

### Nano Banana Pro Generation (High Quality)

```javascript
import { GoogleGenAI } from "@google/genai";
import fs from "fs";

async function generateImagePro(prompt) {
  const ai = new GoogleGenAI({});

  const response = await ai.models.generateContent({
    model: "gemini-3-pro-image-preview",
    contents: prompt,
  });

  // Extract and save image
  for (const part of response.candidates[0].content.parts) {
    if (part.inlineData) {
      const buffer = Buffer.from(part.inlineData.data, "base64");
      fs.writeFileSync('output-pro.png', buffer);
      return 'output-pro.png';
    }
  }
}

generateImagePro("A detailed professional headshot")
  .then(file => console.log('Image saved:', file))
  .catch(err => console.error('Error:', err));
```

### With Image Prompt (Image-to-Image)

```javascript
import { GoogleGenAI } from "@google/genai";
import fs from "fs";

async function generateWithImagePrompt(imagePath, textPrompt) {
  const ai = new GoogleGenAI({});

  // Read and encode reference image
  const imageBuffer = fs.readFileSync(imagePath);
  const imageBase64 = imageBuffer.toString('base64');

  const response = await ai.models.generateContent({
    model: "gemini-2.5-flash-image",
    contents: [
      {
        parts: [
          { text: textPrompt },
          {
            inlineData: {
              mimeType: "image/png",
              data: imageBase64
            }
          }
        ]
      }
    ],
  });

  // Extract and save result
  for (const part of response.candidates[0].content.parts) {
    if (part.inlineData) {
      const buffer = Buffer.from(part.inlineData.data, "base64");
      fs.writeFileSync('output-from-image.png', buffer);
      return 'output-from-image.png';
    }
  }
}
```

## Model Selection

- **gemini-2.5-flash-image** (Nano Banana): Fast generation, 1024px resolution, optimized for high-volume tasks
- **gemini-3-pro-image-preview** (Nano Banana Pro): Professional-grade, up to 4K resolution, advanced reasoning

## Key Features

- Text-to-image generation
- Image-to-image with reference images
- High-quality output with legible text
- Multilingual text rendering
- Grounding with Google Search for factual accuracy

## Error Handling

Always include error handling:

```javascript
try {
  const image = await generateImage("your prompt");
  console.log('Success:', image);
} catch (error) {
  console.error('Generation failed:', error.message);
  if (error.message.includes('API key')) {
    console.error('→ Make sure GEMINI_API_KEY is set in .env');
  } else if (error.message.includes('quota')) {
    console.error('→ API quota exceeded, check your billing');
  }
}
```

## Examples

**User:** "Generate an image of a sunset over mountains"
- Use Nano Banana standard API
- Create script with landscape-oriented prompt
- Default quality settings

**User:** "Create a high-quality professional headshot"
- Use Nano Banana Pro API
- Enable "realistic" style
- Use higher steps (50+)
- Save as high-resolution file

**User:** "Generate an image similar to this one" (with uploaded image)
- Use image prompt feature
- Convert uploaded image to base64
- Apply text prompt to guide generation
- Set appropriate strength parameter

## Tips

1. **Prompt Engineering**: More detailed prompts yield better results
2. **Model Selection**: Use gemini-2.5-flash-image for fast generation, gemini-3-pro-image-preview for highest quality
3. **API Keys**: Stored securely in keymanager and available via .env
4. **Image Prompts**: Include reference images for style transfer and composition guidance
5. **Text in Images**: Both models excel at rendering legible text in multiple languages
6. **Grounding**: Prompts can leverage Google Search for factual accuracy

## Troubleshooting

- **Authentication errors**: Verify GEMINI_API_KEY is set in .env file
- **API not found**: Ensure gemini-3-pro-image-preview is enabled in your Google Cloud project
- **Poor results**: Add more detail to prompts, specify style preferences
- **SDK not found**: Run `npm install @google/genai dotenv`
- **ES Module errors**: Ensure package.json has `"type": "module"`
