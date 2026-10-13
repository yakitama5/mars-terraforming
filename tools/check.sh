#!/usr/bin/env bash
set -euo pipefail
dart run tools/check_architecture.dart
dart format --output=none --set-exit-if-changed lib test integration_test tools test_driver
flutter --no-version-check analyze --no-pub
flutter --no-version-check test --no-pub
