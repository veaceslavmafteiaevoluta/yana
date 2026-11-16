import AppKit
let args = CommandLine.arguments
let src = NSImage(contentsOfFile: args[1])!
var rect = CGRect(origin: .zero, size: src.size)
let cg = src.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
let w = cg.width, h = cg.height
// Find bounding box of the squircle (pixels clearly brighter than the black background)
let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
let p = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
var minX = w, minY = h, maxX = 0, maxY = 0
// scan the middle row/column to avoid the outer glow
func lum(_ x: Int, _ y: Int) -> Int { let i = (y * w + x) * 4; return Int(p[i]) + Int(p[i+1]) + Int(p[i+2]) }
let midY = h / 2, midX = w / 2
for x in 0..<w where lum(x, midY) > 120 { minX = min(minX, x); maxX = max(maxX, x) }
for y in 0..<h where lum(midX, y) > 120 { minY = min(minY, y); maxY = max(maxY, y) }
print("bbox x:\(minX)-\(maxX) y:\(minY)-\(maxY) (bitmap rows from bottom)")
let inset = 4
let crop = CGRect(x: minX + inset, y: h - maxY - 1 + inset, width: maxX - minX + 1 - 2 * inset, height: maxY - minY + 1 - 2 * inset)
let cropped = cg.cropping(to: crop)!

let canvas = 1024, art: CGFloat = 824, off = (CGFloat(canvas) - art) / 2
let out = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: canvas * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let artRect = CGRect(x: off, y: off + 6, width: art, height: art)
let shape = CGPath(roundedRect: artRect, cornerWidth: art * 0.2237, cornerHeight: art * 0.2237, transform: nil)
// soft drop shadow like system icons
out.saveGState()
out.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.35).cgColor)
out.addPath(shape); out.setFillColor(NSColor.black.cgColor); out.fillPath()
out.restoreGState()
out.addPath(shape); out.clip()
out.interpolationQuality = .high
out.draw(cropped, in: artRect)
let img = out.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("ok")
