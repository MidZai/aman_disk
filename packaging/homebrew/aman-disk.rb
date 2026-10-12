cask "aman-disk" do
  version "1.0.0"
  sha256 :no_check # replace with the DMG sha256 at release time

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
