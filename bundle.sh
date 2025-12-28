#!/bin/bash

# Configuration
APP_NAME="Vectorscoperize"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "🚀 Building ${APP_NAME}..."
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "📦 Creating App Bundle Structure..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy Executable
cp "${BUILD_DIR}/${APP_NAME}" "$MACOS_DIR/"

# Copy Resources (The SwiftPM Bundle)
# Note: SwiftPM creates a bundle for resources named 'TargetName_TargetName.bundle'
SWIFTPM_BUNDLE="${APP_NAME}_${APP_NAME}.bundle"
if [ -d "${BUILD_DIR}/${SWIFTPM_BUNDLE}" ]; then
    cp -r "${BUILD_DIR}/${SWIFTPM_BUNDLE}" "$RESOURCES_DIR/"
    echo "   Included resources: ${SWIFTPM_BUNDLE}"
fi

# Create Info.plist
echo "📝 Generating Info.plist..."
cat > "${CONTENTS_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.zhaoluchen.vectorscoperize</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/> <!-- This hides the app from the Dock, making it a Menu Bar app -->
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "✅ Done! App saved to ${APP_BUNDLE}"
echo "   Run with: open ${APP_BUNDLE}"
