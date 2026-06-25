#!/usr/bin/env python3
"""Enforce the expected runner for each YamiboReader test target.

Core tests are SwiftPM-compatible and should be run with `swift test`.
UI tests require Xcode/iOS Simulator coverage and should be run with
`xcodebuild test`.
"""

from __future__ import annotations

import json
import shlex
import sys

CORE_TEST_TARGET = "YamiboReaderCoreTests"
UI_TEST_TARGET = "YamiboReaderUITests"

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


def _swift_token_index(tokens: list[str]) -> int | None:
    if not tokens:
        return None
    if tokens[0] == "swift":
        return 0
    if tokens[0] == "xcrun":
        try:
            return tokens.index("swift", 1)
        except ValueError:
            return None
    return None


def _xcodebuild_token_index(tokens: list[str]) -> int | None:
    if not tokens:
        return None
    if tokens[0] == "xcodebuild":
        return 0
    if tokens[0] == "xcrun":
        try:
            return tokens.index("xcodebuild", 1)
        except ValueError:
            return None
    return None


def _is_swiftpm_test(tokens: list[str]) -> bool:
    swift_index = _swift_token_index(tokens)
    if swift_index is None or len(tokens) <= swift_index + 1:
        return False

    if tokens[swift_index + 1] == "test":
        return True
    return (
        tokens[swift_index + 1] == "package"
        and len(tokens) > swift_index + 2
        and tokens[swift_index + 2] == "test"
    )


def _is_xcodebuild_test(tokens: list[str]) -> bool:
    xcodebuild_index = _xcodebuild_token_index(tokens)
    if xcodebuild_index is None:
        return False
    return "test" in tokens[xcodebuild_index + 1 :]


def _references_target(tokens: list[str], target: str) -> bool:
    path = f"Tests/{target}"
    return any(target in token or path in token for token in tokens)


def _deny_reason(tokens: list[str]) -> str | None:
    is_swiftpm_test = _is_swiftpm_test(tokens)
    is_xcodebuild_test = _is_xcodebuild_test(tokens)
    if not is_swiftpm_test and not is_xcodebuild_test:
        return None

    references_core = _references_target(tokens, CORE_TEST_TARGET)
    references_ui = _references_target(tokens, UI_TEST_TARGET)
    if references_core and references_ui:
        return (
            "Do not mix YamiboReaderCoreTests and YamiboReaderUITests in one "
            "test command. Run Core tests with `swift test --filter "
            "YamiboReaderCoreTests`, and UI tests with `xcodebuild test "
            "-only-testing:YamiboReaderUITests`."
        )

    if is_swiftpm_test:
        if references_core:
            return None
        if references_ui:
            return (
                "Blocked `swift test` for YamiboReaderUITests. Tests under "
                "`Tests/YamiboReaderUITests` must be run with `xcodebuild "
                "test` against an iOS Simulator."
            )
        return (
            "Blocked unscoped `swift test`. SwiftPM tests are allowed only "
            "when explicitly scoped to `YamiboReaderCoreTests`, for example "
            "`swift test --filter YamiboReaderCoreTests`."
        )

    if references_ui:
        return None
    if references_core:
        return (
            "Blocked `xcodebuild test` for YamiboReaderCoreTests. Tests under "
            "`Tests/YamiboReaderCoreTests` must be run with `swift test`."
        )
    return (
        "Blocked unscoped `xcodebuild test`. Xcode tests are allowed only "
        "when explicitly scoped to `YamiboReaderUITests`, for example "
        "`xcodebuild test -only-testing:YamiboReaderUITests`."
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
