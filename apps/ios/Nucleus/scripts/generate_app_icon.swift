#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconSpec {
    let filename: String
    let pixels: Int
}

struct Palette {
    static let ink = CGColor(srgbRed: 0.05, green: 0.06, blue: 0.07, alpha: 1.0)
    static let graphite = CGColor(srgbRed: 0.09, green: 0.10, blue: 0.12, alpha: 1.0)
    static let deepTeal = CGColor(srgbRed: 0.03, green: 0.18, blue: 0.16, alpha: 1.0)
    static let accent = CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 1.0)
    static let accentDeep = CGColor(srgbRed: 0.14, green: 0.80, blue: 0.62, alpha: 1.0)
    static let mist = CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.10)
}

func makeGradient(_ colors: [CGColor], locations: [CGFloat]) -> CGGradient {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

func drawBackground(in ctx: CGContext, size: CGFloat) {
    let bg = makeGradient(
        [Palette.ink, Palette.graphite, Palette.deepTeal],
        locations: [0.0, 0.52, 1.0]
    )
    ctx.drawLinearGradient(
        bg,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: size, y: size),
        options: []
    )

    let aurora1 = makeGradient(
        [
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.35),
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.12),
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
        ],
        locations: [0.0, 0.32, 1.0]
    )
    ctx.drawRadialGradient(
        aurora1,
        startCenter: CGPoint(x: size * 0.92, y: size * 0.10),
        startRadius: 0,
        endCenter: CGPoint(x: size * 0.92, y: size * 0.10),
        endRadius: size * 0.95,
        options: []
    )

    let aurora2 = makeGradient(
        [
            CGColor(srgbRed: 0.14, green: 0.80, blue: 0.62, alpha: 0.18),
            CGColor(srgbRed: 0.14, green: 0.80, blue: 0.62, alpha: 0.06),
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
        ],
        locations: [0.0, 0.42, 1.0]
    )
    ctx.drawRadialGradient(
        aurora2,
        startCenter: CGPoint(x: size * 0.10, y: size * 0.92),
        startRadius: 0,
        endCenter: CGPoint(x: size * 0.10, y: size * 0.92),
        endRadius: size * 0.78,
        options: []
    )

    let vignette = makeGradient(
        [
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.18),
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.40),
        ],
        locations: [0.0, 0.62, 1.0]
    )
    ctx.drawRadialGradient(
        vignette,
        startCenter: CGPoint(x: size * 0.50, y: size * 0.50),
        startRadius: size * 0.10,
        endCenter: CGPoint(x: size * 0.50, y: size * 0.50),
        endRadius: size * 0.78,
        options: []
    )
}

