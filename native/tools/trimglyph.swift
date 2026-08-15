import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 裁掉 glyph 四周透明边并居中放进正方画布（留 pad 比例的空白），
// 让它能像别的品牌标一样「缩小居中」而不显得被切断。
// 用法：trimglyph in.png out.png [pad=0.06]

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: trimglyph in.png out.png [pad]"); exit(1) }
let pad = args.count > 3 ? Double(args[3]) ?? 0.06 : 0.06

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { print("read fail"); exit(1) }
let w = image.width, h = image.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

var minX = w, minY = h, maxX = -1, maxY = -1
for y in 0..<h {
    for x in 0..<w where px[(y * w + x) * 4 + 3] > 8 {
        if x < minX { minX = x }; if x > maxX { maxX = x }
        if y < minY { minY = y }; if y > maxY { maxY = y }
    }
}
guard maxX >= minX else { print("empty"); exit(1) }
let bw = maxX - minX + 1, bh = maxY - minY + 1
print("bbox \(bw)x\(bh) at (\(minX),\(minY))  原画布 \(w)x\(h)")

// 正方画布：边长 = 长边 / (1 - 2*pad)，内容居中
let side = Int((Double(max(bw, bh)) / (1 - 2 * pad)).rounded())
guard let outCtx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
outCtx.clear(CGRect(x: 0, y: 0, width: side, height: side))
guard let cropped = image.cropping(to: CGRect(x: minX, y: minY, width: bw, height: bh)) else { exit(1) }
let dx = (side - bw) / 2, dy = (side - bh) / 2
outCtx.draw(cropped, in: CGRect(x: dx, y: dy, width: bw, height: bh))

guard let outImage = outCtx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, outImage, nil)
CGImageDestinationFinalize(dest)
print("wrote \(args[2])  \(side)x\(side)")
