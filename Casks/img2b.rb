cask "img2b" do
  version "0.2.5"
  sha256 "3ab271e4efe0853ffac6bb1e3bffd02a4f5bd181d9413009515299fc2087259e"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