func drawNucleusOrbital(in ctx: CGContext, size: CGFloat) {
    let center = CGPoint(x: size * 0.58, y: size * 0.48)
    let r = size * 0.29

    let glow = makeGradient(
        [
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.30),
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.10),
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
        ],
        locations: [0.0, 0.35, 1.0]
    )
    ctx.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: center.x, y: center.y),
        startRadius: 0,
        endCenter: CGPoint(x: center.x, y: center.y),
        endRadius: r * 2.1,
        options: []
    )

    let rotation = -CGFloat.pi * 0.12
    let scaleX: CGFloat = 1.34
    let scaleY: CGFloat = 0.78
    let ringRadius = r * 1.06

    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotation)
    ctx.scaleBy(x: scaleX, y: scaleY)
    let ringPath = CGMutablePath()
    ringPath.addEllipse(in: CGRect(x: -ringRadius, y: -ringRadius, width: ringRadius * 2, height: ringRadius * 2))
    ctx.addPath(ringPath)
    ctx.setBlendMode(.plusLighter)
    ctx.setStrokeColor(CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.22))
    ctx.setLineWidth(max(1, size * 0.014) / max(scaleX, scaleY))
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    ctx.saveGState()
    let orbPath = CGPath(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2), transform: nil)
    ctx.addPath(orbPath)
    ctx.clip()

    let orbGradient = makeGradient(
        [
            CGColor(srgbRed: 0.65, green: 1.0, blue: 0.92, alpha: 0.92),
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.92),
            CGColor(srgbRed: 0.06, green: 0.34, blue: 0.28, alpha: 1.0),
        ],
        locations: [0.0, 0.36, 1.0]
    )
    ctx.drawRadialGradient(
        orbGradient,
        startCenter: CGPoint(x: center.x - r * 0.38, y: center.y - r * 0.40),
        startRadius: r * 0.05,
        endCenter: CGPoint(x: center.x, y: center.y),
        endRadius: r * 1.18,
        options: []
    )

    let edgeShade = makeGradient(
        [
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.18),
            CGColor(srgbRed: 0.0, green: 0.0, blue: 0.0, alpha: 0.34),
        ],
        locations: [0.0, 0.70, 1.0]
    )
    ctx.drawRadialGradient(
        edgeShade,
        startCenter: CGPoint(x: center.x, y: center.y),
        startRadius: r * 0.60,
        endCenter: CGPoint(x: center.x, y: center.y),
        endRadius: r * 1.05,
        options: []
    )
    ctx.restoreGState()

    ctx.setBlendMode(.normal)
    ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.18))
    ctx.setLineWidth(max(1, size * 0.006))
    ctx.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))

    let highlightR = r * 0.30
    ctx.saveGState()
    let highlightPath = CGPath(ellipseIn: CGRect(x: center.x - r * 0.62, y: center.y - r * 0.66, width: highlightR * 2, height: highlightR * 2), transform: nil)
    ctx.addPath(highlightPath)
    ctx.clip()
    let highlight = makeGradient(
        [
            CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.42),
            CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.12),
            CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.0),
        ],
        locations: [0.0, 0.45, 1.0]
    )
    let hlCenter = CGPoint(x: center.x - r * 0.54, y: center.y - r * 0.56)
    ctx.drawRadialGradient(
        highlight,
        startCenter: hlCenter,
        startRadius: 0,
        endCenter: hlCenter,
        endRadius: highlightR * 1.30,
        options: []
    )
    ctx.restoreGState()

    let coreCenter = CGPoint(x: center.x - r * 0.18, y: center.y + r * 0.20)
    let coreR = r * 0.18
    let coreGlow = makeGradient(
        [
            CGColor(srgbRed: 0.65, green: 1.0, blue: 0.92, alpha: 0.70),
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.35),
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.0),
        ],
        locations: [0.0, 0.40, 1.0]
    )
    ctx.drawRadialGradient(
        coreGlow,
        startCenter: coreCenter,
        startRadius: 0,
        endCenter: coreCenter,
        endRadius: coreR * 1.90,
        options: []
    )

    let electronAngle = CGFloat.pi * 1.35
    var ringTransform = CGAffineTransform.identity
    ringTransform = ringTransform.translatedBy(x: center.x, y: center.y)
    ringTransform = ringTransform.rotated(by: rotation)
    ringTransform = ringTransform.scaledBy(x: scaleX, y: scaleY)
    let ringPoint = CGPoint(x: cos(electronAngle) * ringRadius, y: sin(electronAngle) * ringRadius).applying(ringTransform)

    let dotR = max(1.5, size * 0.020)
    let dotGlow = makeGradient(
        [
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.60),
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.14),
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.0),
        ],
        locations: [0.0, 0.50, 1.0]
    )
    ctx.drawRadialGradient(
        dotGlow,
        startCenter: ringPoint,
        startRadius: 0,
        endCenter: ringPoint,
        endRadius: dotR * 3.0,
        options: []
    )
    ctx.setFillColor(CGColor(srgbRed: 0.65, green: 1.0, blue: 0.92, alpha: 0.92))
    ctx.fillEllipse(in: CGRect(x: ringPoint.x - dotR, y: ringPoint.y - dotR, width: dotR * 2, height: dotR * 2))
}

