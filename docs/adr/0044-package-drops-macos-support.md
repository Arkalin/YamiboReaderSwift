# Package drops macOS support

YamiboReader's Swift package will no longer support macOS 14 as a package platform; the current app implementation and the Nuke image migration may treat iOS as the supported platform. This avoids spending migration effort preserving macOS compile paths for image loading, NukeUI display adapters, and reader presentation code that is not part of the supported product surface.

## Status

Accepted.

## Consequences

The implementation should remove the `.macOS(.v14)` package platform declaration and perform a repository-wide iOS-only cleanup rather than limiting cleanup to files touched by the Nuke migration. AppKit imports, macOS color/image branches, macOS fallback views, and platform conditionals that exist only to keep the package compiling on macOS should be removed or simplified to their iOS behavior.

Shared Core code should still avoid UIKit-only dependencies unless the module responsibility is explicitly platform-specific, but macOS compile compatibility is no longer an acceptance requirement for the package. The cleanup should be verified against the supported iOS build and test surface rather than preserving host-macOS SwiftPM compatibility.

This cleanup should be implemented as an independent prerequisite before the Nuke image migration. Keeping the iOS-only cleanup separate from the image-pipeline replacement makes regressions attributable to either platform cleanup or Nuke integration instead of mixing both risk surfaces in one change.
