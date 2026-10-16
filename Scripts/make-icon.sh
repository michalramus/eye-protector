#!/usr/bin/env bash
# Renders the app icon from Scripts/make-icon.swift into an .icns.
set -euo pipefail

cd "$(dirname "$0")/.."

swift Scripts/make-icon.swift
iconutil --convert icns Resources/EyeProtector.iconset --output Resources/EyeProtector.icns
rm -rf Resources/EyeProtector.iconset

echo "built Resources/EyeProtector.icns"
