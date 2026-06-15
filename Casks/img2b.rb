cask "img2b" do
  version "0.2.11"
  sha256 "84effe5fd61d557baf848af93bc1b4562aa5d8d1cd8a7c2558ca0ddc9db9abd6"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

  depends_on macos: ">= :sequoia"

  app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
