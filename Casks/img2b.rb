cask "img2b" do
  version "0.2.6"
  sha256 "1ecf542b23af8f61002b3931c92b59bcb9bf43f664d5c3c853ba9f03c7cfbe32"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
