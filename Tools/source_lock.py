#!/usr/bin/env python3
"""Validate the evidence-source lock used by the hardening program.

This validator is intentionally network-free. It checks that every external source
has been frozen to an immutable Git commit and that licensing/provenance policy is
explicit before a contributor relies on it.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

SHA_RE = re.compile(r"^[0-9a-f]{40}$")
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
LICENSE_STATUSES = {"verified_file", "readme_only", "missing"}
COPY_POLICIES = {
    "adapt_with_notice",
    "review_required",
    "reference_only",
    "clean_room_only",
}
PROVENANCE = {"clean", "mixed", "decompiled_origin", "unknown"}


def _iso8601(value: str, field: str, errors: list[str]) -> None:
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except (TypeError, ValueError):
        errors.append(f"{field}: expected an ISO-8601 timestamp, got {value!r}")


def validate_manifest(data: dict[str, Any]) -> list[str]:
    errors: list[str] = []

    if data.get("schema_version") != 1:
        errors.append("schema_version: expected 1")

    generated_at = data.get("generated_at")
    if not isinstance(generated_at, str):
        errors.append("generated_at: required string")
    else:
        _iso8601(generated_at, "generated_at", errors)

    target_repo = data.get("target_repo")
    if not isinstance(target_repo, str) or not REPO_RE.fullmatch(target_repo):
        errors.append("target_repo: expected owner/name")

    target_baseline = data.get("target_baseline")
    if not isinstance(target_baseline, str) or not SHA_RE.fullmatch(target_baseline):
        errors.append("target_baseline: must be an immutable 40-character lowercase commit SHA")

    sources = data.get("sources")
    if not isinstance(sources, list) or not sources:
        errors.append("sources: expected a non-empty list")
        return errors

    seen: set[str] = set()
    target_seen = False
    for i, source in enumerate(sources):
        prefix = f"sources[{i}]"
        if not isinstance(source, dict):
            errors.append(f"{prefix}: expected object")
            continue

        repo = source.get("repo")
        if not isinstance(repo, str) or not REPO_RE.fullmatch(repo):
            errors.append(f"{prefix}.repo: expected owner/name")
            continue
        if repo in seen:
            errors.append(f"{prefix}.repo: duplicate repository {repo}")
        seen.add(repo)
        if repo == target_repo:
            target_seen = True

        expected_url = f"https://github.com/{repo}"
        if source.get("url") != expected_url:
            errors.append(f"{prefix}.url: expected canonical URL {expected_url}")

        branch = source.get("branch")
        if not isinstance(branch, str) or not branch.strip():
            errors.append(f"{prefix}.branch: required non-empty string")

        sha = source.get("sha")
        if not isinstance(sha, str) or not SHA_RE.fullmatch(sha):
            errors.append(
                f"{prefix}.sha: must be an immutable 40-character lowercase commit SHA; moving refs and short SHAs are forbidden"
            )
        elif source.get("permalink") != f"https://github.com/{repo}/tree/{sha}":
            errors.append(f"{prefix}.permalink: must be pinned to the exact SHA")

        commit_date = source.get("commit_date")
        if not isinstance(commit_date, str):
            errors.append(f"{prefix}.commit_date: required string")
        else:
            _iso8601(commit_date, f"{prefix}.commit_date", errors)

        role = source.get("role")
        if not isinstance(role, str) or not role.strip():
            errors.append(f"{prefix}.role: required non-empty string")

        license_info = source.get("license")
        if not isinstance(license_info, dict):
            errors.append(f"{prefix}.license: expected object")
        else:
            status = license_info.get("status")
            policy = license_info.get("copy_policy")
            artifact = license_info.get("artifact")
            if status not in LICENSE_STATUSES:
                errors.append(f"{prefix}.license.status: expected one of {sorted(LICENSE_STATUSES)}")
            if policy not in COPY_POLICIES:
                errors.append(f"{prefix}.license.copy_policy: expected one of {sorted(COPY_POLICIES)}")
            if status == "verified_file" and not isinstance(artifact, str):
                errors.append(f"{prefix}.license.artifact: verified_file requires a license artifact path or URL")
            if status in {"readme_only", "missing"} and policy not in {"reference_only", "clean_room_only"}:
                errors.append(
                    f"{prefix}.license.copy_policy: {status} sources may only be reference_only or clean_room_only"
                )

        provenance = source.get("provenance")
        if provenance not in PROVENANCE:
            errors.append(f"{prefix}.provenance: expected one of {sorted(PROVENANCE)}")
        elif provenance == "decompiled_origin":
            policy = license_info.get("copy_policy") if isinstance(license_info, dict) else None
            if policy != "clean_room_only":
                errors.append(f"{prefix}: decompiled_origin requires clean_room_only policy")

    if isinstance(target_repo, str) and not target_seen:
        errors.append("sources: target_repo must appear in the pinned source list")

    return errors


def load_manifest(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise ValueError("manifest root must be a JSON object")
    return data


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "manifest",
        nargs="?",
        type=Path,
        default=Path("docs/hardening/source-lock.json"),
        help="source-lock JSON to validate (default: docs/hardening/source-lock.json)",
    )
    args = parser.parse_args(argv)

    try:
        data = load_manifest(args.manifest)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"source-lock: could not read {args.manifest}: {exc}", file=sys.stderr)
        return 2

    errors = validate_manifest(data)
    if errors:
        print(f"source-lock: FAILED ({len(errors)} problem{'s' if len(errors) != 1 else ''})", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    print(f"source-lock: OK ({len(data['sources'])} pinned sources)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
