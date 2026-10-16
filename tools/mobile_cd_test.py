"""内部配信の停止条件と再実行時の採番を検証する。"""

import base64
import plistlib
from pathlib import Path
import tempfile
import unittest

from mobile_cd import REQUIRED, build_numbers, preflight, selection


class MobileCdTest(unittest.TestCase):
    def test_unconfigured_push_skips_but_manual_run_reports_missing_setup(self):
        self.assertEqual(selection("push", "both", "", "", "refs/heads/main"),
                         {"android": False, "ios": False})
        with self.assertRaisesRegex(ValueError, "MOBILE_IOS_ENABLED"):
            selection("workflow_dispatch", "both", "true", "false", "refs/heads/main")
        self.assertEqual(selection("workflow_dispatch", "android", "true", "false", "refs/heads/main"),
                         {"android": True, "ios": False})

    def test_other_branches_cannot_distribute(self):
        with self.assertRaisesRegex(ValueError, "main"):
            selection("workflow_dispatch", "both", "true", "true", "refs/heads/develop")

    def test_retry_and_next_run_have_distinct_increasing_numbers(self):
        first, retry, following = [build_numbers(*pair) for pair in (("1", "1"), ("1", "2"), ("2", "1"))]
        self.assertLess(int(first["android_build_number"]), int(retry["android_build_number"]))
        self.assertLess(int(retry["android_build_number"]), int(following["android_build_number"]))
        self.assertEqual(retry["ios_build_number"], "1.2")
        for run, attempt in (("0", "1"), ("1", "100"), ("10000", "1"), ("bad", "1")):
            with self.assertRaises(ValueError):
                build_numbers(run, attempt)

    def test_id_mismatch_and_invalid_credentials_fail_without_showing_secret(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "android/app/build.gradle.kts"
            target.parent.mkdir(parents=True)
            target.write_text('applicationId = "dev.example.mars"')
            env = {key: "configured" for key in REQUIRED["android"]}
            env.update(MOBILE_APP_IDENTIFIER="dev.example.other", ANDROID_KEYSTORE_BASE64="private-value!")
            with self.assertRaisesRegex(ValueError, "一致しません"):
                preflight("android", env, root)
            env["MOBILE_APP_IDENTIFIER"] = "dev.example.mars"
            with self.assertRaisesRegex(ValueError, "ANDROID_KEYSTORE_BASE64") as error:
                preflight("android", env, root)
            self.assertNotIn("private-value", str(error.exception))
            env["ANDROID_KEYSTORE_BASE64"] = base64.b64encode(b"sample").decode()
            preflight("android", env, root)

    def test_ios_requires_explicit_export_compliance_answer(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            project = root / "ios/Runner.xcodeproj/project.pbxproj"
            project.parent.mkdir(parents=True)
            project.write_text("PRODUCT_BUNDLE_IDENTIFIER = dev.example.mars;\n"
                               "PRODUCT_BUNDLE_IDENTIFIER = dev.example.mars.RunnerTests;")
            info = root / "ios/Runner/Info.plist"
            info.parent.mkdir(parents=True)
            info.write_bytes(plistlib.dumps({}))
            env = {key: base64.b64encode(b"sample").decode() for key in REQUIRED["ios"]}
            env["MOBILE_APP_IDENTIFIER"] = "dev.example.mars"
            with self.assertRaisesRegex(ValueError, "申告"):
                preflight("ios", env, root)
            info.write_bytes(plistlib.dumps({"ITSAppUsesNonExemptEncryption": False}))
            preflight("ios", env, root)

    def test_android_build_only_requires_id_and_signing_but_no_google_authorization(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "android/app/build.gradle.kts"
            target.parent.mkdir(parents=True)
            target.write_text('applicationId = "dev.example.mars"')
            env = {
                "MOBILE_APP_IDENTIFIER": "dev.example.mars",
                "ANDROID_KEYSTORE_BASE64": base64.b64encode(b"sample").decode(),
                "ANDROID_KEYSTORE_PASSWORD": "test-only",
                "ANDROID_KEY_ALIAS": "upload",
                "ANDROID_KEY_PASSWORD": "test-only",
            }
            preflight("android", env, root, build_only=True)
            with self.assertRaisesRegex(ValueError, "GOOGLE_WORKLOAD_IDENTITY_PROVIDER"):
                preflight("android", env, root)
            for key in env:
                missing = dict(env)
                missing.pop(key)
                with self.assertRaisesRegex(ValueError, key):
                    preflight("android", missing, root, build_only=True)
            with self.assertRaisesRegex(ValueError, "Android"):
                preflight("ios", env, root, build_only=True)


if __name__ == "__main__":
    unittest.main()
