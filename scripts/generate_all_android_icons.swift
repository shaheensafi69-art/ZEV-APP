import Cocoa
import CoreGraphics

func run() {
    let baseDir = "/Users/Safi_Sahib/zev-app"
    let iconPath = "\(baseDir)/assets/icon/icon-1024x1024.png"
    
    guard let srcImage = NSImage(contentsOfFile: iconPath) else {
        print("Error: Could not load \(iconPath)")
        return
    }
    
    var srcRect = CGRect(origin: .zero, size: srcImage.size)
    guard let cgSrc = srcImage.cgImage(forProposedRect: &srcRect, context: nil, hints: nil) else {
        print("Error: Could not get CGImage from \(iconPath)")
        return
    }

    let densities: [(name: String, legacySize: Int, adaptiveSize: Int, notifSize: Int)] = [
        ("mdpi", 48, 108, 24),
        ("hdpi", 72, 162, 36),
        ("xhdpi", 96, 216, 48),
        ("xxhdpi", 144, 324, 72),
        ("xxxhdpi", 192, 432, 96)
    ]

    func savePng(_ image: CGImage, to path: String) {
        let rep = NSBitmapImageRep(cgImage: image)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("Wrote \(path) (\(image.width)x\(image.height))")
        }
    }

    // 1. Create mipmap-anydpi-v26 folder
    let anydpiDir = "\(baseDir)/android/app/src/main/res/mipmap-anydpi-v26"
    try? FileManager.default.createDirectory(atPath: anydpiDir, withIntermediateDirectories: true)

    // 2. Generate launcher icons for each density
    for d in densities {
        let mipmapDir = "\(baseDir)/android/app/src/main/res/mipmap-\(d.name)"
        let drawableDir = "\(baseDir)/android/app/src/main/res/drawable-\(d.name)"
        try? FileManager.default.createDirectory(atPath: mipmapDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: drawableDir, withIntermediateDirectories: true)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

        // A. Standard ic_launcher (full bleed)
        if let ctx = CGContext(data: nil, width: d.legacySize, height: d.legacySize, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.interpolationQuality = .high
            ctx.draw(cgSrc, in: CGRect(x: 0, y: 0, width: d.legacySize, height: d.legacySize))
            if let img = ctx.makeImage() {
                savePng(img, to: "\(mipmapDir)/ic_launcher.png")
            }
        }

        // B. Circular ic_launcher_round (pure circle with transparent background)
        if let ctx = CGContext(data: nil, width: d.legacySize, height: d.legacySize, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.interpolationQuality = .high
            let circleRect = CGRect(x: 0, y: 0, width: d.legacySize, height: d.legacySize)
            ctx.addEllipse(in: circleRect)
            ctx.clip()
            ctx.draw(cgSrc, in: circleRect)
            if let img = ctx.makeImage() {
                savePng(img, to: "\(mipmapDir)/ic_launcher_round.png")
            }
        }

        // C. Adaptive Foreground (108dp base canvas, icon fits in central 66% viewport = safe zone)
        if let ctx = CGContext(data: nil, width: d.adaptiveSize, height: d.adaptiveSize, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.interpolationQuality = .high
            // Scale icon to 70% of canvas and center it
            let iconW = Double(d.adaptiveSize) * 0.70
            let iconH = Double(d.adaptiveSize) * 0.70
            let iconX = (Double(d.adaptiveSize) - iconW) / 2.0
            let iconY = (Double(d.adaptiveSize) - iconH) / 2.0
            
            // Round corners of the foreground artwork for smooth adaptive rendering
            let innerRect = CGRect(x: iconX, y: iconY, width: iconW, height: iconH)
            let path = CGPath(roundedRect: innerRect, cornerWidth: iconW * 0.22, cornerHeight: iconH * 0.22, transform: nil)
            ctx.addPath(path)
            ctx.clip()
            ctx.draw(cgSrc, in: innerRect)
            
            if let img = ctx.makeImage() {
                savePng(img, to: "\(drawableDir)/ic_launcher_foreground.png")
            }
        }

        // D. Notification Icon (White silhouette on transparent background)
        if let ctx = CGContext(data: nil, width: d.notifSize, height: d.notifSize, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.interpolationQuality = .high

            // Draw crisp white ZEV Z logo and play triangle
            let s = Double(d.notifSize)
            let path = CGMutablePath()
            // Z shape
            path.move(to: CGPoint(x: s * 0.16, y: s * 0.18))
            path.addLine(to: CGPoint(x: s * 0.84, y: s * 0.18))
            path.addLine(to: CGPoint(x: s * 0.84, y: s * 0.32))
            path.addLine(to: CGPoint(x: s * 0.42, y: s * 0.68))
            path.addLine(to: CGPoint(x: s * 0.84, y: s * 0.68))
            path.addLine(to: CGPoint(x: s * 0.84, y: s * 0.82))
            path.addLine(to: CGPoint(x: s * 0.16, y: s * 0.82))
            path.addLine(to: CGPoint(x: s * 0.16, y: s * 0.68))
            path.addLine(to: CGPoint(x: s * 0.58, y: s * 0.32))
            path.addLine(to: CGPoint(x: s * 0.16, y: s * 0.32))
            path.closeSubpath()

            ctx.setFillColor(NSColor.white.cgColor)
            ctx.addPath(path)
            ctx.fillPath()

            // Small play triangle in center
            let tri = CGMutablePath()
            tri.move(to: CGPoint(x: s * 0.46, y: s * 0.40))
            tri.addLine(to: CGPoint(x: s * 0.62, y: s * 0.50))
            tri.addLine(to: CGPoint(x: s * 0.46, y: s * 0.60))
            tri.closeSubpath()

            ctx.setFillColor(NSColor(white: 1.0, alpha: 0.95).cgColor)
            ctx.addPath(tri)
            ctx.fillPath()

            if let img = ctx.makeImage() {
                savePng(img, to: "\(drawableDir)/ic_notification.png")
            }
        }
    }

    print("All icons successfully generated!")
}

run()

