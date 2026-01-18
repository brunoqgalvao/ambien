# Nano Banana Image Generation Skill

This skill enables Claude Code to help you generate images using the Nano Banana and Nano Banana Pro APIs.

## Installation

The skill is automatically available in Claude Code once placed in `~/.claude/skills/nano-banana-image-gen/`.

## Setup

### 1. Install the SDK in your project

```bash
npm install nano-banana-sdk
```

Or if you don't have a package.json yet:

```bash
npm init -y
npm install nano-banana-sdk dotenv
```

### 2. Configure API Keys

Both Nano Banana and Nano Banana Pro use the same Gemini API key.

Create a `.env` file in your project root:

```bash
GEMINI_API_KEY=your-gemini-api-key-here
```

Or set environment variables:

```bash
export GEMINI_API_KEY="your-gemini-api-key-here"
```

**Good news:** Your Gemini API key is already stored in the keymanager!

## Usage

Simply ask Claude Code to generate images:

### Example Prompts

```
"Generate an image of a sunset over mountains"
"Create a professional headshot using Nano Banana Pro"
"Generate a logo design for a tech startup"
"Create an artistic image similar to this reference" (with image)
```

Claude will:
1. Understand your requirements
2. Choose the appropriate API (standard vs Pro)
3. Generate the necessary code
4. Execute and save the image
5. Show you where it's saved

## Testing the Skill

You can test the example script directly:

```bash
# Basic generation
node example-script.js "a beautiful landscape"

# Using Pro API
node example-script.js "a detailed portrait" --pro

# With image prompt
node example-script.js "in this artistic style" --image-prompt reference.jpg --pro
```

## Skill Activation

The skill automatically activates when you:
- Ask to generate images
- Mention "Nano Banana" or "image generation"
- Request visual content creation
- Want to use AI image APIs

## File Structure

```
nano-banana-image-gen/
├── SKILL.md                 # Main skill definition
├── README.md                # This file
├── example-script.js        # Ready-to-use example script
└── package.json.template    # Project setup template
```

## Features

- ✅ Standard and Pro API support
- ✅ Text-to-image generation
- ✅ Image-to-image with prompts (style transfer)
- ✅ Customizable parameters (size, quality, style)
- ✅ Error handling and validation
- ✅ Automatic file saving
- ✅ API key management guidance

## API Comparison

| Feature | Nano Banana | Nano Banana Pro |
|---------|-------------|-----------------|
| Quality | Standard | High |
| Speed | Fast | Slower |
| Max Resolution | 1024x1024 | 2048x2048+ |
| Style Options | Limited | Multiple |
| Cost | Lower | Higher |

## Troubleshooting

**Skill not activating?**
- Restart Claude Code after adding the skill
- Check the skill is in the correct directory
- Verify SKILL.md has valid YAML frontmatter

**API errors?**
- Verify your API keys are correct
- Check you have credits/quota remaining
- Ensure SDK is installed (`npm list nano-banana-sdk`)

**Script errors?**
- Make sure Node.js 14+ is installed
- Run `npm install` to install dependencies
- Check file paths are correct

## Contributing

Feel free to customize this skill for your specific needs:
- Modify default parameters in SKILL.md
- Add more examples to example-script.js
- Create additional helper scripts
- Add support for batch generation

## Notes

- This is a template skill - adjust the SDK usage to match the actual Nano Banana API
- API keys should never be committed to version control
- Consider rate limiting when making multiple requests
- Pro API typically has higher costs per generation

## Resources

- Nano Banana API Documentation: [Add your link]
- Nano Banana Pro Documentation: [Add your link]
- Claude Code Skills Documentation: https://code.claude.com/docs/en/skills.md
