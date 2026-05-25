cask "img2b" do
  version "0.2.2"
  sha256 "50310fc04ed5f7969b3e72a9a38f99f6cb28d880c99549d6c6ce93575e2b83ff"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
