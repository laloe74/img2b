cask "img2b" do
  version "0.2.10"
  sha256 "6c0488df601999b3be3a59b09fa80069ce92cb4322ecafde89b98a346358a159"

  url "https://github.com/laloe74/img2b/releases/download/v#{version}/img2b-v#{version}.dmg"
  name "img2b"
  desc "macOS blog image hosting tool — drag, compress, upload, TOML"
  homepage "https://github.com/laloe74/img2b"

app "img2b.app"

  zap trash: [
    "~/Library/Application Support/img2b",
  ]
end
