// 应用图标生成器 v2：多层光照蓝色背景板 + 三片玻璃叠层 glyph
// 几何遵循 Apple Big Sur+ 图标网格：1024 画布上内容板 824×824 居中（80.46%），
// 圆角 22.4%，四周透明边距留给系统投影（不烙印外部阴影，保证包围盒可验证）
//
// 用法：
//   render-icon preview <输出目录>          生成 A/B/C 三个 512px 变体 + 并排对比图
//   render-icon iconset <iconset目录> [A|B|C] 用指定变体（默认 A）生成整套 iconset

import AppKit

// MARK: - 变体参数

struct Variant {
    let name: String
    let note: String
    /// 卡片宽高（内容板比例）
    let cardW: CGFloat
    let cardH: CGFloat
    /// 相邻卡片纵向间距（内容板比例）
    let dy: CGFloat
    /// [底, 中, 顶] 缩放
    let scales: [CGFloat]
    /// [底, 中, 顶] 横向微错位（内容板比例）
    let xOffsets: [CGFloat]
    /// [底, 中, 顶] 白色透明度
    let alphas: [CGFloat]
}

// 数组顺序一律为 [后, 中, 前]；前片在下方、后片从上方探出（Wallet 式堆叠）
let variants: [String: Variant] = [
    "A": Variant(name: "A", note: "后片收窄递进",
                 cardW: 0.54, cardH: 0.33, dy: 0.11,
                 scales: [0.84, 0.92, 1.00], xOffsets: [0, 0, 0],
                 alphas: [0.30, 0.60, 1.00]),
    "B": Variant(name: "B", note: "等大微错位",
                 cardW: 0.53, cardH: 0.33, dy: 0.12,
                 scales: [1.00, 1.00, 1.00], xOffsets: [0.015, -0.015, 0],
                 alphas: [0.30, 0.60, 1.00]),
    "C": Variant(name: "C", note: "宽片浅堆叠",
                 cardW: 0.58, cardH: 0.30, dy: 0.13,
                 scales: [0.88, 0.94, 1.00], xOffsets: [0, 0, 0],
                 alphas: [0.32, 0.62, 1.00]),
]

// MARK: - 渲染

func deviceColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!
}

