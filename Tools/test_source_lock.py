import json
import tempfile
import unittest
from pathlib import Path

import source_lock


TARGET_SHA = "d4b7cc8a3c2ebc02f77383fcdcae8cf597426abd"


def valid_manifest():
    return {
        "schema_version": 1,
        "generated_at": "2026-08-16T16:39:00-07:00",
        "target_repo": "jonbiro/noop",
        "target_baseline": TARGET_SHA,
        "sources": [
            {
                "repo": "jonbiro/noop",
                "url": "https://github.com/jonbiro/noop",
                "branch": "main",
                "sha": TARGET_SHA,
                "permalink": f"https://github.com/jonbiro/noop/tree/{TARGET_SHA}",
                "commit_date": "2026-08-16T13:34:08Z",
                "role": "implementation target",
                "license": {
                    "status": "verified_file",
                    "spdx": "PolyForm-Noncommercial-1.0.0",
                    "artifact": "LICENSE",
                    "copy_policy": "review_required",
                    "notes": "Target repository license.",
                },
                "provenance": "clean",
            }
        ],
    }


class SourceLockTests(unittest.TestCase):
    def test_valid_manifest(self):
        self.assertEqual(source_lock.validate_manifest(valid_manifest()), [])

    def test_duplicate_repo_rejected(self):
        data = valid_manifest()
        data["sources"].append(dict(data["sources"][0]))
        errors = source_lock.validate_manifest(data)
        self.assertTrue(any("duplicate repository" in error for error in errors))

    def test_short_or_moving_sha_rejected(self):
        data = valid_manifest()
        data["sources"][0]["sha"] = "main"
        errors = source_lock.validate_manifest(data)
        self.assertTrue(any("moving refs and short SHAs are forbidden" in error for error in errors))

    def test_missing_license_cannot_be_adapted(self):
        data = valid_manifest()
        data["sources"][0]["license"] = {
            "status": "missing",
            "spdx": None,
            "artifact": None,
            "copy_policy": "adapt_with_notice",
            "notes": "No license file found.",
        }
        errors = source_lock.validate_manifest(data)
        self.assertTrue(any("may only be reference_only or clean_room_only" in error for error in errors))

    def test_permalink_must_pin_sha(self):
        data = valid_manifest()
        data["sources"][0]["permalink"] = "https://github.com/jonbiro/noop/tree/main"
        errors = source_lock.validate_manifest(data)
        self.assertTrue(any("must be pinned to the exact SHA" in error for error in errors))

    def test_load_and_cli(self):
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "source-lock.json"
            path.write_text(json.dumps(valid_manifest()), encoding="utf-8")
            loaded = source_lock.load_manifest(path)
            self.assertEqual(loaded["target_baseline"], TARGET_SHA)
            self.assertEqual(source_lock.main([str(path)]), 0)


if __name__ == "__main__":
    unittest.main()
