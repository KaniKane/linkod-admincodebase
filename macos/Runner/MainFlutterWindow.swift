import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    styleMask.remove(.resizable)
    styleMask.remove(.miniaturizable)
    collectionBehavior.insert(.fullScreenPrimary)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    if let screenFrame = screen?.frame {
      setFrame(screenFrame, display: true)
    }
    toggleFullScreen(nil)
  }
}
