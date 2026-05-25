cask "img2b" do
  version "0.2.0"
  sha256 "ed2f2a7deb4b73bc9fa625fe576aa18399f55b9a41e6b0ed05185ab5d18902f9"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
