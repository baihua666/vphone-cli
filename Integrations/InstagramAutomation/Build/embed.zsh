#!/bin/zsh
set -euo pipefail
module_dir=${0:a:h:h}
target="$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/threads-automation"
if [[ " ${SWIFT_ACTIVE_COMPILATION_CONDITIONS:-} " != *' VPHONE_CUSTOM_THREADS_DESKTOP '* ]]; then
  rm -f "$target"
  exit 0
fi
VPHONE_CUSTOM_INSTAGRAM_AUTOMATION=1 VPHONE_CUSTOM_THREADS_AUTOMATION=1 /usr/bin/swift build \
  --package-path "$module_dir" --scratch-path "$module_dir/.build-launchpad" -c release --product instagram-test
/bin/cp "$module_dir/.build-launchpad/release/instagram-test" "$target"
/usr/bin/codesign --force --sign - "$target"