func drawNucleusMinimal(in ctx: CGContext, size: CGFloat) {
    let center = CGPoint(x: size * 0.54, y: size * 0.50)
    let coreR = size * 0.12

    let coreGlow = makeGradient(
        [
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.22),
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.10),
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.0),
        ],
        locations: [0.0, 0.38, 1.0]
    )
    ctx.drawRadialGradient(
        coreGlow,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: coreR * 3.4,
        options: []
    )

    ctx.saveGState()
    let corePath = CGPath(ellipseIn: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2), transform: nil)
    ctx.addPath(corePath)
    ctx.clip()

    let fill = makeGradient(
        [
            CGColor(srgbRed: 0.70, green: 1.0, blue: 0.94, alpha: 0.92),
            CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.92),
            CGColor(srgbRed: 0.06, green: 0.30, blue: 0.25, alpha: 1.0),
        ],
        locations: [0.0, 0.42, 1.0]
    )
    ctx.drawRadialGradient(
        fill,
        startCenter: CGPoint(x: center.x - coreR * 0.44, y: center.y - coreR * 0.46),
        startRadius: coreR * 0.06,
        endCenter: center,
        endRadius: coreR * 1.22,
        options: []
    )
    ctx.restoreGState()

    ctx.setStrokeColor(CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.18))
    ctx.setLineWidth(max(1, size * 0.006))
    ctx.strokeEllipse(in: CGRect(x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2))

    let ringRadius = size * 0.32
    let rotation = -CGFloat.pi * 0.14
    let scaleX: CGFloat = 1.22
    let scaleY: CGFloat = 0.78
    let stroke = max(1, size * 0.008) / max(scaleX, scaleY)

    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: rotation)
    ctx.scaleBy(x: scaleX, y: scaleY)
    ctx.setLineCap(.round)

    // Soft glow pass.
    ctx.setBlendMode(.plusLighter)
    ctx.setShadow(offset: .zero, blur: size * 0.030, color: CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.18))
    ctx.setStrokeColor(CGColor(srgbRed: 0.36, green: 0.96, blue: 0.76, alpha: 0.20))
    ctx.setLineWidth(stroke)
    ctx.addArc(center: .zero, radius: ringRadius, startAngle: CGFloat.pi * 0.10, endAngle: CGFloat.pi * 1.18, clockwise: false)
    ctx.strokePath()
    ctx.addArc(center: .zero, radius: ringRadius, startAngle: CGFloat.pi * 1.32, endAngle: CGFloat.pi * 1.92, clockwise: false)
    ctx.strokePath()

    // Crisp pass.
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.setBlendMode(.normal)
    ctx.setStrokeColor(CGColor(srgbRed: 0.65, green: 1.0, blue: 0.92, alpha: 0.20))
    ctx.setLineWidth(stroke * 0.94)
    ctx.addArc(center: .zero, radius: ringRadius, startAngle: CGFloat.pi * 0.12, endAngle: CGFloat.pi * 1.16, clockwise: false)
    ctx.strokePath()
    ctx.addArc(center: .zero, radius: ringRadius, startAngle: CGFloat.pi * 1.34, endAngle: CGFloat.pi * 1.90, clockwise: false)
    ctx.strokePath()

    ctx.restoreGState()

    // Specular highlight.
    let hlR = coreR * 0.34
    ctx.saveGState()
    let highlightPath = CGPath(ellipseIn: CGRect(x: center.x - coreR * 0.68, y: center.y - coreR * 0.70, width: hlR * 2, height: hlR * 2), transform: nil)
    ctx.addPath(highlightPath)
    ctx.clip()
    let highlight = makeGradient(
        [
            CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.40),
            CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.12),
            CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.0),
        ],
        locations: [0.0, 0.44, 1.0]
    )
    let hlCenter = CGPoint(x: center.x - coreR * 0.58, y: center.y - coreR * 0.60)
    ctx.drawRadialGradient(
        highlight,
        startCenter: hlCenter,
        startRadius: 0,
        endCenter: hlCenter,
        endRadius: hlR * 1.35,
        options: []
    )
    ctx.restoreGState()
}

