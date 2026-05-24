cask "img2b" do
  version "0.1.0"
  sha256 "63cf4709917c327ca026c26dc97e0dc8d5547cf0084436220511d14002fee15d"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
