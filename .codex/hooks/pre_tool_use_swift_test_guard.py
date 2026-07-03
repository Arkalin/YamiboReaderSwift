#!/usr/bin/env python3
"""Block SwiftPM test runs for YamiboReader.

All project tests should run through the shared Xcode test plan with
`xcodebuild test`. This avoids the macOS SwiftPM path and keeps Core and UI
tests on the same iOS Simulator configuration.
"""

from __future__ import annotations

import json
import shlex
import sys
from pathlib import PurePath

CONTROL_TOKENS = {"&&", "||", ";", "|"}


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


def _command_segments(command: str) -> list[list[str]]:
    try:
        tokens = shlex.split(command)
    except ValueError:
        return []

    segments: list[list[str]] = []
    current: list[str] = []
    for token in tokens:
        if token in CONTROL_TOKENS:
            if current:
                segments.append(current)
                current = []
            continue
        current.append(token)

    if current:
        segments.append(current)
    return segments


def _looks_like_environment_assignment(token: str) -> bool:
    if "=" not in token:
        return False
    name, _, _ = token.partition("=")
    return bool(name) and all(character.isalnum() or character == "_" for character in name)


def _command_tokens(tokens: list[str]) -> list[str]:
    index = 0
    while index < len(tokens) and _looks_like_environment_assignment(tokens[index]):
        index += 1
    if index < len(tokens) and tokens[index] == "env":
        index += 1
        while index < len(tokens) and _looks_like_environment_assignment(tokens[index]):
            index += 1
    return tokens[index:]


def _command_name(token: str) -> str:
    return PurePath(token).name


def _swift_token_index(tokens: list[str]) -> int | None:
    command_tokens = _command_tokens(tokens)
    if not command_tokens:
        return None
    if _command_name(command_tokens[0]) == "swift":
        return 0
    if _command_name(command_tokens[0]) == "xcrun":
        for index, token in enumerate(command_tokens[1:], start=1):
            if _command_name(token) == "swift":
                return index
    return None


def _is_swiftpm_test(tokens: list[str]) -> bool:
    command_tokens = _command_tokens(tokens)
    swift_index = _swift_token_index(command_tokens)
    if swift_index is None or len(command_tokens) <= swift_index + 1:
        return False

    if command_tokens[swift_index + 1] == "test":
        return True
    return (
        command_tokens[swift_index + 1] == "package"
        and len(command_tokens) > swift_index + 2
        and command_tokens[swift_index + 2] == "test"
    )


def _deny_reason(tokens: list[str]) -> str | None:
    is_swiftpm_test = _is_swiftpm_test(tokens)
    if not is_swiftpm_test:
        return None

    return (
        "Blocked `swift test`. YamiboReader tests must run through the Xcode "
        "test plan, for example `xcodebuild test -project YamiboReader.xcodeproj "
        "-scheme YamiboReader -testPlan YamiboReaderTests -destination "
        "'platform=iOS Simulator,name=iPhone 16' -collect-test-diagnostics never "
        "CODE_SIGNING_ALLOWED=NO`."
    )


def main() -> int:
    command = _command_from_payload(_load_payload())
    for segment in _command_segments(command):
        reason = _deny_reason(segment)
        if reason is None:
            continue
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

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
