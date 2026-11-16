#!/usr/bin/env swift

// Renders Resources/Curfew.icns from code.
//
// Drawn rather than committed as a binary so the icon can be reviewed in a
// diff and adjusted without a design tool. Run `./Scripts/make-curfew-icon.sh`.

import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

// MARK: - Geometry, in fractions of the canvas

/// Apple's icon grid leaves the artwork short of the canvas edge.
private let squircleInset = 0.085
private let cornerRadiusFraction = 0.185

private struct RGB {
    let r, g, b: Double

    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

private let backgroundTop = RGB(r: 0.13, g: 0.15, b: 0.30)
private let backgroundBottom = RGB(r: 0.03, g: 0.04, b: 0.10)
private let moonColor = RGB(r: 0.98, g: 0.93, b: 0.72)

/// A squircle-ish rounded rectangle. `CGPath`'s rounded rect is close enough
/// at icon sizes that hand-rolling a superellipse buys nothing visible.
private func squirclePath(in rect: CGRect) -> CGPath {
    let radius = rect.width * cornerRadiusFraction
    return CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
}

private func circle(centeredAt center: CGPoint, radius: Double) -> CGPath {
    CGPath(
        ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ),
        transform: nil
    )
}

// MARK: - Drawing

private func drawIcon(size: Int) -> CGImage? {
    let side = Double(size)
    guard
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    else { return nil }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    let inset = side * squircleInset
    let plate = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)

    // Background plate, with a top-to-bottom gradient.
    context.saveGState()
    context.addPath(squirclePath(in: plate))
    context.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [backgroundTop.cg, backgroundBottom.cg] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.midX, y: plate.maxY),
        end: CGPoint(x: plate.midX, y: plate.minY),
        options: []
    )
    context.restoreGState()

    // The moon: a disc with a second, offset disc cut out of it, so what is
    // left is a crescent. Drawn with the even-odd rule inside a clip rather
    // than as a hand-built curve, which keeps it to two circles.
    let radius = plate.width * 0.30
    let center = CGPoint(x: plate.midX - radius * 0.10, y: plate.midY)
    let bite = CGPoint(x: center.x + radius * 0.50, y: center.y + radius * 0.28)

    context.saveGState()
    context.addPath(circle(centeredAt: bite, radius: radius * 0.86))
    context.addRect(CGRect(x: 0, y: 0, width: side, height: side))
    context.clip(using: .evenOdd)
    context.addPath(circle(centeredAt: center, radius: radius))
    context.setFillColor(moonColor.cg)
    context.fillPath()
    context.restoreGState()

    return context.makeImage()
}

private func write(_ image: CGImage, to url: URL) throws {
    guard
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw NSError(domain: "make-curfew-icon", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "make-curfew-icon", code: 2)
    }
}

// MARK: - Main

/// `(point size, scale)` — the full set `iconutil` expects.
private let variants: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

let iconset = URL(fileURLWithPath: "Resources/Curfew.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for variant in variants {
    let pixels = variant.points * variant.scale
    guard let image = drawIcon(size: pixels) else {
        FileHandle.standardError.write(Data("failed to render \(pixels)px\n".utf8))
        exit(1)
    }
    let suffix = variant.scale == 1 ? "" : "@\(variant.scale)x"
    let name = "icon_\(variant.points)x\(variant.points)\(suffix).png"
    try write(image, to: iconset.appendingPathComponent(name))
}

print("rendered \(variants.count) sizes into \(iconset.path)")
