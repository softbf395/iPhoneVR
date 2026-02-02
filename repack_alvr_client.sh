#!/bin/bash
set -e

# Path to the compiled Rust binary and headers
BUILDDIR="ALVR/target/aarch64-apple-ios/distribution"
HEADERPATH="ALVR/alvr_client_core.h"

# Clean old artifacts
rm -rf alvrrepack ALVRClientCore.xcframework || true

# Setup directory structure
mkdir -p alvrrepack/ios/headers
cp "$BUILDDIR/libalvr_client_core.dylib" alvrrepack/ios/
cp "$HEADERPATH" alvrrepack/ios/headers/

# Set the RPath so the app can find the dylib at runtime
install_name_tool -id "@rpath/libalvr_client_core.dylib" alvrrepack/ios/libalvr_client_core.dylib

# Create the XCFramework
# This wraps the library and headers into a format XcodeGen can easily consume
xcodebuild -create-xcframework \
    -library alvrrepack/ios/libalvr_client_core.dylib \
    -headers alvrrepack/ios/headers \
    -output ALVRClientCore.xcframework
