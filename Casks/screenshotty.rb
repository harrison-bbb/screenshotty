cask "screenshotty" do
  version :latest
  sha256 :no_check

  url "https://github.com/harrison-bbb/screenshotty/releases/latest/download/Screenshotty.zip"
  name "Screenshotty"
  desc "Beautiful, perfectly centred screenshots with backgrounds"
  homepage "https://github.com/harrison-bbb/screenshotty"

  depends_on macos: ">= :sonoma"

  app "Screenshotty.app"

  # Builds are ad-hoc signed (no paid Apple Developer account), so clear the quarantine flag.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/Screenshotty.app"]
  end

  zap trash: [
    "~/Library/Application Support/Screenshotty",
    "~/Library/Preferences/com.screenshotty.app.plist",
  ]
end
