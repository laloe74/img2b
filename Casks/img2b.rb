cask "img2b" do
  version "0.2.9"
  sha256 "ef359086b12044c92cbd3e9a8d8c1b427fe07c956d78c4b777729e19e212ad6d"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
