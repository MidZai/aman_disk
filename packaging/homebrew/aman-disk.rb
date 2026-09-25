cask "aman-disk" do
  version "1.0.0"
  sha256 :no_check # Remplacez par le sha256 du fichier DMG généré lors de la publication de la release

  url "https://github.com/MidZai/aman_disk/releases/download/v#{version}/Aman.Disk-#{version}.dmg"
  name "Aman Disk"
  desc "Application native et respectueuse de la vie privée pour surveiller l'état et les performances de vos disques sur macOS"
  homepage "https://github.com/MidZai/aman_disk"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: ">= :sonoma"

  app "Aman Disk.app"

  zap trash: [
    "~/Library/Application Support/io.github.aman-disk.AmanDisk",
    "~/Library/Caches/io.github.aman-disk.AmanDisk",
    "~/Library/Preferences/io.github.aman-disk.AmanDisk.plist",
  ]
end
