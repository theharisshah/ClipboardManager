// generate-icon.swift — Clipboard Manager app icon ("clipboard with history")
//
// Usually run through scripts/make-icon.sh, which updates assets/AppIcon.icns and assets/AppIcon.png.
// Build & run:  swiftc -O generate-icon.swift -o generate-icon && ./generate-icon <outdir>
// Writes:       <outdir>/AppIcon-1024.png    RGBA, transparent margins
//               <outdir>/AppIcon.iconset/    every macOS size, each rendered natively
//               <outdir>/AppIcon.icns        via /usr/bin/iconutil, when it is available
//               <outdir>/preview.png         sizes, light/dark, Dock, Finder list, README
// ICON_DEBUG=1  also writes <outdir>/debug-<px>.png: nearest-neighbour blow-ups of the
//               16/32/64/128 px renders on light, dark and Finder-selection backgrounds.
//
// Only AppKit + CoreGraphics; every shape is drawn by hand (no SF Symbols, no assets).

import AppKit
import CoreGraphics

// MARK: - Color helpers

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: a)
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: sRGB,
               colors: stops.map { $0.1 } as CFArray,
               locations: stops.map { $0.0 })!
}

/// Mixes `c` toward white by `t` (0...1), keeping alpha.
func lighten(_ c: CGColor, _ t: CGFloat) -> CGColor {
    let k = c.converted(to: sRGB, intent: .defaultIntent, options: nil)!.components!
    return CGColor(srgbRed: k[0] + (1 - k[0]) * t, green: k[1] + (1 - k[1]) * t, blue: k[2] + (1 - k[2]) * t, alpha: k[3])
}

// MARK: - Geometry helpers

/// Rounded rect with Apple-style *continuous* corners (curvature-continuous
/// approximation of a superellipse corner, as used for the macOS/iOS icon mask).
func continuousRect(_ rect: CGRect, radius r0: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let k: CGFloat = 1.52866483
    let r = min(r0, min(rect.width, rect.height) / 2 / k)
    func tl(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * r, y: rect.minY + y * r) }
    func tr(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.maxX - x * r, y: rect.minY + y * r) }
    func br(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.maxX - x * r, y: rect.maxY - y * r) }
    func bl(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * r, y: rect.maxY - y * r) }
    p.move(to: tl(k, 0))
    p.addLine(to: tr(k, 0))
    p.addCurve(to: tr(0.66993427, 0.06549600), control1: tr(1.08849323, 0), control2: tr(0.86840689, 0))
    p.addLine(to: tr(0.63149399, 0.07491100))
    p.addCurve(to: tr(0.07491176, 0.63149399), control1: tr(0.37282392, 0.16905899), control2: tr(0.16906013, 0.37282401))
    p.addCurve(to: tr(0, k), control1: tr(0, 0.86840701), control2: tr(0, 1.08849299))
    p.addLine(to: br(0, k))
    p.addCurve(to: br(0.06549600, 0.66993427), control1: br(0, 1.08849323), control2: br(0, 0.86840689))
    p.addLine(to: br(0.07491100, 0.63149399))
    p.addCurve(to: br(0.63149399, 0.07491176), control1: br(0.16905899, 0.37282392), control2: br(0.37282401, 0.16906013))
    p.addCurve(to: br(k, 0), control1: br(0.86840701, 0), control2: br(1.08849299, 0))
    p.addLine(to: bl(k, 0))
    p.addCurve(to: bl(0.66993427, 0.06549600), control1: bl(1.08849323, 0), control2: bl(0.86840689, 0))
    p.addLine(to: bl(0.63149399, 0.07491100))
    p.addCurve(to: bl(0.07491176, 0.63149399), control1: bl(0.37282392, 0.16905899), control2: bl(0.16906013, 0.37282401))
    p.addCurve(to: bl(0, k), control1: bl(0, 0.86840701), control2: bl(0, 1.08849299))
    p.addLine(to: tl(0, k))
    p.addCurve(to: tl(0.06549600, 0.66993427), control1: tl(0, 1.08849323), control2: tl(0, 0.86840689))
    p.addLine(to: tl(0.07491100, 0.63149399))
    p.addCurve(to: tl(0.63149399, 0.07491176), control1: tl(0.16905899, 0.37282392), control2: tl(0.37282401, 0.16906013))
    p.addCurve(to: tl(k, 0), control1: tl(0.86840701, 0), control2: tl(1.08849299, 0))
    p.closeSubpath()
    return p
}

func roundRect(_ rect: CGRect, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: min(r, rect.width / 2), cornerHeight: min(r, rect.height / 2), transform: nil)
}

/// The clipboard clip: a wide plate with a raised tab, built as one outline (y-down).
func clipOutline(cx: CGFloat, tabTop: CGFloat, shoulder: CGFloat, bottom: CGFloat,
                 plateHalf: CGFloat, tabHalf: CGFloat,
                 rPlate: CGFloat, rTab: CGFloat, rFillet: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx, y: bottom))
    p.addArc(tangent1End: CGPoint(x: cx - plateHalf, y: bottom), tangent2End: CGPoint(x: cx - plateHalf, y: shoulder), radius: rPlate)
    p.addArc(tangent1End: CGPoint(x: cx - plateHalf, y: shoulder), tangent2End: CGPoint(x: cx - tabHalf, y: shoulder), radius: rPlate)
    p.addArc(tangent1End: CGPoint(x: cx - tabHalf, y: shoulder), tangent2End: CGPoint(x: cx - tabHalf, y: tabTop), radius: rFillet)
    p.addArc(tangent1End: CGPoint(x: cx - tabHalf, y: tabTop), tangent2End: CGPoint(x: cx + tabHalf, y: tabTop), radius: rTab)
    p.addArc(tangent1End: CGPoint(x: cx + tabHalf, y: tabTop), tangent2End: CGPoint(x: cx + tabHalf, y: shoulder), radius: rTab)
    p.addArc(tangent1End: CGPoint(x: cx + tabHalf, y: shoulder), tangent2End: CGPoint(x: cx + plateHalf, y: shoulder), radius: rFillet)
    p.addArc(tangent1End: CGPoint(x: cx + plateHalf, y: shoulder), tangent2End: CGPoint(x: cx + plateHalf, y: bottom), radius: rPlate)
    p.addArc(tangent1End: CGPoint(x: cx + plateHalf, y: bottom), tangent2End: CGPoint(x: cx, y: bottom), radius: rPlate)
    p.closeSubpath()
    return p
}

