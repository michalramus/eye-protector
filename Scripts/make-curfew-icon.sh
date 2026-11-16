#!/usr/bin/env bash
# Renders the Curfew app icon from Scripts/make-curfew-icon.swift into an .icns.
set -euo pipefail

cd "$(dirname "$0")/.."

swift Scripts/make-curfew-icon.swift
iconutil --convert icns Resources/Curfew.iconset --output Resources/Curfew.icns
rm -rf Resources/Curfew.iconset

echo "built Resources/Curfew.icns"
