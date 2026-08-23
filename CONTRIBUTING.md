# Contributing to FastList

Thanks for helping improve FastList. This package is a small shared recycled-list
primitive: keep changes focused on native list mechanics, and leave app domain
behavior to callers.

## Development setup

1. Clone the repository and open `Package.swift` in Xcode, or use the SwiftPM CLI.
2. Run the macOS test suite:

   ```sh
   swift test
   ```

3. Lint Swift sources:

   ```sh
   swiftlint lint --strict
   ```

4. Lint Markdown with Vale (styles sync on first run):

   ```sh
   uvx vale@3.13.0.0 sync
   git ls-files '*.md' | xargs uvx vale@3.13.0.0
   ```

5. Build for the iOS Simulator when you touch the native SwiftUI backend:

   ```sh
   xcodebuild -scheme FastList \
     -destination 'generic/platform=iOS Simulator' \
     -derivedDataPath .build/ios-derived \
     CODE_SIGNING_ALLOWED=NO build
   ```

6. Try the demo:

   ```sh
   swift run FastListDemo
   ```

## Pull requests

- Prefer a focused change with a clear problem statement over a broad rewrite.
- Add or update tests next to the behavior you change.
- Link related GitHub issues with `Fixes #N` when the PR closes them.
- Avoid em dashes in prose; Vale enforces that for Markdown.

## Ownership boundary

FastList owns recycled rows, selection wiring, activation hooks, swipe and context
menu rendering, paging signals, and scroll-position reporting. Calling apps own
row layout, domain commands, menu construction, drag payload meaning, pagination
UI, and persisted scroll state.
