#!/bin/bash
set -eu
cd "$(dirname "$0")/.."

CHECK_DIR=$(mktemp -d)
trap 'rm -rf "$CHECK_DIR"' EXIT
cp vectorscoperize/Shaders/ScopeShaders.metal "$CHECK_DIR/"
swiftc -parse-as-library "$@" -o "$CHECK_DIR/CheckScopes" \
    vectorscoperize/Configs/ScopeConstants.swift \
    vectorscoperize/Managers/AppState.swift \
    vectorscoperize/Managers/CaptureEngine.swift \
    vectorscoperize/Managers/ScopeRenderer.swift \
    vectorscoperize/UI/FloatingScopeWindow.swift \
    vectorscoperize/UI/GraticuleOverlayView.swift \
    vectorscoperize/UI/OverlaySelectionView.swift \
    scripts/CheckScopes.swift
"$CHECK_DIR/CheckScopes"
