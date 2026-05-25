cask "img2b" do
  version "0.2.7"
  sha256 "d0b81e1104556d39bb1ad78301f9382314b681f4af2d44f9f85d2108c95d947f"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
