#!/bin/bash
set -e

echo "Locating build artifacts..."

# 1. Find the dylib (specifically for the iOS architecture)
# We exclude the 'debug' folder if a 'release' or 'distribution' one exists
DYLIB_PATH=$(find . -name "libalvr_client_core.dylib" | grep -v "debug" | head -n 1)

# Fallback to any dylib if the above filter is too strict
if [ -z "$DYLIB_PATH" ]; then
    DYLIB_PATH=$(find . -name "libalvr_client_core.dylib" | head -n 1)
fi

# 2. Find the header file
HEADER_PATH=$(find . -name "alvr_client_core.h" | head -n 1)

# Validation
if [ -z "$DYLIB_PATH" ] || [ -z "$HEADER_PATH" ]; then
    echo "ERROR: Could not find required files."
    echo "Dylib: ${DYLIB_PATH:-NOT FOUND}"
    echo "Header: ${HEADER_PATH:-NOT FOUND}"
    exit 1
fi

echo "Found Dylib: $DYLIB_PATH"
echo "Found Header: $HEADER_PATH"

# 3. Clean and Stage
rm -rf alvrrepack ALVRClientCore.xcframework || true
mkdir -p alvrrepack/headers

cp "$DYLIB_PATH" alvrrepack/libalvr_client_core.dylib
cp "$HEADER_PATH" alvrrepack/headers/

# 4. Fix Library ID
install_name_tool -id "@rpath/libalvr_client_core.dylib" alvrrepack/libalvr_client_core.dylib

# 5. Create XCFramework
xcodebuild -create-xcframework \
  -library alvrrepack/libalvr_client_core.dylib \
  -headers alvrrepack/headers \
  -output ALVRClientCore.xcframework
