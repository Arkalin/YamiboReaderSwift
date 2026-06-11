#!/usr/bin/env python3
"""Block accidental full `swift test` runs in this repository.

Codex should prefer focused tests during normal development. This hook denies
unfiltered SwiftPM test commands and lets the model choose a narrower
`swift test --filter ...` command.
"""

from __future__ import annotations

import json
import shlex
import sys


def _load_payload() -> dict:
    try:
        return json.load(sys.stdin)
    except Exception:
        return {}


def _command_from_payload(payload: dict) -> str:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return ""
    command = tool_input.get("command") or tool_input.get("cmd")
    return command if isinstance(command, str) else ""


def _is_full_swift_test(command: str) -> bool:
    try:
        tokens = shlex.split(command)
    except ValueError:
        return False

    if len(tokens) < 2 or tokens[0] != "swift" or tokens[1] != "test":
        return False

    allowed_scope_flags = {
        "--filter",
        "--skip",
        "--list-tests",
        "--show-codecov-path",
    }
    for token in tokens[2:]:
        if token in allowed_scope_flags:
            return False
        if token.startswith("--filter=") or token.startswith("--skip="):
            return False

    return True


def main() -> int:
    command = _command_from_payload(_load_payload())
    if not _is_full_swift_test(command):
        return 0

    reason = (
        "Blocked full `swift test` in YamiboReaderSwift. Run only necessary "
        "focused tests, for example `swift test --filter MangaReaderModelTests/"
        "testName`, and reserve the full suite for explicit user requests or "
        "release validation."
    )
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
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
