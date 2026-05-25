cask "img2b" do
  version "0.2.3"
  sha256 "1bc561afa8b9873f22075287474ddb023b526aae445af4921405f6fbb66e14cf"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
