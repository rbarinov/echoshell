# Instructions for Adding Logo Images

## Cursor Logo
1. Download the official Cursor logo from https://cursor.com
2. Save the logo as PNG files with the following names:
   - `CursorLogo.png` (1x - 32x32 pixels)
   - `CursorLogo@2x.png` (2x - 64x64 pixels)
   - `CursorLogo@3x.png` (3x - 96x96 pixels)
3. Place all three files in: `EchoShell/EchoShell/Assets.xcassets/CursorLogo.imageset/`

## Claude Logo
1. Download the official Claude/Anthropic logo from https://www.anthropic.com or https://claude.ai
2. Save the logo as PNG files with the following names:
   - `ClaudeLogo.png` (1x - 32x32 pixels)
   - `ClaudeLogo@2x.png` (2x - 64x64 pixels)
   - `ClaudeLogo@3x.png` (3x - 96x96 pixels)
3. Place all three files in: `EchoShell/EchoShell/Assets.xcassets/ClaudeLogo.imageset/`

## Notes
- The logos will automatically appear in the terminal list once the images are added
- If images are not found, the app will fall back to system icons (brain.head.profile for Cursor, sparkles for Claude)
- Make sure the logos have transparent backgrounds for best appearance
- Recommended format: PNG with transparency

