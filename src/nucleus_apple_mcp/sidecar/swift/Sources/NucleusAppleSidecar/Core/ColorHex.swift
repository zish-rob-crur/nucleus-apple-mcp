import CoreGraphics
import Foundation

func hexColor(from cgColor: CGColor?) -> String {
    guard let cgColor else { return "#000000" }

    let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    let converted = cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil) ?? cgColor
    guard let components = converted.components, !components.isEmpty else { return "#000000" }

    let r: CGFloat
    let g: CGFloat
    let b: CGFloat

    switch components.count {
    case 1:
        r = components[0]
        g = components[0]
        b = components[0]
    case 2:
        r = components[0]
        g = components[0]
        b = components[0]
    default:
        r = components[0]
        g = components[1]
        b = components[2]
    }

    func clampByte(_ x: CGFloat) -> Int {
        Int(max(0, min(255, (x * 255.0).rounded())))
    }

    return String(format: "#%02X%02X%02X", clampByte(r), clampByte(g), clampByte(b))
}

