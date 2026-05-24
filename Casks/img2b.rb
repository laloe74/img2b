cask "img2b" do
  version "0.1.1"
  sha256 "53fd784a04017098ada4fec064cbbb6730f84649c05db9d3ebe0d26e61e26c08"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
