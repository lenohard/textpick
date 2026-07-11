cask "textpick" do
  version "1.0.0"
  sha256 "3471188532e906408adcd6216c976de47c23595d1b2fe3e80a716e9b0c12f1af"

  url "https://github.com/lenohard/textpick/releases/download/v#{version}/TextPick-#{version}.zip"
  name "TextPick"
  desc "Capture selected text and process it via LLM"
  homepage "https://github.com/lenohard/textpick"

  depends_on macos: ">= :ventura"

  app "TextPick.app"
end
