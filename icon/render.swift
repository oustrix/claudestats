// Headless rasterizer for icon/AppIcon.html, using the WebKit that ships with
// macOS — no Chrome, no external tools. Loads the local HTML in an offscreen
// WKWebView and writes a transparent PNG.
//
//   swift icon/render.swift <fileURL-with-query> <cssSize> <outWidth> <out.png>
//
// cssSize is the tile's CSS size; outWidth is the pixel width of the PNG. A
// larger outWidth supersamples (the old Chrome path used device-scale-factor 4,
// i.e. cssSize 256 -> outWidth 1024), which keeps the 1px bevel highlights and
// the SVG glow crisp. Run via icon/build.sh, not by hand.

import AppKit
import WebKit

let args = CommandLine.arguments
guard args.count == 5,
      let url = URL(string: args[1]),
      let cssSize = Double(args[2]),
      let outWidth = Int(args[3]) else {
    FileHandle.standardError.write(
        Data("usage: render.swift <fileURL> <cssSize> <outWidth> <out.png>\n".utf8))
    exit(2)
}
let side = CGFloat(cssSize)
let outPath = args[4]

func die(_ message: String) -> Never {
    FileHandle.standardError.write(Data("render.swift: \(message)\n".utf8))
    exit(1)
}

final class Renderer: NSObject, WKNavigationDelegate {
    let side: CGFloat
    let outWidth: Int
    let outPath: String

    init(side: CGFloat, outWidth: Int, outPath: String) {
        self.side = side
        self.outWidth = outWidth
        self.outPath = outPath
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        // The artwork is painted synchronously on load; a short beat lets the
        // SVG drop-shadow filters settle before the snapshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: self.side, height: self.side)
            config.snapshotWidth = NSNumber(value: self.outWidth)
            webView.takeSnapshot(with: config) { image, error in
                guard let image, error == nil else {
                    die("snapshot failed: \(error?.localizedDescription ?? "unknown")")
                }
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else {
                    die("PNG encoding failed")
                }
                do {
                    try png.write(to: URL(fileURLWithPath: self.outPath))
                } catch {
                    die("write failed: \(error.localizedDescription)")
                }
                exit(0)
            }
        }
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        die("navigation failed: \(error.localizedDescription)")
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        die("load failed: \(error.localizedDescription)")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // offscreen, no Dock icon

let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: side, height: side))
webView.setValue(false, forKey: "drawsBackground") // transparent, not white
let renderer = Renderer(side: side, outWidth: outWidth, outPath: outPath)
webView.navigationDelegate = renderer

let readAccess = url.deletingLastPathComponent()
webView.loadFileURL(url, allowingReadAccessTo: readAccess)

app.run()
