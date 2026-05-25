# Changelog

## v0.2.5 — 2026-05-25

  - 17c8973 Honest file format: extension matches actual content


## v0.2.4 — 2026-05-25

  - 0dc761d R2 sync, delete fix, and preview polish


## v0.2.3 — 2026-05-25

  - 723c2b7 Shimmer skeleton loading in sidebar for processing/uploading items


## v0.2.2 — 2026-05-25

  - 661ec40 Preview loading states, progress animation, and fixed info bar height


## v0.2.1 — 2026-05-25

  - 90e5c82 Category toggle, upload flow, preview cache, and UI polish


## v0.2.0 — 2026-05-25

  - 8c17e73 Zipic-style 6-level compression: single-pass AVIF encode, width-only constraint


## v0.1.1 — 2026-05-25

  - 4511b8e Category system with icons, per-item category selection, clean toolbar layout
  - f8dccbc Batch select dropped items, persist cache to Application Support, Messages-style toolbar
  - aea99df AVIF encoding with HEIC fallback, gradual resize cascade, template-first TOML
  - 58c9bd9 Show original filename in sidebar, not HEIC name
  - 2be0a15 Quality floor Q75, resize to 2048px Q80
  - 877a39c Pre-resize to lossless PNG intermediate to preserve quality
  - 1c198eb Simplify: pure native List selection, no custom gestures
  - cb38bf7 Refactor click: Button for preview (always selects, never toggles), checkbox for multi-select
  - c116641 Fix flicker: native List selection for preview, custom checkbox for multi-select
  - 5739f9e Quality floor: never below Q65, never below 1920px
  - 61e6a11 Checkbox multi-select + detail area drop + click row to preview
  - 76a7e97 Fix: allow drag-drop during preview, skip Cmd/Shift clicks in sidebar monitor
  - 457e899 Separate previewItemID from selectedItemIDs to fix flash bug
  - f55cf1e Remove detail tap gesture causing crash, use native List selection
  - ca7d4bc Native List multi-select via Set<UUID> binding
  - c8398cf Checkbox multi-select instead of List selection
  - 20658bb Multi-select sidebar + batch delete. HEIC format for native encoding.
  - 8e8946a Fix variable names in R2Uploader after HEIC switch
  - b59431a Switch to HEIC format for reliable native encoding
  - 0af5c11 Pre-resize images over 4000px to avoid encoder limits
  - be20c55 Make processImage nonisolated, encode synchronous
  - 5d230b3 Add detailed error messages, fix Task.detached with Sendable Error
  - 0f3528e Remove Task.detached from encode, show original filename on error
  - 87f816a Remove manual color space conversion, let CGImageDestination handle it
  - aaec5ba Fix target size: multi-step quality reduction (80-60-40), resize 1920/1024 fallback
  - c9cb281 Add security-scoped URL access, restore quality option, RGB conversion
  - 628987f Fix AVIF: remove kCGImageDestinationLossyCompressionQuality, add RGB conversion
  - bd976c4 Fix native AVIF: use CGImageSourceCreateWithData, preserve color space
  - f346779 Switch to native AVIF encoding via CGImageDestination, zero external deps
  - c35fcba Switch output format from WebP to AVIF (heifsave --compression av1)


## v0.1.0 — 2026-05-24

- Initial release
- Drag-and-drop WebP conversion via libvips
- Cloudflare R2 / S3 upload with AWS Signature V4
- TOML export with auto-append to file
- Image list persistence across launches
- Auto-update via GitHub Releases
- Settings in app menu (Cmd+,)
- macOS 26 native NavigationSplitView sidebar
- Homebrew cask support
