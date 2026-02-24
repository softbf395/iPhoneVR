#!/bin/bash
set -e

# 1. Dynamically find the dylib (ignores whether it's /release or /distribution)
echo "Searching for libalvr_client_core.dylib..."
DYLIB_PATH=$(find ALVR/target/aarch64-apple-ios -name "libalvr_client_core.dylib" | head -n 1)

if [ -z "$DYLIB_PATH" ]; then
    echo "ERROR: libalvr_client_core.dylib not found anywhere in ALVR/target/aarch64-apple-ios"
    exit 1
fi
echo "Found dylib at: $DYLIB_PATH"

# 2. Dynamically find the header
echo "Searching for alvr_client_core.h..."
HEADER_PATH=$(find . -name "alvr_client_core.h" | head -n 1)

if [ -z "$HEADER_PATH" ]; then
    echo "ERROR: alvr_client_core.h not found. cbindgen likely failed."
    exit 1
fi
echo "Found header at: $HEADER_PATH"

# 3. Prepare the workspace
rm -rf alvrrepack ALVRClientCore.xcframework || true
mkdir -p alvrrepack/headers

# 4. Copy found files into a predictable structure
cp "$DYLIB_PATH" alvrrepack/libalvr_client_core.dylib
cp "$HEADER_PATH" alvrrepack/headers/

# 5. Fix the runtime path
install_name_tool -id "@rpath/libalvr_client_core.dylib" alvrrepack/libalvr_client_core.dylib

# 6. Create the framework
xcodebuild -create-xcframework \
  -library alvrrepack/libalvr_client_core.dylib \
  -headers alvrrepack/headers \
  -output ALVRClientCore.xcframework

echo "Successfully created ALVRClientCore.xcframework"