// MARK: - Badge glyphs (hand-drawn, echoing the app's type badges)

enum Glyph { case link, code, json, email, number }

/// Strokes glyph `g` centred in badge rect `b` (y-down grid units).
/// `weight` is the stroke width as a fraction of the badge size.
func drawGlyph(_ g: Glyph, in b: CGRect, ctx: CGContext, color: CGColor, weight: CGFloat = 0.085) {
    let u = b.width
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: b.minX + x * u, y: b.minY + y * u) }
    ctx.saveGState()
    ctx.setStrokeColor(color)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(weight * u)
    switch g {
    case .link:
        // two interlocking rounded links on a 45° diagonal
        ctx.translateBy(x: b.midX, y: b.midY)
        ctx.rotate(by: -.pi / 4)
        let heavy = weight > 0.1
        let w = (heavy ? 0.44 : 0.40) * u, h = (heavy ? 0.28 : 0.24) * u, off = (heavy ? 0.13 : 0.14) * u
        for dx in [-off, off] {
            ctx.addPath(roundRect(CGRect(x: dx - w / 2, y: -h / 2, width: w, height: h), h / 2))
        }
        ctx.strokePath()
    case .code:
        ctx.move(to: P(0.35, 0.32)); ctx.addLine(to: P(0.21, 0.5)); ctx.addLine(to: P(0.35, 0.68))
        ctx.move(to: P(0.65, 0.32)); ctx.addLine(to: P(0.79, 0.5)); ctx.addLine(to: P(0.65, 0.68))
        ctx.move(to: P(0.56, 0.28)); ctx.addLine(to: P(0.44, 0.72))
        ctx.strokePath()
    case .json:
        for flip in [false, true] {
            let sx: CGFloat = flip ? -1 : 1
            func Q(_ x: CGFloat, _ y: CGFloat) -> CGPoint { P(0.5 + sx * (x - 0.5), y) }
            ctx.move(to: Q(0.40, 0.27))
            ctx.addCurve(to: Q(0.32, 0.40), control1: Q(0.33, 0.27), control2: Q(0.32, 0.31))
            ctx.addCurve(to: Q(0.24, 0.50), control1: Q(0.32, 0.47), control2: Q(0.29, 0.50))
            ctx.addCurve(to: Q(0.32, 0.60), control1: Q(0.29, 0.50), control2: Q(0.32, 0.53))
            ctx.addCurve(to: Q(0.40, 0.73), control1: Q(0.32, 0.69), control2: Q(0.33, 0.73))
        }
        ctx.strokePath()
    case .email:
        ctx.addPath(roundRect(CGRect(x: b.minX + 0.21 * u, y: b.minY + 0.30 * u, width: 0.58 * u, height: 0.40 * u), 0.07 * u))
        ctx.move(to: P(0.23, 0.33)); ctx.addLine(to: P(0.5, 0.53)); ctx.addLine(to: P(0.77, 0.33))
        ctx.strokePath()
    case .number:
        ctx.move(to: P(0.43, 0.24)); ctx.addLine(to: P(0.37, 0.76))
        ctx.move(to: P(0.63, 0.24)); ctx.addLine(to: P(0.57, 0.76))
        ctx.move(to: P(0.26, 0.40)); ctx.addLine(to: P(0.76, 0.40))
        ctx.move(to: P(0.24, 0.60)); ctx.addLine(to: P(0.74, 0.60))
        ctx.strokePath()
    }
    ctx.restoreGState()
}

// MARK: - Palette (from the app UI)

let bodyTop = rgb(0x5297FF)          // azure, lit from above
let bodyBottom = rgb(0x1A44B8)       // cobalt: still clearly blue, a step away from Finder's selection blue
let accentTop = rgb(0x3A8DFF)        // the popover's selected-row accent
let accentBottom = rgb(0x0A64E2)
let tintCode = rgb(0xB24BE6), tintEmail = rgb(0x2FBE57), tintNumber = rgb(0xFF9A0A), tintJSON = rgb(0xFF4F7B)
let clipTop = rgb(0x7D8AA1), clipMid = rgb(0x4E5A6E), clipBottom = rgb(0x323C4C)   // blue-tinted graphite

struct Row { let glyph: Glyph; let tint: CGColor?; let title: CGFloat; let meta: CGFloat }
/// Newest first, like the popover: the selected link, then code, email and a number.
let rows: [Row] = [
    Row(glyph: .link,   tint: nil,        title: 0.82, meta: 0.46),   // selected (accent)
    Row(glyph: .code,   tint: tintCode,   title: 0.70, meta: 0.38),
    Row(glyph: .email,  tint: tintEmail,  title: 0.90, meta: 0.30),
    Row(glyph: .number, tint: tintNumber, title: 0.52, meta: 0.42),
]

