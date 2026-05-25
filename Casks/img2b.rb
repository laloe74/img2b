cask "img2b" do
  version "0.2.1"
  sha256 "cc3573251642fab7d734b38d72515838509da6240854d6315fa24c7c2c809bd7"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
