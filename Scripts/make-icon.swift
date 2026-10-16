#!/usr/bin/env swift

// Renders Resources/EyeProtector.icns from code.
//
// Drawn rather than committed as a binary so the icon can be reviewed in a
// diff and adjusted without a design tool. Run `./Scripts/make-icon.sh`.

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

private let backgroundTop = RGB(r: 0.09, g: 0.36, b: 0.44)
private let backgroundBottom = RGB(r: 0.04, g: 0.09, b: 0.16)
private let scleraColor = RGB(r: 0.96, g: 0.98, b: 0.99)
private let irisColor = RGB(r: 0.11, g: 0.52, b: 0.60)
private let pupilColor = RGB(r: 0.03, g: 0.07, b: 0.12)

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

/// The almond outline, as two cubic curves meeting at the corners. Built in a
/// unit square and scaled, so every size renders the same shape.
private func eyePath(in box: CGRect) -> CGPath {
    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: box.minX + box.width * x, y: box.minY + box.height * y)
    }

    let path = CGMutablePath()
    path.move(to: point(0.06, 0.5))
    path.addCurve(
        to: point(0.94, 0.5),
        control1: point(0.30, 0.95),
        control2: point(0.70, 0.95)
    )
    path.addCurve(
        to: point(0.06, 0.5),
        control1: point(0.70, 0.05),
        control2: point(0.30, 0.05)
    )
    path.closeSubpath()
    return path
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

    // The eye, centred and a little above middle so it reads as upright.
    let eyeWidth = plate.width * 0.70
    let eyeHeight = eyeWidth * 0.62
    let eyeBox = CGRect(
        x: plate.midX - eyeWidth / 2,
        y: plate.midY - eyeHeight / 2,
        width: eyeWidth,
        height: eyeHeight
    )

    context.addPath(eyePath(in: eyeBox))
    context.setFillColor(scleraColor.cg)
    context.fillPath()

    let irisRadius = eyeHeight * 0.40
    let center = CGPoint(x: eyeBox.midX, y: eyeBox.midY)

    context.addPath(circle(centeredAt: center, radius: irisRadius))
    context.setFillColor(irisColor.cg)
    context.fillPath()

    context.addPath(circle(centeredAt: center, radius: irisRadius * 0.52))
    context.setFillColor(pupilColor.cg)
    context.fillPath()

    // Catchlight. Skipped at the smallest sizes, where it turns into mud.
    if size >= 64 {
        context.addPath(
            circle(
                centeredAt: CGPoint(
                    x: center.x + irisRadius * 0.38,
                    y: center.y + irisRadius * 0.40
                ),
                radius: irisRadius * 0.22
            )
        )
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85))
        context.fillPath()
    }

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
        throw NSError(domain: "make-icon", code: 1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "make-icon", code: 2)
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

let iconset = URL(fileURLWithPath: "Resources/EyeProtector.iconset")
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