// MARK: - The icon

enum Tier {
    case tiny     // <= 20 px  (16): hand-placed pixels
    case small    // <= 40 px  (32): hand-placed pixels
    case medium   // <= 100 px (48-96): regular layout, snapped, no meta lines or slot
    case regular  // > 100 px: full layout; snapped to whole pixels below 256
    init(_ size: CGFloat) {
        self = size <= 20 ? .tiny : size <= 40 ? .small : size <= 100 ? .medium : .regular
    }
}

/// Draws the full icon (body + shadow + artwork) into a size x size square of `ctx`
/// (origin bottom-left, as CoreGraphics bitmap contexts are).
/// Resolution independent: authored on a 1024-unit grid (y-down) and scaled to `size`.
/// Below 256 px every mark is snapped to whole device pixels, and at 16 and 32 px the
/// artwork is re-drawn as a pixel-placed variant (hand-hinting, as Apple does).
func draw(in ctx: CGContext, size: CGFloat) {
    let s = size / 1024
    let u = 1024 / size                 // grid units per device pixel
    let tier = Tier(size)
    let hinted = size < 256
    ctx.saveGState()
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: s, y: -s)

    // ---- Small helpers ------------------------------------------------------------
    func snap(_ v: CGFloat) -> CGFloat { hinted ? (v / u).rounded() * u : v }
    func snapped(_ r: CGRect) -> CGRect {
        guard hinted else { return r }
        let x0 = snap(r.minX), y0 = snap(r.minY)
        return CGRect(x: x0, y: y0, width: max(snap(r.maxX) - x0, u), height: max(snap(r.maxY) - y0, u))
    }
    /// Whole-pixel span of half-width `half` around centre `c` (centre snapped first, so
    /// both edges land on pixel boundaries and the span stays symmetric).
    func span(_ c: CGFloat, _ half: CGFloat) -> (CGFloat, CGFloat) {
        guard hinted else { return (c - half, c + half) }
        let cp = (c / u).rounded(), hp = max((half / u).rounded(), 1)
        return ((cp - hp) * u, (cp + hp) * u)
    }
    // Shadows are specified in device space, so convert from grid units here.
    func shadow(dy: CGFloat, blur: CGFloat, _ color: CGColor) {
        ctx.setShadow(offset: CGSize(width: 0, height: -dy * s), blur: blur * s, color: color)
    }
    func fill(_ path: CGPath, _ color: CGColor) {
        ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
    }
    func fillGradient(_ path: CGPath, _ g: CGGradient, from y0: CGFloat, to y1: CGFloat) {
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }
    /// Clip to the band along the upward-facing edges of `path` (path minus itself moved down).
    func clipToTopEdge(_ path: CGPath, dy: CGFloat) {
        var t = CGAffineTransform(translationX: 0, y: dy)
        ctx.addPath(path)
        ctx.clip()
        ctx.addRect(CGRect(x: -1024, y: -1024, width: 3072, height: 3072))
        ctx.addPath(path.copy(using: &t)!)
        ctx.clip(using: .evenOdd)
    }

    // ---- Body ---------------------------------------------------------------------
    // 824-unit squircle with 100-unit margins; at 16/32 px the body is snapped to whole
    // pixels (1..15 and 3..29) so no half-transparent ring surrounds it.
    let bodyRect: CGRect
    switch tier {
    case .tiny, .small:
        let m = (size * 100 / 1024).rounded(.down)
        bodyRect = CGRect(x: m * u, y: m * u, width: (size - 2 * m) * u, height: (size - 2 * m) * u)
    case .medium, .regular:
        bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    }
    let body = continuousRect(bodyRect, radius: bodyRect.width * 185 / 824)

    ctx.saveGState()
    shadow(dy: 12, blur: 28, rgb(0x000000, 0.28))
    fill(body, bodyBottom)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, bodyTop), (1, bodyBottom)]),
                           start: CGPoint(x: 0, y: bodyRect.minY), end: CGPoint(x: 0, y: bodyRect.maxY), options: [])
    ctx.drawRadialGradient(gradient([(0, rgb(0xFFFFFF, 0.14)), (1, rgb(0xFFFFFF, 0))]),
                           startCenter: CGPoint(x: 512, y: 60), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 60), endRadius: 640, options: [])

    switch tier {
    case .tiny, .small:
        drawPixelArt()
    case .medium, .regular:
        drawArt()
    }

    ctx.restoreGState() // end body clip

    // ---- Body edge ----------------------------------------------------------------
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.addPath(body)
    if tier == .tiny || tier == .small {
        // 1 px inner rim, darker toward the bottom and sides, so the squircle survives
        // on Finder's blue selection and on pale backgrounds.
        ctx.setLineWidth(2 * u)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(gradient([(0, rgb(0x001040, 0.0)), (0.3, rgb(0x001040, 0.14)), (1, rgb(0x001040, 0.30))]),
                               start: CGPoint(x: 0, y: bodyRect.minY), end: CGPoint(x: 0, y: bodyRect.maxY), options: [])
    } else {
        // Thin inner rim light: brightest along the top edge.
        ctx.setLineWidth(4)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.32)), (0.5, rgb(0xFFFFFF, 0.06)), (1, rgb(0xFFFFFF, 0.10))]),
                               start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    }
    ctx.restoreGState()

    ctx.restoreGState()

    // =================================================================================
    // Full artwork (48 px and up)
    // =================================================================================
    func drawArt() {
        let showMeta = size > 100
        let showSlot = size > 100
        let allGlyphs = size >= 256
        let heroGlyph = size > 100            // the selected row's link glyph from 112/128 px
        let glyphWeight: CGFloat = allGlyphs ? 0.085 : 0.15

        // Front sheet, centred on the body's vertical axis (x = 512 - 16 keeps the
        // white mass + the fan behind it optically centred).
        let cx: CGFloat = 496
        let (sx0, sx1) = span(cx, 224)
        let sheet = CGRect(x: sx0, y: snap(256), width: sx1 - sx0, height: snap(832) - snap(256))
        let axis = sheet.midX
        let sheetPath = continuousRect(sheet, radius: 46)

        // ---- History: older clips fanned out behind, fogged toward the body colour ----
        // Pivot sits above the sheet's bottom-right corner, so the fanned sheets emerge
        // from behind the front sheet instead of meeting in one corner.
        let pivot = CGPoint(x: sheet.maxX - 40, y: sheet.maxY - 90)
        // Each older sheet is also a little smaller (further away); the scale is chosen so
        // its top-left corner stays tucked behind the front sheet and its bottom never shows.
        struct Back { let angle: CGFloat; let scale: CGFloat; let top: UInt32; let bottom: UInt32
                      let shadowAlpha: CGFloat; let ghost: Bool }
        let backs = [
            Back(angle: 10.5, scale: 0.86, top: 0xA9C8FF, bottom: 0x7FA6F0, shadowAlpha: 0.38, ghost: false),
            Back(angle: 5.25, scale: 0.91, top: 0xE4EEFF, bottom: 0xC6D8FA, shadowAlpha: 0.30, ghost: true),
        ]
        for b in backs {
            ctx.saveGState()
            ctx.translateBy(x: pivot.x, y: pivot.y)
            ctx.rotate(by: b.angle * .pi / 180)
            ctx.scaleBy(x: b.scale, y: b.scale)
            ctx.translateBy(x: -pivot.x, y: -pivot.y)
            ctx.saveGState()
            shadow(dy: 10, blur: 20, rgb(0x031A4A, b.shadowAlpha))
            fill(sheetPath, rgb(b.bottom))
            ctx.restoreGState()
            fillGradient(sheetPath, gradient([(0, rgb(b.top)), (1, rgb(b.bottom))]), from: sheet.minY, to: sheet.maxY)
            if b.ghost && size >= 256 {   // below 256 px the peek is a 1-2 px pink artifact
                // A ghost of that older clip's own selected row (a JSON item, pink) peeks out
                // past the front sheet's right edge: the history holds earlier clips.
                ctx.saveGState()
                ctx.addPath(sheetPath); ctx.clip()
                let band = CGRect(x: sheet.minX + 24, y: 348, width: sheet.width - 38, height: 104)
                fill(continuousRect(band, radius: 22), rgb(0xFF4F7B, 0.42))
                ctx.restoreGState()
            }
            // crisp, slightly darker edge so each sheet separates from what is behind it
            ctx.saveGState()
            ctx.addPath(sheetPath); ctx.clip()
            ctx.addPath(sheetPath); ctx.setLineWidth(3); ctx.setStrokeColor(rgb(0x1E4FB4, 0.30)); ctx.strokePath()
            ctx.restoreGState()
            ctx.restoreGState()
        }

        // ---- Front sheet ---------------------------------------------------------------
        ctx.saveGState()
        shadow(dy: 16, blur: 34, rgb(0x031A4A, 0.40))
        fill(sheetPath, rgb(0xF4F7FB))
        ctx.restoreGState()
        fillGradient(sheetPath, gradient([(0, rgb(0xFFFFFF)), (1, rgb(0xEAEFF6))]), from: sheet.minY, to: sheet.maxY)

        // ---- Rows: the popover list in miniature ---------------------------------------
        let centers: [CGFloat] = [400, 528, 632, 736]
        let badgeSize: CGFloat = 52
        let badgeX = sheet.minX + 48
        let textX = badgeX + badgeSize + 24
        let textMax = sheet.maxX - 48 - textX
        for (i, r) in rows.enumerated() {
            let c = centers[i]
            // Badges stay square and an even number of pixels, so the 2 px text bars centre on them.
            let bs = hinted ? max(1, (badgeSize / u / 2).rounded()) * 2 * u : badgeSize
            let bc = snap(c)           // snapped row centre
            let badge = CGRect(x: snap(badgeX), y: bc - bs / 2, width: bs, height: bs)
            // Title and meta lines: never thinner than 2 device px, always 1 px apart.
            var title: CGRect, meta: CGRect?
            if showMeta {
                title = snapped(CGRect(x: textX, y: bc - 17, width: textMax * r.title, height: max(16, 2 * u)))
                let mh = max(11, 2 * u)
                var m = snapped(CGRect(x: textX, y: bc + 8, width: textMax * r.meta, height: mh))
                if hinted && m.minY < title.maxY + u { m.origin.y = title.maxY + u }
                meta = m
            } else {
                let th = max(16, 2 * u)
                title = snapped(CGRect(x: textX, y: bc - th / 2, width: textMax * r.title, height: th))
                meta = nil
            }
            let titlePath = roundRect(title, title.height / 2), metaPath = meta.map { roundRect($0, $0.height / 2) }

            if let tint = r.tint {
                // Older items fade slightly with age (newest first).
                let age = CGFloat(i - 1)
                let t = lighten(tint, 0.06 * age)
                fillGradient(continuousRect(badge, radius: 14), gradient([(0, lighten(t, 0.18)), (1, t)]),
                             from: badge.minY, to: badge.maxY)
                if allGlyphs { drawGlyph(r.glyph, in: badge, ctx: ctx, color: rgb(0xFFFFFF)) }
                let titleGray = hinted ? rgb(0xA9B4C4) : lighten(rgb(0xB3BECC), 0.08 * age)
                fill(titlePath, titleGray)
                if let mp = metaPath { fill(mp, hinted ? rgb(0xCDD5E0) : lighten(rgb(0xD5DCE6), 0.10 * age)) }
            } else {
                // Selected row in the system accent blue, as in the popover; a touch wider
                // and taller than the others so it reads first.
                let (bx0, bx1) = span(axis, sheet.width / 2 - 24)
                let bandRect = CGRect(x: bx0, y: snap(c - 52), width: bx1 - bx0, height: snap(c + 52) - snap(c - 52))
                let band = continuousRect(bandRect, radius: 22)
                ctx.saveGState()
                shadow(dy: 4, blur: 9, rgb(0x0A3FA8, 0.32))
                fill(band, accentBottom)
                ctx.restoreGState()
                fillGradient(band, gradient([(0, accentTop), (1, accentBottom)]), from: bandRect.minY, to: bandRect.maxY)
                // soft top highlight on the band
                ctx.saveGState()
                clipToTopEdge(band, dy: max(3, u))
                ctx.setFillColor(rgb(0xFFFFFF, 0.28)); ctx.fill(bandRect)
                ctx.restoreGState()
                fill(continuousRect(badge, radius: 14), rgb(0xFFFFFF, 0.26))
                if heroGlyph { drawGlyph(r.glyph, in: badge, ctx: ctx, color: rgb(0xFFFFFF), weight: glyphWeight) }
                fill(titlePath, rgb(0xFFFFFF))
                if let mp = metaPath { fill(mp, rgb(0xFFFFFF, 0.62)) }
            }
        }

        // ---- Clip ----------------------------------------------------------------------
        // Blue-tinted graphite, lit from above; never the darkest value in the icon.
        let tabTop = snap(184), shoulder = snap(234), plateBottom = snap(314)
        let (px0, px1) = span(axis, hinted ? 128 : 120)
        let (tx0, tx1) = span(axis, 64)
        let clipPath = clipOutline(cx: axis, tabTop: tabTop, shoulder: shoulder, bottom: plateBottom,
                                   plateHalf: (px1 - px0) / 2, tabHalf: (tx1 - tx0) / 2,
                                   rPlate: 24, rTab: 34, rFillet: 16)
        let slotRect: CGRect = {
            let (x0, x1) = span(axis, hinted ? 32 : 30)
            return CGRect(x: x0, y: snap(tabTop + 16), width: x1 - x0, height: max(snap(22), 2 * u))
        }()
        let slot = showSlot ? roundRect(slotRect, slotRect.height / 2) : CGPath(rect: .zero, transform: nil)

        ctx.saveGState()
        ctx.addRect(CGRect(x: -1024, y: -1024, width: 3072, height: 3072))
        ctx.addPath(slot)
        ctx.clip(using: .evenOdd)               // punch the slot through the clip
        ctx.saveGState()
        shadow(dy: 10, blur: 18, rgb(0x00102E, 0.34))
        fill(clipPath, clipMid)
        ctx.restoreGState()
        fillGradient(clipPath, gradient([(0, clipTop), (0.5, clipMid), (1, clipBottom)]), from: tabTop, to: plateBottom)
        // Top-lit bevel: only the upward-facing edges catch the light.
        ctx.saveGState()
        clipToTopEdge(clipPath, dy: max(5, u))
        ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0.50)), (0.5, rgb(0xFFFFFF, 0.22)), (1, rgb(0xFFFFFF, 0.10))]),
                               start: CGPoint(x: 0, y: tabTop), end: CGPoint(x: 0, y: plateBottom), options: [])
        ctx.restoreGState()
        ctx.restoreGState()

        // Depth inside the slot: its upper inner wall is in shadow.
        if showSlot {
            ctx.saveGState()
            clipToTopEdge(slot, dy: max(6, u))
            ctx.setFillColor(rgb(0x00102E, 0.40))
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
            ctx.restoreGState()
        }
    }

    // =================================================================================
    // Pixel-placed artwork for 16 and 32 px (coordinates in device pixels from centre)
    // =================================================================================
    func drawPixelArt() {
        let c = (size / 2).rounded(.down)
        func P(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: (c + x0) * u, y: (c + y0) * u, width: (x1 - x0) * u, height: (y1 - y0) * u)
        }
        func px(_ r: CGRect, _ color: CGColor) { ctx.setFillColor(color); ctx.fill(r) }
        let gray = rgb(0xA9B4C4)

        if tier == .tiny {
            // 16 px: 8x10 sheet, 2-row clip, blue selection band and two badge rows.
            let sheet = P(-4, -5, 4, 5)
            ctx.saveGState()
            shadow(dy: 0.6 * u, blur: 1.2 * u, rgb(0x031A4A, 0.45))
            fill(continuousRect(sheet, radius: 0.7 * u), rgb(0xFFFFFF))
            ctx.restoreGState()
            fillGradient(CGPath(rect: P(-3, -3, 3, -1), transform: nil), gradient([(0, rgb(0x2F86FF)), (1, accentBottom)]),
                         from: P(0, -3, 0, -1).minY, to: P(0, -3, 0, -1).maxY)
            px(P(-3, 0, -2, 1), tintCode);  px(P(-1, 0, 3, 1), gray)
            px(P(-3, 2, -2, 3), tintEmail); px(P(-1, 2, 2, 3), gray)
            // clip: 4 px tab over a 6 px plate
            let clip = clipOutline(cx: c * u, tabTop: (c - 6) * u, shoulder: (c - 5) * u, bottom: (c - 4) * u,
                                   plateHalf: 3 * u, tabHalf: 2 * u, rPlate: 0.01, rTab: 0.5 * u, rFillet: 0.01)
            fillGradient(clip, gradient([(0, rgb(0x4A5568)), (1, rgb(0x232B38))]), from: (c - 6) * u, to: (c - 4) * u)
        } else {
            // 32 px: 14x18 sheet, clip, selection band with badge + two lines, three rows.
            let sheet = P(-7, -8, 7, 10)
            // the history, reduced to one hard 1 px column peeking out on the right
            px(P(7, -4, 8, 8), rgb(0x86AEF6))
            ctx.saveGState()
            shadow(dy: 0.6 * u, blur: 1.4 * u, rgb(0x031A4A, 0.45))
            fill(continuousRect(sheet, radius: 1.2 * u), rgb(0xFFFFFF))
            ctx.restoreGState()
            let bandR = P(-6, -6, 6, -2)
            fillGradient(continuousRect(bandR, radius: 0.8 * u), gradient([(0, accentTop), (1, accentBottom)]),
                         from: bandR.minY, to: bandR.maxY)
            px(P(-5, -5, -3, -3), rgb(0xFFFFFF, 0.45))
            px(P(-2, -5, 5, -3), rgb(0xFFFFFF))
            // rows: 2x2 badge + one solid 2 px line (two-tone 1 px lines read as blur)
            let tints = [tintCode, tintEmail, tintNumber]
            let lineEnd: [CGFloat] = [3, 5, 2]
            for i in 0..<3 {
                let y0 = CGFloat(i * 3)
                px(P(-5, y0, -3, y0 + 2), tints[i])
                px(P(-2, y0, lineEnd[i], y0 + 2), rgb(0xBCC6D3))
            }
            let clip = clipOutline(cx: c * u, tabTop: (c - 11) * u, shoulder: (c - 9) * u, bottom: (c - 7) * u,
                                   plateHalf: 5 * u, tabHalf: 2 * u, rPlate: 0.5 * u, rTab: 0.9 * u, rFillet: 0.01)
            ctx.saveGState()
            shadow(dy: 0.5 * u, blur: 0.8 * u, rgb(0x00102E, 0.30))
            fill(clip, rgb(0x2E3746))
            ctx.restoreGState()
            fillGradient(clip, gradient([(0, rgb(0x667389)), (0.5, rgb(0x3E4859)), (1, rgb(0x2A3240))]),
                         from: (c - 11) * u, to: (c - 7) * u)
        }
    }
}

