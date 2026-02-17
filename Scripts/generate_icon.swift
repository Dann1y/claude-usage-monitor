#!/usr/bin/swift
//
// generate_icon.swift
// Generates an .icns app icon for "Claude Usage Monitor"
//
// Usage: swift Scripts/generate_icon.swift <output_path.icns>
//

import AppKit
import Foundation

// MARK: - Icon Renderer

/// Renders a single icon image at the given pixel size.
func renderIcon(pixelSize: Int) -> NSImage {
    let size = NSSize(width: pixelSize, height: pixelSize)
    let image = NSImage(size: size)

    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else {
        fatalError("Failed to obtain CGContext")
    }

    let rect = CGRect(origin: .zero, size: CGSize(width: pixelSize, height: pixelSize))

    // -- Rounded rectangle background with blue gradient --
    let cornerRadius = CGFloat(pixelSize) * 0.22
    let bgPath = CGPath(
        roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    context.saveGState()
    context.addPath(bgPath)
    context.clip()

    // Claude-inspired blue/indigo gradient (top-left to bottom-right)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        CGColor(red: 0.35, green: 0.48, blue: 0.95, alpha: 1.0),  // lighter blue-indigo
        CGColor(red: 0.20, green: 0.25, blue: 0.72, alpha: 1.0),  // deeper indigo
    ] as CFArray
    let locations: [CGFloat] = [0.0, 1.0]

    if let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: locations) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: CGFloat(pixelSize)),
            end: CGPoint(x: CGFloat(pixelSize), y: 0),
            options: []
        )
    }
    context.restoreGState()

    // -- Subtle inner shadow / highlight along top edge --
    context.saveGState()
    context.addPath(bgPath)
    context.clip()
    let highlightColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.12)
    context.setFillColor(highlightColor)
    let highlightRect = CGRect(
        x: 0,
        y: CGFloat(pixelSize) * 0.88,
        width: CGFloat(pixelSize),
        height: CGFloat(pixelSize) * 0.12
    )
    context.fill([highlightRect])
    context.restoreGState()

    // -- Draw the cloud symbol --
    // We use NSImage(systemSymbolName:) which is available on macOS 11+
    let symbolConfig = NSImage.SymbolConfiguration(pointSize: CGFloat(pixelSize) * 0.38, weight: .medium)
    if let cloudSymbol = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symbolConfig) {

        // Tint the symbol white
        let tinted = NSImage(size: cloudSymbol.size)
        tinted.lockFocus()
        NSColor.white.set()
        let tintRect = NSRect(origin: .zero, size: cloudSymbol.size)
        cloudSymbol.draw(in: tintRect)
        tintRect.fill(using: .sourceAtop)
        tinted.unlockFocus()

        // Center the cloud in the icon
        let symbolSize = tinted.size
        let x = (CGFloat(pixelSize) - symbolSize.width) / 2.0
        let y = (CGFloat(pixelSize) - symbolSize.height) / 2.0 + CGFloat(pixelSize) * 0.02
        tinted.draw(
            in: NSRect(x: x, y: y, width: symbolSize.width, height: symbolSize.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
    } else {
        // Fallback: draw a simple cloud shape manually if SF Symbols unavailable
        drawFallbackCloud(context: context, pixelSize: pixelSize)
    }

    // -- Draw a small bar-chart element in the lower portion to suggest "monitoring" --
    drawMiniChart(context: context, pixelSize: pixelSize)

    image.unlockFocus()
    return image
}

/// Fallback cloud drawing if SF Symbols are not available.
func drawFallbackCloud(context: CGContext, pixelSize: Int) {
    let s = CGFloat(pixelSize)
    context.saveGState()
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))

    let cx = s * 0.5
    let cy = s * 0.55

    // Build cloud from overlapping ellipses
    let mainW = s * 0.44
    let mainH = s * 0.22
    let mainRect = CGRect(x: cx - mainW / 2, y: cy - mainH / 2, width: mainW, height: mainH)
    context.fillEllipse(in: mainRect)

    let topW = s * 0.24
    let topH = s * 0.24
    context.fillEllipse(in: CGRect(x: cx - topW / 2, y: cy + mainH * 0.15, width: topW, height: topH))

    let leftW = s * 0.20
    let leftH = s * 0.20
    context.fillEllipse(in: CGRect(x: cx - mainW * 0.35, y: cy - mainH * 0.05, width: leftW, height: leftH))

    let rightW = s * 0.22
    let rightH = s * 0.20
    context.fillEllipse(in: CGRect(x: cx + mainW * 0.15, y: cy, width: rightW, height: rightH))

    context.restoreGState()
}

