import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 把「彩底 + 白线」的 app 图标提炼成「透明底 + 单色线」的模板 glyph。
// 判据：白线的三通道最小值高（接近白/灰），彩底最小值低（绿底 R 很低）。
// 用法：glyphify <in.png> <out.png> [analyze]

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: glyphify in.png out.png [analyze]"); exit(1) }
let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let analyzeOnly = args.count > 3 && args[3] == "analyze"

guard let src = CGImageSourceCreateWithURL(inURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("cannot read image"); exit(1)
}
let w = image.width, h = image.height

// 统一解到 RGBA8
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("cannot make context"); exit(1)
}
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

if analyzeOnly {
    // 按 minChannel 分桶，看看「白线」和「绿底」分得开不开
    var buckets = [Int](repeating: 0, count: 11)
    var transparent = 0
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let a = Int(pixels[i + 3])
        if a < 20 { transparent += 1; continue }
        let minC = min(Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        buckets[min(10, minC * 10 / 255)] += 1
    }
    print("size \(w)x\(h)  透明 \(transparent)")
    for (index, count) in buckets.enumerated() where count > 0 {
        let lo = index * 255 / 10
        print(String(format: "minChannel %3d-%3d : %6d px", lo, lo + 25, count))
    }
    // 采样几个关键点
    func sample(_ x: Int, _ y: Int) -> String {
        let i = (y * w + x) * 4
        return "(\(pixels[i]),\(pixels[i+1]),\(pixels[i+2]) a\(pixels[i+3]))"
    }
    print("左上角内 \(sample(w/6, h/6))  中心 \(sample(w/2, h/2))  右下 \(sample(w*5/6, h*5/6))")
    exit(0)
}

// 生成模板 glyph：alpha = 白度（minChannel 归一后打斜坡），RGB = 黑（模板渲染只看 alpha）
var out = [UInt8](repeating: 0, count: w * h * 4)
let lo: Double = 0.50, hi: Double = 0.78
for i in stride(from: 0, to: pixels.count, by: 4) {
    let srcAlpha = Double(pixels[i + 3]) / 255
    guard srcAlpha > 0.02 else { continue }
    // premultipliedLast：先还原成直通色再判白度
    let r = Double(pixels[i]) / 255 / srcAlpha
    let g = Double(pixels[i + 1]) / 255 / srcAlpha
    let b = Double(pixels[i + 2]) / 255 / srcAlpha
    let whiteness = min(min(r, g), b)
    let ramp = max(0, min(1, (whiteness - lo) / (hi - lo)))
    let alpha = UInt8((ramp * srcAlpha * 255).rounded())
    out[i] = 0; out[i + 1] = 0; out[i + 2] = 0; out[i + 3] = alpha
}

guard let outCtx = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8,
                             bytesPerRow: w * 4, space: space,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let outImage = outCtx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)
else { print("cannot write"); exit(1) }
CGImageDestinationAddImage(dest, outImage, nil)
CGImageDestinationFinalize(dest)

let opaque = out.enumerated().filter { $0.offset % 4 == 3 && $0.element > 128 }.count
print("wrote \(outURL.lastPathComponent)  不透明像素 \(opaque) / \(w * h)")