func render(canvas: Int, variant: Variant) -> NSBitmapImageRep {
    let s = CGFloat(canvas)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: canvas, pixelsHigh: canvas,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("bitmap 创建失败") }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // 内容板：824/1024 居中，圆角 22.4%
    let plate = (s * 824.0 / 1024.0).rounded()
    let origin = ((s - plate) / 2).rounded()
    let plateRect = CGRect(x: origin, y: origin, width: plate, height: plate)
    let radius = plate * 0.224
    let platePath = CGPath(roundedRect: plateRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // ① 主渐变：顶部天蓝 → 底部深蓝（#0A84FF 家族）
    cg.saveGState()
    cg.addPath(platePath); cg.clip()
    let base = CGGradient(colorsSpace: space, colors: [
        deviceColor(0.42, 0.68, 1.00, 1),
        deviceColor(0.13, 0.50, 0.98, 1),
        deviceColor(0.02, 0.34, 0.86, 1),
    ] as CFArray, locations: [0.0, 0.55, 1.0])!
    cg.drawLinearGradient(base,
                          start: CGPoint(x: plateRect.midX, y: plateRect.maxY),
                          end: CGPoint(x: plateRect.midX, y: plateRect.minY), options: [])

    // ② 顶部中央柔和径向高光（模拟光源）
    let glow = CGGradient(colorsSpace: space, colors: [
        deviceColor(1, 1, 1, 0.32), deviceColor(1, 1, 1, 0.0),
    ] as CFArray, locations: [0.0, 1.0])!
    let glowCenter = CGPoint(x: plateRect.midX, y: plateRect.maxY - plate * 0.10)
    cg.drawRadialGradient(glow, startCenter: glowCenter, startRadius: 0,
                          endCenter: glowCenter, endRadius: plate * 0.62, options: [])

    // ③ 底缘 vignette 轻微加深
    let vignette = CGGradient(colorsSpace: space, colors: [
        deviceColor(0, 0, 0, 0.0), deviceColor(0, 0, 0, 0.13),
    ] as CFArray, locations: [0.0, 1.0])!
    cg.drawLinearGradient(vignette,
                          start: CGPoint(x: plateRect.midX, y: plateRect.minY + plate * 0.34),
                          end: CGPoint(x: plateRect.midX, y: plateRect.minY), options: [])
    cg.restoreGState()

    // ④ 顶部内侧极细 specular 亮边：描边路径做剪裁，只在上沿渐显
    cg.saveGState()
    let rimWidth = max(plate * 0.006, 1)
    let rimPath = CGPath(roundedRect: plateRect.insetBy(dx: rimWidth / 2, dy: rimWidth / 2),
                         cornerWidth: radius - rimWidth / 2, cornerHeight: radius - rimWidth / 2,
                         transform: nil)
        .copy(strokingWithWidth: rimWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
    cg.addPath(rimPath); cg.clip()
    let rimGrad = CGGradient(colorsSpace: space, colors: [
        deviceColor(1, 1, 1, 0.55), deviceColor(1, 1, 1, 0.0),
    ] as CFArray, locations: [0.0, 1.0])!
    cg.drawLinearGradient(rimGrad,
                          start: CGPoint(x: plateRect.midX, y: plateRect.maxY),
                          end: CGPoint(x: plateRect.midX, y: plateRect.maxY - plate * 0.30), options: [])
    cg.restoreGState()

    // ⑤ 玻璃叠层 glyph：三片圆角卡片，底→顶依次绘制，投影收在板内
    cg.saveGState()
    cg.addPath(platePath); cg.clip()
    let cardW = plate * variant.cardW
    let cardH = plate * variant.cardH
    let dy = plate * variant.dy
    let stackH = cardH + dy * 2
    // 光学居中：整体上移 2.5%
    let stackCenterY = plateRect.midY + plate * 0.025
    // 前片（不透明）在堆叠底部，后片依次从上方探出
    let frontCenterY = stackCenterY - stackH / 2 + cardH / 2

    for i in 0..<3 { // 0=后 1=中 2=前（绘制顺序后→前）
        let w = cardW * variant.scales[i]
        let h = cardH * variant.scales[i]
        let cx = plateRect.midX + plate * variant.xOffsets[i]
        let cy = frontCenterY + dy * CGFloat(2 - i)
        let rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        let r = h * 0.30
        let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)

        cg.saveGState()
        // 片间柔和投影：向下小 blur，制造分离
        cg.setShadow(offset: CGSize(width: 0, height: -plate * 0.012), blur: plate * 0.020,
                     color: deviceColor(0, 0, 0, 0.11))
        cg.addPath(path)
        cg.setFillColor(deviceColor(1, 1, 1, variant.alphas[i]))
        cg.fillPath()
        cg.restoreGState()

        // 前片避免大面积死白：叠一层极淡的白→冷白纵向渐变
        if i == 2 {
            cg.saveGState()
            cg.addPath(path); cg.clip()
            let frontGrad = CGGradient(colorsSpace: space, colors: [
                deviceColor(1, 1, 1, 0.0), deviceColor(0.87, 0.92, 1.0, 0.55),
            ] as CFArray, locations: [0.0, 1.0])!
            cg.drawLinearGradient(frontGrad,
                                  start: CGPoint(x: rect.midX, y: rect.maxY),
                                  end: CGPoint(x: rect.midX, y: rect.minY), options: [])
            cg.restoreGState()
        }

        // 顶片加极细顶边高光（增强玻璃感）
        if i == 2 {
            cg.saveGState()
            let edge = max(h * 0.035, 0.8)
            let edgePath = CGPath(roundedRect: rect.insetBy(dx: edge / 2, dy: edge / 2),
                                  cornerWidth: max(r - edge / 2, 1), cornerHeight: max(r - edge / 2, 1),
                                  transform: nil)
                .copy(strokingWithWidth: edge, lineCap: .round, lineJoin: .round, miterLimit: 10)
            cg.addPath(edgePath); cg.clip()
            let edgeGrad = CGGradient(colorsSpace: space, colors: [
                deviceColor(1, 1, 1, 0.9), deviceColor(1, 1, 1, 0.0),
            ] as CFArray, locations: [0.0, 1.0])!
            cg.drawLinearGradient(edgeGrad,
                                  start: CGPoint(x: rect.midX, y: rect.maxY),
                                  end: CGPoint(x: rect.midX, y: rect.maxY - h * 0.5), options: [])
            cg.restoreGState()
        }
    }
    cg.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) {
    guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("PNG 编码失败") }
    try! data.write(to: url)
}

// MARK: - 入口

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("""
    用法:
      render-icon preview <输出目录>
      render-icon iconset <iconset目录> [A|B|C]
    \n
    """.data(using: .utf8)!)
    exit(1)
}

let mode = args[1]
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

switch mode {
case "preview":
    var images: [(String, NSBitmapImageRep)] = []
    for key in ["A", "B", "C"] {
        let v = variants[key]!
        let rep = render(canvas: 512, variant: v)
        writePNG(rep, to: outDir.appendingPathComponent("variant-\(key).png"))
        images.append(("\(key) · \(v.note)", rep))
        print("生成 variant-\(key).png")
    }
    // 并排对比图
    let W = 512 * 3 + 16 * 4, H = 512 + 90
    let canvasRep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvasRep)
    NSColor(calibratedWhite: 0.93, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1)]
    for (i, (label, rep)) in images.enumerated() {
        let x = CGFloat(16 + i * (512 + 16))
        NSImage(size: rep.size).withRep(rep).draw(in: NSRect(x: x, y: 66, width: 512, height: 512))
        (label as NSString).draw(at: NSPoint(x: x + 150, y: 22), withAttributes: attrs)
    }
    NSGraphicsContext.restoreGraphicsState()
    writePNG(canvasRep, to: outDir.appendingPathComponent("variants-compare.png"))
    print("生成 variants-compare.png")

case "iconset":
    let key = args.count >= 4 ? args[3] : "A"
    guard let v = variants[key] else { FileHandle.standardError.write("未知变体 \(key)\n".data(using: .utf8)!); exit(1) }
    let specs: [(Int, String)] = [
        (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
    ]
    for (size, name) in specs {
        writePNG(render(canvas: size, variant: v), to: outDir.appendingPathComponent(name))
        print("生成 \(name) (\(size)px)")
    }
    print("完成（变体 \(key)）：\(outDir.path)")

default:
    FileHandle.standardError.write("未知模式 \(mode)\n".data(using: .utf8)!)
    exit(1)
}

extension NSImage {
    func withRep(_ rep: NSBitmapImageRep) -> NSImage {
        addRepresentation(rep)
        return self
    }
}
