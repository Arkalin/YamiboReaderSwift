#!/usr/bin/env python3
"""Block tests that assert against source-code text.

This repository wants behavior tests, not tests that read files under Sources
and assert on implementation text or regex matches. The hook checks proposed
test-file writes before the tool runs.
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Iterable


SOURCE_FILE_ACCESS_PATTERNS = [
    re.compile(r"String\s*\(\s*contentsOf(?:File)?:"),
    re.compile(r"FileManager\s*\.\s*default"),
    re.compile(r"contentsOfDirectory\s*\("),
    re.compile(r"URL\s*\(\s*fileURLWithPath:"),
    re.compile(r"Bundle\s*\.\s*module\s*\.\s*url\s*\("),
]

SOURCE_PATH_PATTERNS = [
    re.compile(r"Sources/"),
    re.compile(r'"\s*Sources\s*"'),
    re.compile(r"\.swift\b"),
    re.compile(r"source(?:Code|Text|File|Files|Path|Paths)?", re.IGNORECASE),
]

ASSERTION_PATTERNS = [
    re.compile(r"#expect\s*\("),
    re.compile(r"XCTAssert\w*\s*\("),
    re.compile(r"\bassert\s*\("),
    re.compile(r"Issue\s*\.\s*record\s*\("),
]


def _load_payload() -> dict:
    try:
        return json.load(sys.stdin)
    except Exception:
        return {}


def _repo_root() -> Path:
    try:
        output = subprocess.check_output(
            ["git", "rev-parse", "--show-toplevel"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if output:
            return Path(output)
    except Exception:
        pass
    return Path.cwd()


def _tool_input(payload: dict) -> dict:
    tool_input = payload.get("tool_input")
    return tool_input if isinstance(tool_input, dict) else {}


def _normalize_path(path: str, repo_root: Path) -> str:
    candidate = Path(path)
    if not candidate.is_absolute():
        candidate = repo_root / candidate
    try:
        return candidate.resolve().relative_to(repo_root.resolve()).as_posix()
    except Exception:
        return candidate.as_posix()


def _is_project_test_file(path: str, repo_root: Path) -> bool:
    relative_path = _normalize_path(path, repo_root)
    return (
        relative_path.startswith("Tests/")
        and relative_path.endswith(".swift")
        and "/Fixtures/" not in relative_path
    )


def _candidate_texts(tool_input: dict) -> Iterable[tuple[str, str]]:
    file_path = tool_input.get("file_path") or tool_input.get("path")

    content = tool_input.get("content")
    if isinstance(file_path, str) and isinstance(content, str):
        yield file_path, content

    new_string = tool_input.get("new_string")
    if isinstance(file_path, str) and isinstance(new_string, str):
        yield file_path, new_string

    edits = tool_input.get("edits")
    if isinstance(file_path, str) and isinstance(edits, list):
        for edit in edits:
            if not isinstance(edit, dict):
                continue
            edit_text = edit.get("new_string") or edit.get("content")
            if isinstance(edit_text, str):
                yield file_path, edit_text


def _matches_any(patterns: list[re.Pattern[str]], text: str) -> bool:
    return any(pattern.search(text) for pattern in patterns)


def _looks_like_source_assertion_test(text: str) -> bool:
    reads_source_file = _matches_any(SOURCE_FILE_ACCESS_PATTERNS, text) and _matches_any(
        SOURCE_PATH_PATTERNS,
        text,
    )
    return reads_source_file and _matches_any(ASSERTION_PATTERNS, text)


def _deny(reason: str) -> None:
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": reason,
                    "additionalContext": reason,
                }
            },
            ensure_ascii=False,
        )
    )


def main() -> int:
    repo_root = _repo_root()
    for file_path, text in _candidate_texts(_tool_input(_load_payload())):
        if not _is_project_test_file(file_path, repo_root):
            continue
        if not _looks_like_source_assertion_test(text):
            continue

        _deny(
            "Blocked source-code assertion test. Do not write tests that read "
            "`Sources/**/*.swift` or scan source text and assert on implementation "
            "details. Test behavior through public APIs, domain models, or focused "
            "fixtures instead."
        )
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
