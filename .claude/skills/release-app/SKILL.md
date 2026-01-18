# Release App Skill

Build, sign, and release MeetingRecorder with OTA updates via Sparkle + GitHub Pages.

## Triggers

Use this skill when the user says:
- "release", "ship it", "deploy"
- "bump version", "new version"
- "build release", "create release"
- "push update", "OTA update"

## Quick Release

```bash
./scripts/release.sh <version> <build>
```

Example:
```bash
./scripts/release.sh 1.0.2 3
```

Then push:
```bash
git add docs/
git commit -m "Release v1.0.2"
git push origin main
```

## Version Numbers

| Field | Description | Example |
|-------|-------------|---------|
| `version` | Marketing version (semver) | `1.0.1`, `1.1.0`, `2.0.0` |
| `build` | Build number (must increment each release) | `1`, `2`, `3`... |

**Rules:**
- Build number MUST always increment (never reuse)
- Marketing version follows semver (major.minor.patch)
- Current: Check `MeetingRecorder/Info.plist` for `CFBundleShortVersionString` and `CFBundleVersion`

## What the Release Script Does

1. Updates `Info.plist` with new version/build
2. Runs `xcodebuild` Release build
3. Creates signed zip in `docs/releases/`
4. Signs with Sparkle EdDSA key (stored in Keychain)
5. Updates `docs/appcast.xml` with new entry
6. Updates `docs/index.html` download link
7. Copies app to `/Applications/`

## File Locations

| File | Purpose |
|------|---------|
| `docs/appcast.xml` | Sparkle update feed |
| `docs/index.html` | Download landing page |
| `docs/releases/*.zip` | Signed app bundles |
| `scripts/release.sh` | Release automation |
| `MeetingRecorder/Info.plist` | Version source of truth |

## GitHub Pages URLs

- **Appcast:** https://brunogalvao.github.io/ami-like/appcast.xml
- **Download:** https://brunogalvao.github.io/ami-like/
- **Zip:** https://brunogalvao.github.io/ami-like/releases/MeetingRecorder-{version}.zip

## Sparkle Configuration

| Setting | Value |
|---------|-------|
| Feed URL | `https://brunogalvao.github.io/ami-like/appcast.xml` |
| Public Key | `xp2vvfvsXmL2AO2/U0PTmfS1akW013Pz5iPpcXRmVac=` |
| Private Key | Stored in macOS Keychain (auto-used by `sign_update`) |

## Manual Steps (if script fails)

### 1. Build Release
```bash
xcodebuild -project MeetingRecorder.xcodeproj \
  -scheme MeetingRecorder \
  -configuration Release \
  clean build
```

### 2. Find Built App
```bash
find ~/Library/Developer/Xcode/DerivedData \
  -path "*/MeetingRecorder*/Build/Products/Release/MeetingRecorder.app" \
  -type d
```

### 3. Create Zip
```bash
ditto -c -k --keepParent /path/to/MeetingRecorder.app MeetingRecorder-X.X.X.zip
```

### 4. Sign Zip
```bash
# Find sign_update tool
SIGN_TOOL=$(find ~/Library/Developer/Xcode/DerivedData \
  -path "*/MeetingRecorder*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
  -type f | head -1)

$SIGN_TOOL MeetingRecorder-X.X.X.zip
```

### 5. Update appcast.xml
Add new `<item>` with signature from step 4.

## Troubleshooting

### "Sparkle tools not found"
Build the project in Xcode first to fetch SPM dependencies.

### Signature mismatch
Re-run `sign_update` on the exact zip file you're distributing.

### Update not detected
- Check `SUFeedURL` in Info.plist matches appcast location
- Verify build number is higher than installed version
- Clear Sparkle cache: `rm -rf ~/Library/Caches/com.meetingrecorder.app.ShipIt`

### GitHub Pages not updating
- Check Settings → Pages is enabled on `/docs` folder
- Wait 1-2 minutes for deployment
- Check Actions tab for deployment status

## Adding Release Notes

Edit `scripts/release.sh` line ~109 to customize release notes, or manually edit `docs/appcast.xml` after running the script.

## Custom Domain (Optional)

To use `meetingrecorder.app` instead of `brunogalvao.github.io`:

1. Add CNAME file to `docs/`:
   ```
   meetingrecorder.app
   ```

2. Configure DNS at your registrar:
   ```
   CNAME @ brunogalvao.github.io
   ```

3. Update `SUFeedURL` in Info.plist:
   ```
   https://meetingrecorder.app/appcast.xml
   ```

4. Update `BASE_URL` in `scripts/release.sh`
