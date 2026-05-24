#!/bin/bash

# Build script to create a BatteryWatch.plasmoid file

WIDGET_DIR="."
OUTPUT_DIR="./dist"
PLASMOID_NAME="BatteryWatch.plasmoid"

# Change to the widget directory
cd "$WIDGET_DIR" || exit 1

# Remove old plasmoid file if it exists
rm -f "$OUTPUT_DIR/$PLASMOID_NAME"
mkdir -p "$OUTPUT_DIR"

# Check if prebuilt binaries exist
if [ ! -f contents/bin/read_hid_devices.x86_64 ] || [ ! -f contents/bin/read_hid_devices.aarch64 ]; then
    echo "Error: pre-built binaries are missing! Run build-binaries.sh first!"
    exit 1
fi

# Create the plasmoid file (zip) excluding screenshots and build script
echo "Building $PLASMOID_NAME..."
zip -r "$OUTPUT_DIR/$PLASMOID_NAME" . \
    -x "contents/screenshots/*" \
    -x "build-plasmoid.sh" \
    -x "dev-install.sh" \
    -x "dev-uninstall.sh" \
    -x "dev-restart-plasma.sh" \
    -x "dist/*" \
    -x ".git/*" \
    -x ".gitignore" \
    -x "contents/src/*" \
    -x "contents/bin/*.dev"

if [ $? -eq 0 ]; then
    echo "Successfully created: $OUTPUT_DIR/$PLASMOID_NAME"
    ls -lh "$OUTPUT_DIR/$PLASMOID_NAME"
else
    echo "Failed to create plasmoid file"
    exit 1
fi