enum IconStyle: String {
    case minimal
    case orbital
}

func renderIcon(pixels: Int) -> CGImage {
    return renderIcon(pixels: pixels, style: .minimal)
}

func renderIcon(pixels: Int, style: IconStyle) -> CGImage {
    let w = pixels
    let h = pixels
    let size = CGFloat(pixels)

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(
        data: nil,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    )!

    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // Flip to a top-left origin to make layout math intuitive.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    drawBackground(in: ctx, size: size)
    switch style {
    case .minimal:
        drawNucleusMinimal(in: ctx, size: size)
    case .orbital:
        drawNucleusOrbital(in: ctx, size: size)
    }

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw NSError(domain: "icon", code: 1)
    }
    CGImageDestinationAddImage(destination, image, [
        kCGImageDestinationLossyCompressionQuality: 1.0,
    ] as CFDictionary)
    if !CGImageDestinationFinalize(destination) {
        throw NSError(domain: "icon", code: 2)
    }
}

let specs: [IconSpec] = [
    IconSpec(filename: "AppIcon-iPhone-20@2x.png", pixels: 40),
    IconSpec(filename: "AppIcon-iPhone-20@3x.png", pixels: 60),
    IconSpec(filename: "AppIcon-iPhone-29@2x.png", pixels: 58),
    IconSpec(filename: "AppIcon-iPhone-29@3x.png", pixels: 87),
    IconSpec(filename: "AppIcon-iPhone-40@2x.png", pixels: 80),
    IconSpec(filename: "AppIcon-iPhone-40@3x.png", pixels: 120),
    IconSpec(filename: "AppIcon-iPhone-60@2x.png", pixels: 120),
    IconSpec(filename: "AppIcon-iPhone-60@3x.png", pixels: 180),
    IconSpec(filename: "AppIcon-iPad-20@1x.png", pixels: 20),
    IconSpec(filename: "AppIcon-iPad-20@2x.png", pixels: 40),
    IconSpec(filename: "AppIcon-iPad-29@1x.png", pixels: 29),
    IconSpec(filename: "AppIcon-iPad-29@2x.png", pixels: 58),
    IconSpec(filename: "AppIcon-iPad-40@1x.png", pixels: 40),
    IconSpec(filename: "AppIcon-iPad-40@2x.png", pixels: 80),
    IconSpec(filename: "AppIcon-iPad-76@1x.png", pixels: 76),
    IconSpec(filename: "AppIcon-iPad-76@2x.png", pixels: 152),
    IconSpec(filename: "AppIcon-iPad-83.5@2x.png", pixels: 167),
    IconSpec(filename: "AppIcon-1024.png", pixels: 1024),
]

let defaultOutput = "apps/ios/Nucleus/Nucleus/Assets.xcassets/AppIcon.appiconset"

var style: IconStyle = .minimal
var outputPath: String = defaultOutput
let args = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < args.count {
    let arg = args[index]
    if arg == "--style", index + 1 < args.count {
        style = IconStyle(rawValue: args[index + 1]) ?? style
        index += 2
        continue
    }
    if arg == "--out", index + 1 < args.count {
        outputPath = args[index + 1]
        index += 2
        continue
    }
    if !arg.hasPrefix("--") {
        outputPath = arg
        index += 1
        continue
    }
    index += 1
}

let outDir = URL(fileURLWithPath: outputPath)

try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for spec in specs {
    let image = renderIcon(pixels: spec.pixels, style: style)
    let url = outDir.appendingPathComponent(spec.filename)
    try writePNG(image, to: url)
    print("wrote \(spec.filename)")
}