// MARK: - Offscreen rendering

func makeRep(_ w: Int, _ h: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        .retagging(with: .sRGB)!
    rep.size = NSSize(width: w, height: h)
    return rep
}

func render(_ w: Int, _ h: Int, _ body: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = makeRep(w, h)
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g
    let ctx = g.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    body(ctx)
    g.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

var iconCache: [Int: NSBitmapImageRep] = [:]
func renderIcon(_ px: Int) -> NSBitmapImageRep {
    if let r = iconCache[px] { return r }
    let r = render(px, px) { draw(in: $0, size: CGFloat(px)) }
    iconCache[px] = r
    return r
}

func writePNG(_ rep: NSBitmapImageRep, _ url: URL) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed for \(url.path)")
    }
    do { try data.write(to: url) } catch { fatalError("Cannot write \(url.path): \(error)") }
}

/// Placeholder "app" for the Dock mocks (same body geometry, no artwork).
func drawPlaceholder(in ctx: CGContext, size: CGFloat, top: UInt32, bottom: UInt32, mark: UInt32? = nil) {
    let s = size / 1024
    ctx.saveGState()
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: s, y: -s)
    let body = continuousRect(CGRect(x: 100, y: 100, width: 824, height: 824), radius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12 * s), blur: 28 * s, color: rgb(0, 0.28))
    ctx.addPath(body)
    ctx.setFillColor(rgb(bottom))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.drawLinearGradient(gradient([(0, rgb(top)), (1, rgb(bottom))]),
                           start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    if let m = mark {   // a generic white disc, so blue neighbours look like real apps
        ctx.setFillColor(rgb(m, 0.9))
        ctx.fillEllipse(in: CGRect(x: 312, y: 312, width: 400, height: 400))
    }
    ctx.restoreGState()
}

