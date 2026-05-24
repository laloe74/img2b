# Changelog

## v0.1.0 — 2026-05-24

  - e326a06 Fix gh release create trailing backslash
  - cefd283 v1.3
  - 1f83ae7 v1.2
  - a4883a7 v1.1
  - c2a64d6 Remove --prerelease from release script
  - e46b381 Fix cask version sed in release script
  - 4075f9b v1.1
  - aa68d34 Fix settings sheet height to fit window
  - c2b246b Sidebar: plain Image List header, like Messages.app
  - 0c1092e Sidebar empty state: Image List
  - 25e3996 Wider default window, square drop zone, remote URL preview for old records
  - a6eaeef Persist image items across app launches (5s autosave + save on quit)
  - 16e387d Remove DMG generation from build script, only release.sh creates DMG
  - 6d860b6 Auto-migrate config from old Image2Blog directory
  - 0157fc1 Fix Homebrew install instructions
  - 40f40b0 Add Settings to app menu (Cmd+,), Homebrew cask, README, DMG in build script
  - be59331 DMG with Applications symlink in build scripts
  - 9537193 Add auto-update via GitHub Releases, DMG with Applications symlink
  - 357ee13 v1.0
  - 8e7aced Add release script and changelog
  - 6f166b7 Rename to img2b
  - 8aefc3a Image2Blog: macOS 26 native blog image hosting tool


## v1.3 — 2026-05-24

  - 1f83ae7 v1.2
  - a4883a7 v1.1
  - c2a64d6 Remove --prerelease from release script
  - e46b381 Fix cask version sed in release script
  - 4075f9b v1.1
  - aa68d34 Fix settings sheet height to fit window
  - c2b246b Sidebar: plain Image List header, like Messages.app
  - 0c1092e Sidebar empty state: Image List
  - 25e3996 Wider default window, square drop zone, remote URL preview for old records
  - a6eaeef Persist image items across app launches (5s autosave + save on quit)
  - 16e387d Remove DMG generation from build script, only release.sh creates DMG
  - 6d860b6 Auto-migrate config from old Image2Blog directory
  - 0157fc1 Fix Homebrew install instructions
  - 40f40b0 Add Settings to app menu (Cmd+,), Homebrew cask, README, DMG in build script
  - be59331 DMG with Applications symlink in build scripts
  - 9537193 Add auto-update via GitHub Releases, DMG with Applications symlink


## v1.2 — 2026-05-24

  - a4883a7 v1.1
  - c2a64d6 Remove --prerelease from release script
  - e46b381 Fix cask version sed in release script
  - 4075f9b v1.1
  - aa68d34 Fix settings sheet height to fit window
  - c2b246b Sidebar: plain Image List header, like Messages.app
  - 0c1092e Sidebar empty state: Image List
  - 25e3996 Wider default window, square drop zone, remote URL preview for old records
  - a6eaeef Persist image items across app launches (5s autosave + save on quit)
  - 16e387d Remove DMG generation from build script, only release.sh creates DMG
  - 6d860b6 Auto-migrate config from old Image2Blog directory
  - 0157fc1 Fix Homebrew install instructions
  - 40f40b0 Add Settings to app menu (Cmd+,), Homebrew cask, README, DMG in build script
  - be59331 DMG with Applications symlink in build scripts
  - 9537193 Add auto-update via GitHub Releases, DMG with Applications symlink


## v1.1 — 2026-05-24

  - c2a64d6 Remove --prerelease from release script
  - e46b381 Fix cask version sed in release script
  - 4075f9b v1.1
  - aa68d34 Fix settings sheet height to fit window
  - c2b246b Sidebar: plain Image List header, like Messages.app
  - 0c1092e Sidebar empty state: Image List
  - 25e3996 Wider default window, square drop zone, remote URL preview for old records
  - a6eaeef Persist image items across app launches (5s autosave + save on quit)
  - 16e387d Remove DMG generation from build script, only release.sh creates DMG
  - 6d860b6 Auto-migrate config from old Image2Blog directory
  - 0157fc1 Fix Homebrew install instructions
  - 40f40b0 Add Settings to app menu (Cmd+,), Homebrew cask, README, DMG in build script
  - be59331 DMG with Applications symlink in build scripts
  - 9537193 Add auto-update via GitHub Releases, DMG with Applications symlink


## v1.1 — 2026-05-24

  - aa68d34 Fix settings sheet height to fit window
  - c2b246b Sidebar: plain Image List header, like Messages.app
  - 0c1092e Sidebar empty state: Image List
  - 25e3996 Wider default window, square drop zone, remote URL preview for old records
  - a6eaeef Persist image items across app launches (5s autosave + save on quit)
  - 16e387d Remove DMG generation from build script, only release.sh creates DMG
  - 6d860b6 Auto-migrate config from old Image2Blog directory
  - 0157fc1 Fix Homebrew install instructions
  - 40f40b0 Add Settings to app menu (Cmd+,), Homebrew cask, README, DMG in build script
  - be59331 DMG with Applications symlink in build scripts
  - 9537193 Add auto-update via GitHub Releases, DMG with Applications symlink


## v1.0 — 2026-05-24

  - 8e7aced Add release script and changelog
  - 6f166b7 Rename to img2b
  - 8aefc3a Image2Blog: macOS 26 native blog image hosting tool


## v1.0 — 2026-05-24

- Drag-and-drop image upload with WebP conversion via libvips
- Cloudflare R2 / S3-compatible storage support
- Auto-rename: `img-{hash16}-{date}` pattern (customizable)
- TOML export with auto-append to file
- Uploaded URL auto-copied to clipboard
- Four default categories: design, photography, physics, typography
- macOS 26 native design with NavigationSplitView sidebar
- Click sidebar empty space to deselect (AppKit interop)
- Dashed drop zone with drag hover animation
- Configurable compression quality and target file size
- Settings saved to `~/Library/Application Support/img2b/config.json`
