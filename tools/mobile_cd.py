#!/usr/bin/env python3
"""内部配信の選択・入力検証。秘密値は表示しない。"""

import argparse
import base64
import binascii
import os
from pathlib import Path
import plistlib
import re
import sys


ROOT = Path(__file__).resolve().parents[1]
ANDROID_BUILD_REQUIRED = (
    "MOBILE_APP_IDENTIFIER", "ANDROID_KEYSTORE_BASE64", "ANDROID_KEYSTORE_PASSWORD",
    "ANDROID_KEY_ALIAS", "ANDROID_KEY_PASSWORD",
)
REQUIRED = {
    "android": ANDROID_BUILD_REQUIRED + (
        "GOOGLE_WORKLOAD_IDENTITY_PROVIDER", "GOOGLE_PLAY_SERVICE_ACCOUNT",
    ),
    "ios": (
        "MOBILE_APP_IDENTIFIER", "IOS_TEAM_ID", "ASC_KEY_ID", "ASC_ISSUER_ID",
        "IOS_TESTFLIGHT_GROUP", "IOS_DISTRIBUTION_P12_BASE64",
        "IOS_DISTRIBUTION_P12_PASSWORD", "IOS_PROVISION_PROFILE_BASE64",
        "ASC_PRIVATE_KEY_BASE64",
    ),
}
FILES = {
    "android": {"ANDROID_KEYSTORE_BASE64": ("upload.jks", "ANDROID_KEYSTORE_PATH")},
    "ios": {
        "IOS_DISTRIBUTION_P12_BASE64": ("distribution.p12", "IOS_DISTRIBUTION_P12_PATH"),
        "IOS_PROVISION_PROFILE_BASE64": ("app.mobileprovision", "IOS_PROVISION_PROFILE_PATH"),
        "ASC_PRIVATE_KEY_BASE64": ("asc.p8", "ASC_PRIVATE_KEY_PATH"),
    },
}


def selection(event, platform, android_enabled, ios_enabled, ref):
    if ref != "refs/heads/main":
        raise ValueError("内部配信は main ブランチだけで実行できます。")
    enabled = {"android": android_enabled == "true", "ios": ios_enabled == "true"}
    requested = ("android", "ios") if platform == "both" else (platform,)
    if event == "workflow_dispatch":
        missing = [f"MOBILE_{name.upper()}_ENABLED=true" for name in requested if not enabled[name]]
        if missing:
            raise ValueError("ストア初期設定後に有効化してください: " + ", ".join(missing))
    return {name: enabled[name] and name in requested for name in enabled}


def build_numbers(run, attempt):
    if not run.isdecimal() or not attempt.isdecimal():
        raise ValueError("GitHub の実行番号が必要です。")
    run_number, run_attempt = int(run), int(attempt)
    if not 1 <= run_number <= 9999 or not 1 <= run_attempt <= 99:
        raise ValueError("実行番号が採番範囲を超えました。配信番号の移行が必要です。")
    # Retry gets a new number; an older workflow must not overwrite a newer one.
    return {"android_build_number": str(run_number * 100 + run_attempt),
            "ios_build_number": f"{run_number}.{run_attempt}"}


def preflight(platform, env, root=ROOT, *, build_only=False):
    if build_only and platform != "android":
        raise ValueError("--build-only は Android の初回ビルド専用です。")
    required = ANDROID_BUILD_REQUIRED if build_only else REQUIRED[platform]
    missing = [key for key in required if not env.get(key, "").strip()]
    if missing:
        raise ValueError("不足している設定: " + ", ".join(missing))
    identifier = env["MOBILE_APP_IDENTIFIER"]
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*(?:\.[A-Za-z][A-Za-z0-9]*){2,}", identifier):
        raise ValueError("MOBILE_APP_IDENTIFIER の形式が不正です。")
    if identifier.startswith("com.example."):
        raise ValueError("製品用のアプリ識別子を先に設定してください。")
    if platform == "android":
        source = (root / "android/app/build.gradle.kts").read_text()
        match = re.search(r'applicationId\s*=\s*"([^"]+)"', source)
        if not match or match.group(1) != identifier:
            raise ValueError("Android の applicationId とストア登録 ID が一致しません。")
    else:
        source = (root / "ios/Runner.xcodeproj/project.pbxproj").read_text()
        identifiers = {value.strip('" ') for value in re.findall(
            r"PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);", source)}
        app_ids = {value for value in identifiers if not value.endswith(".RunnerTests")}
        if app_ids != {identifier}:
            raise ValueError("iOS の Bundle ID とストア登録 ID が一致しません。")
        info = plistlib.loads((root / "ios/Runner/Info.plist").read_bytes())
        if not isinstance(info.get("ITSAppUsesNonExemptEncryption"), bool):
            raise ValueError("Info.plist の暗号化に関する申告を明示してください。")
    for key in FILES[platform]:
        try:
            if not base64.b64decode(env[key], validate=True):
                raise ValueError()
        except (ValueError, binascii.Error):
            raise ValueError(f"{key} の Base64 が不正です。") from None


def emit(values):
    output = os.environ.get("GITHUB_OUTPUT")
    lines = "".join(f"{key}={str(value).lower() if isinstance(value, bool) else value}\n"
                    for key, value in values.items())
    if output:
        with open(output, "a") as handle:
            handle.write(lines)
    else:
        print(lines, end="")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("select", "numbers", "preflight", "materialize"))
    parser.add_argument("platform", nargs="?", choices=("android", "ios"))
    parser.add_argument("--build-only", action="store_true",
                        help="Android の初回署名ビルド用。Google Play API 設定を要求しない。")
    args = parser.parse_args()
    if args.build_only and (args.command not in ("preflight", "materialize") or args.platform != "android"):
        parser.error("--build-only は preflight/materialize android で指定してください。")
    if args.command == "select":
        emit(selection(os.environ.get("GITHUB_EVENT_NAME"),
                       os.environ.get("REQUESTED_PLATFORM", "both"),
                       os.environ.get("MOBILE_ANDROID_ENABLED"),
                       os.environ.get("MOBILE_IOS_ENABLED"),
                       os.environ.get("GITHUB_REF")))
    elif args.command == "numbers":
        emit(build_numbers(os.environ.get("GITHUB_RUN_NUMBER", ""),
                           os.environ.get("GITHUB_RUN_ATTEMPT", "")))
    elif args.platform is None:
        parser.error("android または ios を指定してください。")
    else:
        preflight(args.platform, os.environ, build_only=args.build_only)
        if args.command == "materialize":
            directory = Path(os.environ["RUNNER_TEMP"]) / "mars-mobile-signing"
            directory.mkdir(mode=0o700, parents=True, exist_ok=True)
            with open(os.environ["GITHUB_ENV"], "a") as handle:
                for key, (filename, path_key) in FILES[args.platform].items():
                    target = directory / filename
                    with open(target, "wb", opener=lambda path, flags: os.open(path, flags, 0o600)) as binary:
                        binary.write(base64.b64decode(os.environ[key], validate=True))
                    handle.write(f"{path_key}={target}\n")
        print(f"{args.platform}: 設定の検証が完了しました。")


if __name__ == "__main__":
    try:
        main()
    except ValueError as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