// MARK: - Preview sheet

func makePreview() -> NSBitmapImageRep {
    let W = 1600, panelH = 690, readmeH = 230, H = panelH * 2 + readmeH
    let sizes = [256, 128, 64, 32, 16]
    func placeholder(_ px: Int, _ top: UInt32, _ bottom: UInt32, _ mark: UInt32? = nil) -> CGImage {
        render(px, px) { drawPlaceholder(in: $0, size: CGFloat(px), top: top, bottom: bottom, mark: mark) }.cgImage!
    }
    let ph1 = placeholder(112, 0xD9DCE1, 0xA9AFB8), ph2 = placeholder(112, 0x6E7480, 0x3E434C)
    let blues = [placeholder(96, 0x6BC0FF, 0x1C74E8, 0xFFFFFF), placeholder(96, 0x4FA8FF, 0x0D5BD8, 0xE8F2FF),
                 placeholder(96, 0x5FD0FF, 0x1A8CF0, 0xFFFFFF)]
    let ph16 = placeholder(16, 0xD9DCE1, 0xA9AFB8)

    return render(W, H) { ctx in
        ctx.translateBy(x: 0, y: CGFloat(H))
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

        func image(_ img: CGImage, _ r: CGRect, smooth: Bool = false) {
            ctx.saveGState()
            ctx.interpolationQuality = smooth ? .high : .none
            ctx.translateBy(x: r.minX, y: r.maxY)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(img, in: CGRect(origin: .zero, size: r.size))
            ctx.restoreGState()
        }
        func icon(_ px: Int, _ x: CGFloat, _ y: CGFloat, zoom: CGFloat = 1) {
            image(renderIcon(px).cgImage!, CGRect(x: x, y: y, width: CGFloat(px) * zoom, height: CGFloat(px) * zoom))
        }
        func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ color: NSColor, center: Bool = true,
                   size: CGFloat = 15, weight: NSFont.Weight = .regular) {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color,
            ]
            let str = NSAttributedString(string: text, attributes: attrs)
            str.draw(at: NSPoint(x: center ? x - str.size().width / 2 : x, y: y))
        }
        func dockShelf(_ r: CGRect, dark: Bool) {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 20, color: rgb(0, dark ? 0.5 : 0.18))
            ctx.addPath(roundRect(r, 26))
            ctx.setFillColor(dark ? rgb(0x323234, 0.92) : rgb(0xFFFFFF, 0.72))
            ctx.fillPath()
            ctx.restoreGState()
            ctx.addPath(roundRect(r.insetBy(dx: 0.5, dy: 0.5), 26))
            ctx.setStrokeColor(dark ? rgb(0xFFFFFF, 0.14) : rgb(0x000000, 0.08))
            ctx.setLineWidth(1)
            ctx.strokePath()
        }

        for (pi, dark) in [false, true].enumerated() {
            let oy = CGFloat(pi * panelH)
            ctx.setFillColor(dark ? rgb(0x1E1E1E) : rgb(0xF5F5F7))
            ctx.fill(CGRect(x: 0, y: oy, width: CGFloat(W), height: CGFloat(panelH)))
            let fg = dark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.12, alpha: 1)
            let dim = dark ? NSColor(white: 0.6, alpha: 1) : NSColor(white: 0.45, alpha: 1)
            label(dark ? "Dark background (#1E1E1E)" : "Light background (#F5F5F7)", 48, oy + 26, fg,
                  center: false, size: 17, weight: .semibold)

            // Size row, bottom-aligned. Each size is rendered natively, never downscaled.
            let baseline = oy + 70 + 360
            var x: CGFloat = 48
            image(renderIcon(1024).cgImage!, CGRect(x: x, y: baseline - 360, width: 360, height: 360), smooth: true)
            label("1024 (shown at 360)", x + 180, baseline + 12, dim)
            x += 360 + 44
            for sz in sizes {
                let f = CGFloat(sz)
                icon(sz, x, baseline - f)
                label("\(sz)", x + f / 2, baseline + 12, dim)
                x += f + 44
            }
            // Nearest-neighbour zooms of the hand-hinted sizes
            let zx: CGFloat = 1180
            icon(32, zx, baseline - 192, zoom: 6)
            label("32 px  ×6", zx + 96, baseline + 12, dim)
            icon(16, zx + 220, baseline - 128, zoom: 8)
            label("16 px  ×8", zx + 220 + 64, baseline + 12, dim)

            // Dock mocks: neutral neighbours, then saturated blue neighbours
            let dockY = baseline + 56
            let dock = CGRect(x: 48, y: dockY, width: 3 * 112 + 4 * 14, height: 132)
            dockShelf(dock, dark: dark)
            var dx = dock.minX + 14
            for (j, img) in [ph1, renderIcon(112).cgImage!, ph2].enumerated() {
                image(img, CGRect(x: dx, y: dockY + 10, width: 112, height: 112))
                if j == 1 {
                    ctx.setFillColor(dark ? rgb(0xFFFFFF, 0.75) : rgb(0x000000, 0.55))
                    ctx.fillEllipse(in: CGRect(x: dx + 53, y: dock.maxY - 9, width: 6, height: 6))
                }
                dx += 112 + 14
            }
            label("Dock, 112 px", dock.midX, dock.maxY + 10, dim)

            let dock2 = CGRect(x: dock.maxX + 28, y: dockY + 8, width: 4 * 96 + 5 * 12, height: 116)
            dockShelf(dock2, dark: dark)
            dx = dock2.minX + 12
            for img in [blues[0], renderIcon(96).cgImage!, blues[1], blues[2]] {
                image(img, CGRect(x: dx, y: dock2.minY + 10, width: 96, height: 96))
                dx += 96 + 12
            }
            label("Among blue Dock icons, 96 px", dock2.midX, dock.maxY + 10, dim)

            // Finder list mock: rows at 16 px (one selected) and an icon-view tile at 32 px
            let lx = dock2.maxX + 36, lw: CGFloat = 1600 - 48 - lx, ly = dockY
            ctx.setFillColor(dark ? rgb(0x2A2A2C) : rgb(0xFFFFFF))
            ctx.addPath(roundRect(CGRect(x: lx, y: ly, width: lw, height: 132), 10)); ctx.fillPath()
            let names = ["Calculator.app", "Clipboard Manager.app", "Clipboard Manager.app"]
            for j in 0..<3 {
                let ry = ly + 8 + CGFloat(j) * 26
                let selected = j == 1
                if selected {
                    ctx.setFillColor(rgb(0x0A64E2))
                    ctx.addPath(roundRect(CGRect(x: lx + 6, y: ry, width: 300, height: 24), 5)); ctx.fillPath()
                }
                image(j == 0 ? ph16 : renderIcon(16).cgImage!, CGRect(x: lx + 14, y: ry + 4, width: 16, height: 16))
                label(names[j], lx + 38, ry + 4, selected ? .white : fg, center: false, size: 13)
            }
            // 32 px on and off the selection (Finder icon view / About panel)
            let ty = ly + 92
            ctx.setFillColor(rgb(0x0A64E2))
            ctx.addPath(roundRect(CGRect(x: lx + 8, y: ty - 4, width: 40, height: 40), 6)); ctx.fillPath()
            icon(32, lx + 12, ty)
            icon(32, lx + 60, ty)
            label("32 px on selection / plain", lx + 102, ty + 8, dim, center: false, size: 12)
            // Zoom of the selected 16 px row
            let zr = CGRect(x: lx + 320, y: ly + 8, width: 24 * 4 + 16, height: 24 * 4)
            ctx.saveGState()
            ctx.addRect(zr); ctx.clip()
            ctx.setFillColor(rgb(0x0A64E2)); ctx.fill(zr)
            icon(16, zr.midX - 32, zr.midY - 32, zoom: 4)
            ctx.restoreGState()
            label("16 px on selection ×4", zr.midX, zr.maxY + 4, dim, size: 11)
            label("Finder list (#0A64E2 selection)", lx + lw / 2, dock.maxY + 10, dim)
        }

        // README header strip: GitHub light (#FFFFFF) and dark (#0D1117) at 128 px
        let ry = CGFloat(panelH * 2)
        for (j, bg) in [UInt32(0xFFFFFF), 0x0D1117].enumerated() {
            let rx = CGFloat(j * W / 2)
            ctx.setFillColor(rgb(bg)); ctx.fill(CGRect(x: rx, y: ry, width: CGFloat(W / 2), height: CGFloat(readmeH)))
            icon(128, rx + 48, ry + 51)
            let fg = j == 0 ? NSColor(srgbRed: 0.12, green: 0.14, blue: 0.16, alpha: 1) : NSColor(srgbRed: 0.90, green: 0.93, blue: 0.95, alpha: 1)
            label("Clipboard Manager", rx + 200, ry + 78, fg, center: false, size: 30, weight: .semibold)
            label("README header, 128 px on " + (j == 0 ? "#FFFFFF" : "#0D1117"), rx + 200, ry + 124,
                  fg.withAlphaComponent(0.6), center: false, size: 15)
        }
    }
}