/// Draws small bar-chart bars at the bottom of the icon to convey "usage monitoring".
func drawMiniChart(context: CGContext, pixelSize: Int) {
    let s = CGFloat(pixelSize)
    context.saveGState()

    let barColor = CGColor(red: 1, green: 1, blue: 1, alpha: 0.85)
    context.setFillColor(barColor)

    let barCount = 4
    let totalChartWidth = s * 0.36
    let barWidth = totalChartWidth / CGFloat(barCount * 2 - 1)
    let gap = barWidth
    let startX = (s - totalChartWidth) / 2.0
    let baseY = s * 0.18

    let heights: [CGFloat] = [0.06, 0.11, 0.08, 0.14]

    for i in 0..<barCount {
        let barHeight = s * heights[i]
        let x = startX + CGFloat(i) * (barWidth + gap)
        let barRect = CGRect(x: x, y: baseY, width: barWidth, height: barHeight)
        let barPath = CGPath(
            roundedRect: barRect,
            cornerWidth: barWidth * 0.3,
            cornerHeight: barWidth * 0.3,
            transform: nil
        )
        context.addPath(barPath)
        context.fillPath()
    }

    context.restoreGState()
}

// MARK: - .iconset / .icns generation

/// The required sizes for a macOS .iconset directory.
/// Each entry is (filename, pixel width/height).
let iconsetEntries: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func writePNG(image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create PNG data"])
    }
    try pngData.write(to: url)
}

func generateICNS(outputPath: String) throws {
    let fileManager = FileManager.default

    // Create a temporary .iconset directory
    let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let iconsetDir = tempDir.appendingPathComponent("AppIcon.iconset")
    try fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

    print("Rendering icon images...")

    // Deduplicate pixel sizes so we only render each size once
    var renderedImages: [Int: NSImage] = [:]
    let uniqueSizes = Set(iconsetEntries.map { $0.1 })
    for px in uniqueSizes.sorted() {
        print("  Rendering \(px)x\(px)...")
        renderedImages[px] = renderIcon(pixelSize: px)
    }

    // Write PNGs into the .iconset
    for (filename, px) in iconsetEntries {
        guard let image = renderedImages[px] else { continue }
        let fileURL = iconsetDir.appendingPathComponent(filename)
        try writePNG(image: image, to: fileURL)
    }

    print("Converting .iconset to .icns...")

    // Use iconutil to convert .iconset -> .icns
    let outputURL = URL(fileURLWithPath: outputPath)

    // Make sure the output directory exists
    let outputDir = outputURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

    // Remove existing file if present
    if fileManager.fileExists(atPath: outputPath) {
        try fileManager.removeItem(atPath: outputPath)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputPath]

    let pipe = Pipe()
    process.standardError = pipe

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
        let errorStr = String(data: errorData, encoding: .utf8) ?? "unknown error"
        throw NSError(
            domain: "IconGen", code: 2,
            userInfo: [NSLocalizedDescriptionKey: "iconutil failed: \(errorStr)"]
        )
    }

    // Cleanup temp directory
    try? fileManager.removeItem(at: tempDir)

    let attrs = try fileManager.attributesOfItem(atPath: outputPath)
    let fileSize = attrs[.size] as? Int ?? 0
    print("Successfully generated \(outputPath) (\(fileSize) bytes)")
}

// MARK: - Main

guard CommandLine.arguments.count >= 2 else {
    print("Usage: swift \(CommandLine.arguments[0]) <output_path.icns>")
    exit(1)
}

let outputPath = CommandLine.arguments[1]

do {
    try generateICNS(outputPath: outputPath)
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
