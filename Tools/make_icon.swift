// Draws Resources/AppIcon.iconset from the sprite's sitting cat. To remake the icon:
//   swiftc Tools/make_icon.swift -o build/make_icon
//   build/make_icon Resources/Cat_Sprite_Sheet.png build/AppIcon.iconset
//   iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns

import AppKit

let args = CommandLine.arguments
let source = CGImageSourceCreateImageAtIndex(
    CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil)!, 0, nil)!
// The sitting cat occupies columns 10-21 and rows 20-31 of the first 32px frame.
let cat = source.cropping(to: CGRect(x: 9, y: 19, width: 14, height: 13))!
try FileManager.default.createDirectory(atPath: args[2], withIntermediateDirectories: true)

for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let size = points * scale
        let s = CGFloat(size)
        let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // Apple's icon grid: a rounded square inset by about a tenth.
        let inset = s * 0.098
        let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        c.addPath(CGPath(roundedRect: tile, cornerWidth: s * 0.18, cornerHeight: s * 0.18, transform: nil))
        c.setFillColor(CGColor(srgbRed: 0.13, green: 0.14, blue: 0.17, alpha: 1))
        c.fillPath()
        // Whole-pixel scale so the art stays crisp.
        let px = max(1, floor(tile.width * 0.72 / 14))
        c.interpolationQuality = .none
        c.draw(cat, in: CGRect(x: floor((s - 14 * px) / 2), y: floor((s - 13 * px) / 2), width: 14 * px, height: 13 * px))
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: args[2]).appendingPathComponent(name))
    }
}