/// Nearest-neighbour blow-up of one size on light, dark and Finder-selection backgrounds.
func makeDebug(_ px: Int) -> NSBitmapImageRep {
    let zoom = max(4, 256 / px), d = px * zoom, pad = 16
    return render(3 * d + 4 * pad, d + 2 * pad) { ctx in
        ctx.interpolationQuality = .none
        for (j, bg) in [UInt32(0xF5F5F7), 0x1E1E1E, 0x0A64E2].enumerated() {
            let x = CGFloat(pad + j * (d + pad))
            ctx.setFillColor(rgb(bg)); ctx.fill(CGRect(x: x - CGFloat(pad / 2), y: 0, width: CGFloat(d + pad), height: CGFloat(d + 2 * pad)))
            ctx.draw(renderIcon(px).cgImage!, in: CGRect(x: x, y: CGFloat(pad), width: CGFloat(d), height: CGFloat(d)))
        }
    }
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: \(args[0]) <outdir>\n".data(using: .utf8)!)
    exit(1)
}
let fm = FileManager.default
let outDir = URL(fileURLWithPath: args[1], isDirectory: true)
try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

writePNG(renderIcon(1024), outDir.appendingPathComponent("AppIcon-1024.png"))

// AppIcon.iconset: every entry rendered natively at its pixel size (32 px for 16@2x, ...).
let iconset = outDir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? fm.removeItem(at: iconset)
try? fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for pt in [16, 32, 128, 256, 512] {
    writePNG(renderIcon(pt), iconset.appendingPathComponent("icon_\(pt)x\(pt).png"))
    writePNG(renderIcon(pt * 2), iconset.appendingPathComponent("icon_\(pt)x\(pt)@2x.png"))
}

writePNG(makePreview(), outDir.appendingPathComponent("preview.png"))

if ProcessInfo.processInfo.environment["ICON_DEBUG"] != nil {
    for px in [16, 32, 64, 128] { writePNG(makeDebug(px), outDir.appendingPathComponent("debug-\(px).png")) }
}

// AppIcon.icns, when iconutil is available (it ships with macOS).
let icns = outDir.appendingPathComponent("AppIcon.icns")
let iconutil = "/usr/bin/iconutil"
if fm.isExecutableFile(atPath: iconutil) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: iconutil)
    p.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
    do {
        try p.run(); p.waitUntilExit()
        if p.terminationStatus == 0 { print("Wrote \(icns.path)") }
        else { FileHandle.standardError.write("iconutil failed (\(p.terminationStatus)); iconset is still in place\n".data(using: .utf8)!) }
    } catch {
        FileHandle.standardError.write("Could not run iconutil: \(error)\n".data(using: .utf8)!)
    }
}
print("Wrote \(outDir.appendingPathComponent("AppIcon-1024.png").path)")
print("Wrote \(iconset.path)")
print("Wrote \(outDir.appendingPathComponent("preview.png").path)")
