#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_FILE="$SCRIPT_DIR/ocr-watcher.swift"
OUTPUT_BINARY="$SCRIPT_DIR/ocr-watcher"

echo "Compiling OCR watcher..."

# Check if Swift is available
if ! command -v swiftc &> /dev/null; then
    echo "Error: Swift compiler not found. Please install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

# Compile the Swift program
echo "Building Swift binary..."
swiftc "$SOURCE_FILE" -o "$OUTPUT_BINARY" \
    -framework Foundation \
    -framework Vision \
    -framework AppKit

echo "Compilation complete!"
echo "Binary location: $OUTPUT_BINARY"
