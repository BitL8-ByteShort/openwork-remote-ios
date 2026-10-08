import AppKit

// Render the original bracket-and-arrow mark used in the accepted Penpot design.
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("OpenWorkRemote/Assets.xcassets")
let icon = assets.appendingPathComponent("AppIcon.appiconset")
try FileManager.default.createDirectory(at: icon, withIntermediateDirectories: true)
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(red: 0x35 / 255.0, green: 0x59 / 255.0, blue: 0xDF / 255.0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.setStrokeColor(CGColor(gray: 1, alpha: 1))
context.setLineWidth(47)
context.setLineCap(.round)
context.setLineJoin(.round)
func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * Double(size), y: y * Double(size)) }
context.move(to: point(0.40, 0.75))
context.addLine(to: point(0.26, 0.75))
context.addLine(to: point(0.26, 0.25))
context.addLine(to: point(0.40, 0.25))
context.move(to: point(0.60, 0.75))
context.addLine(to: point(0.74, 0.75))
context.addLine(to: point(0.74, 0.25))
context.addLine(to: point(0.60, 0.25))
context.move(to: point(0.40, 0.50))
context.addLine(to: point(0.61, 0.50))
context.move(to: point(0.54, 0.57))
context.addLine(to: point(0.61, 0.50))
context.addLine(to: point(0.54, 0.43))
context.strokePath()
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: icon.appendingPathComponent("AppIcon.png"))
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
struct Info: Encodable { let author = "xcode"; let version = 1 }
struct Image: Encodable { let filename = "AppIcon.png"; let idiom = "universal"; let platform = "ios"; let size = "1024x1024" }
struct IconContents: Encodable { let images = [Image()]; let info = Info() }
struct Contents: Encodable { let info = Info() }
try encoder.encode(IconContents()).write(to: icon.appendingPathComponent("Contents.json"))
try encoder.encode(Contents()).write(to: assets.appendingPathComponent("Contents.json"))
print("Generated original OpenWork Remote app icon.")
