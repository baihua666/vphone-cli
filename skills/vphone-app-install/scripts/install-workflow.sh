#!/bin/zsh
set -euo pipefail
SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vphone-install-workflow.XXXXXXXX")"
trap 'rm -f "$BUILD_DIR/workflow"; rmdir "$BUILD_DIR"' EXIT
/usr/bin/xcrun swiftc -swift-version 6 -parse-as-library \
  "$SCRIPT_DIR/InstallWorkflow.swift" "$SCRIPT_DIR/../tests/InstallWorkflowTests.swift" -o "$BUILD_DIR/workflow"
VPHONE_INSTALL_SCRIPTS="$SCRIPT_DIR" "$BUILD_DIR/workflow" "$@"
