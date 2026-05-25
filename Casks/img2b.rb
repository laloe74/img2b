cask "img2b" do
  version "0.2.8"
  sha256 "e826a3f8f4357b372a3bc9466a71a772c99fed4647f2274485f9f629b4579d37"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
