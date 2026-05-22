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

# Compile SC2 HID reader
echo "Compiling read_hid_sc2..."
cc -O2 -o contents/bin/read_hid_sc2 contents/src/read_hid_sc2.c || {
    echo "Warning: compilation failed, SC2 support will be unavailable"
}

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
    -x "contents/src/*"

if [ $? -eq 0 ]; then
    echo "Successfully created: $OUTPUT_DIR/$PLASMOID_NAME"
    ls -lh "$OUTPUT_DIR/$PLASMOID_NAME"
else
    echo "Failed to create plasmoid file"
    exit 1
fi
