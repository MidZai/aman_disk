cask "aman-disk" do
  version "1.0.1"
  sha256 "2af8fc3c17ed74136d57426b516bf5fd76c7392d13ad0d55c70f9ec6588cfe9e"

  url "https://github.com/MidZai/aman_disk/releases/download/v#{version}/Aman-Disk-#{version}.dmg"
  name "Aman Disk"
  desc "Native, privacy-respecting drive health and performance monitor"
  homepage "https://github.com/MidZai/aman_disk"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Aman Disk.app"

  zap trash: [
    "~/Library/Application Support/io.github.aman-disk.AmanDisk",
    "~/Library/Caches/io.github.aman-disk.AmanDisk",
    "~/Library/Preferences/io.github.aman-disk.AmanDisk.plist",
  ]
end
