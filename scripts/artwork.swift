import AppKit
let args = CommandLine.arguments
if args[1] == "file-icon" {
    guard let image = NSImage(contentsOfFile: args[2]), NSWorkspace.shared.setIcon(image, forFile: args[3], options: []) else { fatalError("Custom icon failed") }
} else {
    guard let art = NSImage(contentsOfFile: args[2]) else { fatalError("Artwork missing") }
    let size = NSSize(width: 680, height: 560)
    let canvas = NSImage(size: size)
    canvas.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    art.draw(in: NSRect(x: 190, y: 220, width: 300, height: 300))
    func text(_ string: String, y: CGFloat, font: NSFont, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let width = (string as NSString).size(withAttributes: attributes).width
        (string as NSString).draw(at: NSPoint(x: (680-width)/2, y: y), withAttributes: attributes)
    }
    text("Pixovolt 1.1", y: 526, font: .systemFont(ofSize: 23, weight: .semibold), color: .black)
    text("→", y: 142, font: .systemFont(ofSize: 34, weight: .light), color: .darkGray)
    text("앱을 응용 프로그램 폴더로 드래그하세요", y: 56, font: .systemFont(ofSize: 15), color: .darkGray)
    text("Apple Silicon · macOS 13+", y: 30, font: .systemFont(ofSize: 12), color: .gray)
    canvas.unlockFocus()
    let bitmap = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
}
