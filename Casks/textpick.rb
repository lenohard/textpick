cask "textpick" do
  version "1.0.0"
  sha256 "b649cf5af6842c6f446437ec80b482427ec18e7614ae72726f5810dffc77118a"

  url "https://github.com/lenohard/textpick/releases/download/v#{version}/TextPick-#{version}.zip"
  name "TextPick"
  desc "Capture selected text and process it via LLM"
  homepage "https://github.com/lenohard/textpick"

  depends_on macos: :ventura

  app "TextPick.app"
end
