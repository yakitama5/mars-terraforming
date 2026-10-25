#!/usr/bin/env bash
set -euo pipefail
dart run tools/check_architecture.dart
dart tools/verify_research.dart
dart tools/verify_map_buildings.dart
python3 -m unittest discover -s tools -p mobile_cd_test.py
dart format --output=none --set-exit-if-changed lib test integration_test tools test_driver hook
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub
