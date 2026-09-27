#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
export CLANG_MODULE_CACHE_PATH="$project_dir/.module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_dir/.module-cache"
swift build --configuration release --arch arm64
binary_dir="$(swift build --configuration release --arch arm64 --show-bin-path)"
output_dir="${SHUTTER_LOVER_BUILD_DIR:-$project_dir/build}"
bundle="$output_dir/Shutter Loved.app"
previous_bundle="$output_dir/Shutter Lover.app"
if [[ -d "$previous_bundle" && ! -e "$bundle" ]]; then
  mv "$previous_bundle" "$bundle"
fi
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$binary_dir/ShutterLover" "$bundle/Contents/MacOS/ShutterLover"
cp Configuration/Info.plist "$bundle/Contents/Info.plist"
cp ../LICENSE "$bundle/Contents/Resources/LICENSE"
swift scripts/make-icon.swift "$project_dir/build"
iconutil -c icns "$project_dir/build/AppIcon.iconset" -o "$bundle/Contents/Resources/AppIcon.icns"
codesign --force --sign - --options runtime --entitlements Configuration/ShutterLover.entitlements "$bundle"
codesign --verify --deep --strict "$bundle"
print "Built local development app: $bundle"
print "This ad-hoc signed alpha is not notarized for distribution."
