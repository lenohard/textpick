cask "textpick" do
  version "1.0.0"
  sha256 "a3a85441285239c733a8ace0a359b91d51bd7bed9ab7fa24188b57c02d0a6403"

  url "https://github.com/lenohard/textpick/releases/download/v#{version}/TextPick-#{version}.zip"
  name "TextPick"
  desc "Capture selected text and process it via LLM"
  homepage "https://github.com/lenohard/textpick"

  depends_on macos: ">= :ventura"

  app "TextPick.app"
end
