import AppKit

/// Procedural pixel-art landscape with a smiling retro computer, ported from
/// `pixel_computer_landscape_four_scenes.html`. Renders one `width × height`
/// pixel frame per `render(time:)` call; the caller scales it up with nearest-
/// neighbour interpolation so the pixels stay crisp.
final class PixelScene {
    enum Kind { case meadow, dusk, night, coast }

    struct Palette {
        var sky: [(Int, Int, Int)]
        var cl: [String]
        var nC: Int
        var sun = false, stars = false, moon = false, water = false
        var dk = "", md = "", lt = "", fl = "", fl2 = "", gr = ""
        var rk = "", rkd = "", bl = "", blL = "", mote = "", sh = ""
        var bd = "", bdL = "", bdH = "", bdD = "", bz = "", s1 = "", s2 = "", fc = ""
        /// Body colours of the small second computer standing behind the main one.
        var b2 = "", b2L = "", b2H = "", b2D = ""
        /// Underground (rows below the 16:10 scene): two dithered soil tones, root, pebble.
        var soil = ("#4a3221", "#3f2a1b"), root = "#8f6a45", rootD = "#66482c", pebble = "#6e655c"
    }

    static func palette(for kind: Kind) -> Palette {
        switch kind {
        case .meadow:
            return Palette(sky: [(46, 152, 214), (176, 222, 240)], cl: ["#ffffff", "#bcdcef"], nC: 4,
                dk: "#1f5c24", md: "#3d8a2a", lt: "#68b03a", fl: "#ffe95c", fl2: "#f5d431", gr: "#2e6d20",
                rk: "#6c8290", rkd: "#4d616d", bl: "#2e6d20", blL: "#8ec93f", mote: "#fff6c0", sh: "#255a19",
                bd: "#d9692b", bdL: "#e8813b", bdH: "#f5a45e", bdD: "#b84d1c", bz: "#a34a1f", s1: "#5b2a15", s2: "#4a2011", fc: "#f2913f",
                b2: "#3f8fa8", b2L: "#57a9c0", b2H: "#8fd0e0", b2D: "#2c6a80")
        case .dusk:
            return Palette(sky: [(92, 52, 120), (250, 178, 110)], cl: ["#ffd9b0", "#cf8f8a"], nC: 4, sun: true,
                dk: "#173d33", md: "#2c6446", lt: "#4f8a4a", fl: "#ffcf6b", fl2: "#f0a848", gr: "#1f4a33",
                rk: "#6b5a70", rkd: "#493a52", bl: "#1f4a33", blL: "#7fa54a", mote: "#ffdca0", sh: "#183b2a",
                bd: "#c85c2a", bdL: "#df7738", bdH: "#f0a05a", bdD: "#8f3a17", bz: "#8f3a17", s1: "#4d2415", s2: "#3a1a10", fc: "#ffb15c",
                b2: "#3a7f97", b2L: "#4f98ad", b2H: "#7fc0d0", b2D: "#25596b",
                soil: ("#3e2a1c", "#342216"), root: "#7c5a3c", rootD: "#563d27", pebble: "#5d5350")
        case .night:
            return Palette(sky: [(8, 14, 40), (38, 60, 100)], cl: ["#3a4a72", "#2a3557"], nC: 2, stars: true, moon: true,
                dk: "#0f2a1a", md: "#193d24", lt: "#25532f", fl: "#9fd7ff", fl2: "#6fa8d6", gr: "#12331d",
                rk: "#3a4656", rkd: "#252e3c", bl: "#12331d", blL: "#2c6b34", mote: "#d6ff8a", sh: "#0b2213",
                bd: "#8a4020", bdL: "#a05128", bdH: "#c06a38", bdD: "#5c2712", bz: "#5c2712", s1: "#123a3c", s2: "#0d2a2c", fc: "#7fe6d8",
                b2: "#27596b", b2L: "#336d82", b2H: "#4b8ea6", b2D: "#193c48",
                soil: ("#241a12", "#1d140e"), root: "#5a412c", rootD: "#3e2c1b", pebble: "#3d3a3f")
        case .coast:
            return Palette(sky: [(74, 168, 214), (206, 236, 242)], cl: ["#ffffff", "#c6e2ef"], nC: 3, water: true,
                dk: "#3f6b3a", md: "#5d8a3c", lt: "#8bb551", fl: "#f2e6a8", fl2: "#e8d488", gr: "#e6cf9c",
                rk: "#8a8f92", rkd: "#646b6f", bl: "#5d8a3c", blL: "#a8c96a", mote: "#ffffff", sh: "#c9a76a",
                bd: "#d9692b", bdL: "#e8813b", bdH: "#f5a45e", bdD: "#b84d1c", bz: "#a34a1f", s1: "#5b2a15", s2: "#4a2011", fc: "#f2913f",
                b2: "#3f8fa8", b2L: "#57a9c0", b2H: "#8fd0e0", b2D: "#2c6a80",
                soil: ("#8a7250", "#7a6444"), root: "#a8895e", rootD: "#8c7047", pebble: "#9c9a92")
        }
    }

    /// Scene for the wall clock: day → meadow, evening → golden hour, otherwise night.
    static func kind(forHour hour: Int) -> Kind {
        switch hour {
        case 7..<17: return .meadow
        case 17..<20: return .dusk
        default: return .night
        }
    }

    // MARK: - State

    /// `H` is the nominal 16:10 layout height (horizon, computer, sky); `totalH` is the
    /// bitmap height — any rows beyond `H` continue the ground with more grass and bushes.
    let W: Int, H: Int, totalH: Int
    let P: Palette
    /// Colour of the underground, so the caller can extend the bitmap below its bottom edge.
    var groundColor: NSColor { color(P.soil.1).nsColor }

    private let ctx: CGContext
    private let sky: CGContext
    private var t: Double = 0
    /// Point (in scene pixels, may lie outside the bitmap) the computers look at;
    /// `nil` looks straight ahead.
    var lookAt: (x: Double, y: Double)?
    /// Scene time a task was last ticked off, or nil. Held by SurfaceView rather than
    /// here (like `lookAt`) so a rebuild mid-cheer picks it up unchanged.
    var celebratedAt: Double?
    /// How long the computers cheer for.
    static let cheerDuration = 0.6

    private struct Cloud { var x, y: Double; var b: [(Double, Double, Double)]; var s: Double }
    private struct Bush { var x, y, r: Double; var dark: Bool; var ph: Double; var f: (Double, Double)? }
    private struct Blade { var x, y, h, ph: Double; var c: Bool }
    private struct Mote { var x, y, ph, sp: Double }
    private struct Twinkle { var x, y, ph: Double }
    private struct Gull { var x, y, sp, ph: Double }

    private var clouds: [Cloud] = [], bushes: [Bush] = [], blades: [Blade] = []
    private var motes: [Mote] = [], twk: [Twinkle] = [], gulls: [Gull] = []
    private let rocks: [[(Double, Double)]] = [
        [(0.01, 0.66), (0.06, 0.58), (0.12, 0.66), (0.11, 0.78), (0.02, 0.78)],
        [(0.86, 0.80), (0.93, 0.74), (1.00, 0.81), (0.99, 0.92), (0.87, 0.91)],
        [(0.14, 0.84), (0.20, 0.79), (0.25, 0.87), (0.19, 0.93), (0.12, 0.91)]
    ]

    init(width: Int, height: Int, totalHeight: Int? = nil, kind: Kind) {
        W = width; H = height; totalH = max(height, totalHeight ?? height); P = PixelScene.palette(for: kind)
        ctx = PixelScene.makeContext(W, totalH)
        sky = PixelScene.makeContext(W, totalH)
        build()
    }

    /// Bitmap context whose coordinates run top-down like a canvas.
    private static func makeContext(_ w: Int, _ h: Int) -> CGContext {
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)
        c.setShouldAntialias(false)
        return c
    }

    // MARK: - Helpers (canvas primitives)

    /// mulberry32, same sequence as the HTML's `rnd(seed)`.
    private struct Rnd {
        var a: UInt32
        init(_ seed: Int) { a = UInt32(truncatingIfNeeded: seed) }
        mutating func next() -> Double {
            a = a &+ 0x6D2B79F5
            var r = (a ^ (a >> 15)) &* (1 | a)
            r = (r &+ ((r ^ (r >> 7)) &* (61 | r))) ^ r
            return Double((r ^ (r >> 14))) / 4294967296
        }
    }

    private struct Col { let cg: CGColor; let nsColor: NSColor }
    private var colors: [String: Col] = [:]
    private func color(_ hex: String) -> Col {
        if let c = colors[hex] { return c }
        var s = hex; s.removeFirst()
        let v = UInt32(s, radix: 16) ?? 0
        let ns = NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                         blue: CGFloat(v & 255) / 255, alpha: 1)
        let c = Col(cg: ns.cgColor, nsColor: ns)
        colors[hex] = c
        return c
    }

    private func fill(_ g: CGContext, _ hex: String) { g.setFillColor(color(hex).cg) }
    private func rect(_ g: CGContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        g.fill(CGRect(x: x, y: y, width: w, height: h))
    }
    private func R(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ c: String) {
        fill(ctx, c)
        rect(ctx, x.rounded(), y.rounded(), max(1, w.rounded()), max(1, h.rounded()))
    }
    private func circ(_ g: CGContext, _ cx: Double, _ cy: Double, _ r: Int, _ c: String) {
        fill(g, c)
        if r < 0 { return }
        for d in -r...r {
            let w = Double(Int(Double(r * r - d * d).squareRoot()))
            rect(g, (cx - w).rounded(), (cy + Double(d)).rounded(), w * 2 + 1, 1)
        }
    }
    private func circ(_ cx: Double, _ cy: Double, _ r: Int, _ c: String) { circ(ctx, cx, cy, r, c) }
    private func rr(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ rad: Double, _ c: String) {
        fill(ctx, c)
        var i = 0.0
        while i < h {
            var ins = 0.0
            if i < rad { let k = rad - i - 0.5; ins = rad - Double(Int(max(0, rad * rad - k * k).squareRoot())) }
            let b = h - 1 - i
            if b < rad { let k = rad - b - 0.5; ins = max(ins, rad - Double(Int(max(0, rad * rad - k * k).squareRoot()))) }
            rect(ctx, (x + ins).rounded(), (y + i).rounded(), max(1, (w - 2 * ins).rounded()), 1)
            i += 1
        }
    }
    private func poly(_ p: [(Double, Double)], _ c: String) {
        let ys = p.map { $0.1 }
        let a = ys.min()!, b = ys.max()!
        fill(ctx, c)
        var y = Double(Int(a.rounded(.down)))
        while y <= b {
            var xs: [Double] = []
            for i in 0..<p.count {
                let u = p[i], v = p[(i + 1) % p.count]
                if (u.1 <= y && v.1 > y) || (v.1 <= y && u.1 > y) {
                    xs.append(u.0 + (y - u.1) / (v.1 - u.1) * (v.0 - u.0))
                }
            }
            xs.sort()
            var i = 0
            while i + 1 < xs.count {
                rect(ctx, xs[i].rounded(), y, max(1, (xs[i + 1] - xs[i]).rounded()), 1)
                i += 2
            }
            y += 1
        }
    }

    // MARK: - Build (static parts)

    private func build() {
        let Wd = Double(W), Hd = Double(H)
        // Dithered sky gradient, quantised to 17-step bands like the original.
        let data = sky.data!.assumingMemoryBound(to: UInt8.self)
        let bay = [[0, 2], [3, 1]], hz = Hd * 0.78
        for y in 0..<totalH {
            let f = min(1, Double(y) / hz)
            for x in 0..<W {
                let dd = (Double(bay[y & 1][x & 1]) / 4 - 0.375) * 26
                let o = (y * W + x) * 4
                let c0 = [P.sky[0].0, P.sky[0].1, P.sky[0].2], c1 = [P.sky[1].0, P.sky[1].1, P.sky[1].2]
                for i in 0..<3 {
                    let v = Double(c0[i]) + Double(c1[i] - c0[i]) * f + dd
                    data[o + i] = UInt8(max(0, min(255, (v / 17).rounded() * 17)))
                }
                data[o + 3] = 255
            }
        }
        underground()
        var q = Rnd(5)
        if P.stars {
            for _ in 0..<70 {
                let sx = Double(Int(q.next() * Wd)), sy = Double(Int(q.next() * Hd * 0.6))
                sky.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.4 + q.next() * 0.6))
                rect(sky, sx, sy, 1, 1)
            }
        }
        if P.moon {
            let mx = Wd * 0.78, my = Hd * 0.2
            circ(sky, mx, my, 9, "#f2ecd0")
            fill(sky, "#dcd4b4"); rect(sky, mx - 3, my - 3, 3, 3); rect(sky, mx + 2, my + 3, 2, 2)
        }
        if P.sun { circ(sky, Wd * 0.30, Hd * 0.52, 13, "#ffe0a8") }

        clouds = []
        var r = Rnd(P.water ? 13 : 7)
        for _ in 0..<P.nC {
            let n = 5 + Int(r.next() * 4)
            var b: [(Double, Double, Double)] = []
            let sp = Wd * (0.14 + r.next() * 0.13)
            for j in 0..<n {
                b.append(((Double(j) / Double(n - 1) - 0.5) * sp, (r.next() - 0.5) * Hd * 0.05, Hd * (0.05 + r.next() * 0.06)))
            }
            clouds.append(Cloud(x: r.next() * Wd * 1.4 - Wd * 0.2, y: Hd * (0.08 + r.next() * 0.26), b: b, s: 0.05 + r.next() * 0.08))
        }
        bushes = []
        func mass(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ n: Int, _ seed: Int) {
            var p = Rnd(seed)
            for _ in 0..<n {
                let px = x0 + p.next() * (x1 - x0), py = y0 + p.next() * (y1 - y0), rad = Hd * (0.035 + p.next() * 0.06)
                let dark = p.next() < 0.45, ph = p.next() * 6.28
                let f: (Double, Double)? = p.next() < 0.5 ? (px + (p.next() - 0.5) * rad, py - rad * 0.55) : nil
                bushes.append(Bush(x: px, y: py, r: rad, dark: dark, ph: ph, f: f))
            }
        }
        if !P.water {
            mass(-Wd * 0.04, Wd * 0.30, Hd * 0.55, Hd * 0.76, 30, 3)
            mass(Wd * 0.70, Wd * 1.04, Hd * 0.52, Hd * 0.74, 28, 9)
        }
        mass(-Wd * 0.04, Wd * 1.04, Hd * 0.78, Hd * 1.04, P.water ? 18 : 46, 15)
        blades = []
        var r3 = Rnd(33)
        let nb = Int((Wd * (P.water ? 0.35 : 0.95)).rounded())
        for _ in 0..<nb {
            blades.append(Blade(x: r3.next() * Wd, y: Hd * (0.80 + r3.next() * 0.22), h: Hd * (0.03 + r3.next() * 0.07), ph: r3.next() * 6.28, c: r3.next() < 0.35))
        }
        motes = []
        var r4 = Rnd(41)
        for _ in 0..<14 { motes.append(Mote(x: r4.next() * Wd, y: r4.next() * Hd, ph: r4.next() * 6.28, sp: 0.06 + r4.next() * 0.12)) }
        twk = []
        var r5 = Rnd(51)
        for _ in 0..<10 { twk.append(Twinkle(x: Double(Int(r5.next() * Wd)), y: Double(Int(r5.next() * Hd * 0.55)), ph: r5.next() * 6.28)) }
        gulls = []
        var r6 = Rnd(61)
        for _ in 0..<3 { gulls.append(Gull(x: r6.next() * Wd, y: Hd * (0.12 + r6.next() * 0.2), sp: 0.14 + r6.next() * 0.1, ph: r6.next() * 6.28)) }
    }

    /// Soil with roots and pebbles for the rows below the scene, baked into `sky`
    /// (the static background) so the animation loop doesn't pay for it.
    private func underground() {
        guard totalH > H else { return }
        let Wd = Double(W), top = H
        for y in top..<totalH {
            for x in 0..<W {
                fill(sky, ((x + y) & 1 == 0) ? P.soil.0 : P.soil.1)
                rect(sky, Double(x), Double(y), 1, 1)
            }
        }
        // Dirt edge just under the grass.
        fill(sky, P.rootD); rect(sky, 0, Double(top), Wd, 1)
        var r = Rnd(91)
        for _ in 0..<(W / 3) where r.next() < 0.6 {
            fill(sky, P.soil.1); rect(sky, Double(Int(r.next() * Wd)), Double(top + 1), 2, 1)
        }
        // Pebbles.
        var rp = Rnd(97)
        for _ in 0..<((totalH - top) * W / 700) {
            let x = Double(Int(rp.next() * Wd)), y = Double(top + 3 + Int(rp.next() * Double(totalH - top - 3)))
            let big = rp.next() < 0.3
            fill(sky, P.pebble); rect(sky, x, y, big ? 3 : 2, big ? 2 : 1)
            fill(sky, P.soil.1); rect(sky, x, y + (big ? 2 : 1), big ? 3 : 2, 1)
        }
        // Roots: random walks down from the grass line that thin out and branch.
        var rr = Rnd(101)
        func grow(x0: Int, y0: Int, length: Int, width: Int, drift: Double) {
            var x = x0, dx = drift
            for i in 0..<length {
                let y = y0 + i
                if y >= totalH { break }
                if rr.next() < 0.35 { dx += (rr.next() - 0.5) * 1.2 }
                dx = max(-1.2, min(1.2, dx))
                x += Int(dx.rounded())
                let w = i > length * 2 / 3 ? 1 : width
                fill(sky, P.root); rect(sky, Double(x), Double(y), Double(w), 1)
                fill(sky, P.rootD); rect(sky, Double(x + w), Double(y), 1, 1)
                if i > 4, width > 1, rr.next() < 0.06 {
                    grow(x0: x, y0: y, length: length / 2, width: 1, drift: dx > 0 ? -1 : 1)
                }
            }
        }
        let nRoots = max(3, W / 28)
        for i in 0..<nRoots {
            let x = Int((Double(i) + 0.3 + rr.next() * 0.4) * Wd / Double(nRoots))
            let length = 16 + Int(rr.next() * 34), width = rr.next() < 0.5 ? 2 : 1
            grow(x0: x, y0: top + 1, length: length, width: width, drift: (rr.next() - 0.5) * 0.8)
        }
    }

    // MARK: - Frame

    private func cloud(_ c: Cloud) {
        for b in c.b { circ(c.x + b.0, c.y + b.1 + b.2 * 0.35, Int((b.2 * 0.85).rounded()), P.cl[1]) }
        for b in c.b { circ(c.x + b.0, c.y + b.1, Int(b.2.rounded()), P.cl[0]) }
        for b in c.b { circ(c.x + b.0, c.y + b.1 - b.2 * 0.25, Int((b.2 * 0.5).rounded()), P.cl[0]) }
    }

    private func bush(_ b: Bush) {
        let Hd = Double(H)
        let sw = sin(t * 0.9 + b.ph) * (Hd / 170) * 1.1, u = max(1, (Hd / 170 * 2).rounded())
        circ(b.x + sw, b.y, Int(b.r.rounded()), b.dark ? P.dk : P.md)
        circ(b.x + sw - b.r * 0.25, b.y - b.r * 0.3, Int((b.r * 0.55).rounded()), b.dark ? P.md : P.lt)
        if let f = b.f {
            R(f.0 + sw, f.1, u, u, P.fl2)
            R(f.0 + sw + u * 1.6, f.1 + u * 1.6, u, u, P.fl)
        }
    }

    /// The retro computer. `scale` is relative to the main one; `cx` is its centre,
    /// 0…1 over `cheerDuration` after a check-off, 0 otherwise. `delay` staggers the
    /// small computer so the two don't fire in lockstep. One envelope drives the hop,
    /// the squint and the screen flash together, so they cannot drift apart.
    private func cheer(delay: Double = 0) -> Double {
        guard let at = celebratedAt else { return 0 }
        let e = (t - at - delay) / PixelScene.cheerDuration
        return e > 0 && e < 1 ? e : 0
    }

    /// `groundY` where its base sits, `phase` offsets the bob and blink so two
    /// computers don't move in lockstep.
    private func computer(cx: Double, groundY: Double, scale: Double, phase: Double,
                          body: (String, String, String, String), face: (String, String, String, String)) {
        let Hd = Double(H)
        let S = Hd / 170 * 1.16 * scale, bw = (56 * S).rounded(), bh = (62 * S).rounded()
        let bx = (cx - bw / 2).rounded()
        let joy = cheer(delay: phase == 0 ? 0 : 0.08)
        // A hop on top of the idle bob: sin() is 0 at both ends, so it leaves from and
        // lands on exactly the bob's position instead of snapping.
        let hop = (sin(.pi * joy) * S * 4).rounded()
        // Three-step bob (-1 / 0 / +1 px), shifted up one step so it never dips below the ground line.
        let by = groundY - bh + (sin(t * 1.1 + phase) * S * 1.2).rounded() - S.rounded() - hop, u = max(1, S.rounded())
        let (bd, bdL, bdH, bdD) = body, (bz, s1, s2, fc) = face
        // The shadow belongs to the ground, not to him, so the hop is added back out of it
        // and it tightens a little while he is in the air.
        if P.water { R(bx - (4 * S).rounded(), by + hop + bh - (3 * S).rounded(), bw + (8 * S).rounded(), (4 * S).rounded(), P.sh) }
        else { circ(cx, by + hop + bh - (2 * S).rounded(), Int((bw * 0.46 * (1 - 0.25 * sin(.pi * joy))).rounded()), P.sh) }
        rr(bx, by, bw, bh, (7 * S).rounded(), bd)
        rr(bx, by, bw, (bh * 0.62).rounded(), (7 * S).rounded(), bdL)
        R(bx + (2 * S).rounded(), by + (4 * S).rounded(), (2 * S).rounded(), bh - (12 * S).rounded(), bdH)
        R(bx + bw - (4 * S).rounded(), by + (6 * S).rounded(), (3 * S).rounded(), bh - (16 * S).rounded(), bdD)
        for i in 0..<3 { R(bx + bw - (9 * S).rounded(), by + ((15 + Double(i) * 4) * S).rounded(), (4 * S).rounded(), (2 * S).rounded(), bdD) }
        let sx = bx + (6 * S).rounded(), sy = by + (6 * S).rounded(), sw2 = bw - (12 * S).rounded(), sh = (34 * S).rounded()
        rr(sx, sy, sw2, sh, (5 * S).rounded(), bz)
        rr(sx + u, sy + u, sw2 - 2 * u, sh - 2 * u, (4 * S).rounded(), s1)
        rr(sx + 2 * u, sy + 2 * u, sw2 - 4 * u, sh - (5 * S).rounded(), (4 * S).rounded(), s2)
        let bl = (t + phase).truncatingRemainder(dividingBy: 4.3) < 0.16
        let eh = bl ? (2 * S).rounded() : (6 * S).rounded(), ey = sy + (11 * S).rounded() + (bl ? (2 * S).rounded() : 0)
        let ew = (7 * S).rounded(), ex1 = sx + (9 * S).rounded(), ex2 = sx + sw2 - (16 * S).rounded()
        if joy > 0 {
            // Happy squint: a shallow ∧ per eye. Only ~6 px of eye to work with, so it is
            // built from three blocks — outer sides one step down from a raised middle —
            // rather than a drawn curve, which would just alias into a bar.
            let step = max(1, (S * 1.5).rounded()), side = max(1, (ew / 3).rounded())
            for ex in [ex1, ex2] {
                R(ex, ey + (3 * S).rounded() + step, side, step, fc)
                R(ex + side, ey + (3 * S).rounded(), ew - 2 * side, step, fc)
                R(ex + ew - side, ey + (3 * S).rounded() + step, side, step, fc)
            }
        } else {
            R(ex1, ey, ew, eh, fc)
            R(ex2, ey, ew, eh, fc)
        }
        if !bl, joy == 0 {
            // Pupils: a dark 3×3 block that slides up to 2 px sideways / 1 px vertically
            // toward `lookAt`; the sigmoid keeps them centred while the mouse is close.
            let pw = (3 * S).rounded(), mx = ew - pw, my = eh - pw
            var px = (mx / 2).rounded(), py = (my / 2).rounded()
            if let l = lookAt {
                let dx = l.x - (ex1 + ex2 + ew) / 2, dy = l.y - (ey + eh / 2)
                let d = (dx * dx + dy * dy).squareRoot()
                if d > 0.5 {
                    let k = tanh(d / (28 * S)) // 0…1, saturates a little way from the face
                    px = ((mx / 2) + dx / d * k * (mx / 2)).rounded()
                    py = ((my / 2) + dy / d * k * (my / 2)).rounded()
                }
            }
            R(ex1 + px, ey + py, pw, pw, s2)
            R(ex2 + px, ey + py, pw, pw, s2)
        }
        R(sx + (3 * S).rounded(), sy + (2 * S).rounded(), (3 * S).rounded(), (9 * S).rounded(), s1)
        R(bx + bw / 2 - (5 * S).rounded(), by + (48 * S).rounded(), (10 * S).rounded(), u, bdD)
        R(bx + bw / 2 - (5 * S).rounded(), by + (51 * S).rounded(), (10 * S).rounded(), u, bdD)
    }

    /// Main computer plus a smaller, differently coloured one peeking out behind it.
    private func mac() {
        let Wd = Double(W), Hd = Double(H)
        let S = Hd / 170 * 1.16, ground = (Hd * 0.30).rounded() + (62 * S).rounded()
        computer(cx: (Wd / 2 + 36 * S).rounded(), groundY: ground - (6 * S).rounded(), scale: 0.6, phase: 2.1,
                 body: (P.b2, P.b2L, P.b2H, P.b2D), face: (P.b2D, "#12333c", "#0c262d", "#bff2ff"))
        computer(cx: Wd / 2, groundY: ground, scale: 1, phase: 0, body: (P.bd, P.bdL, P.bdH, P.bdD), face: (P.bz, P.s1, P.s2, P.fc))
        // Foreground bushes at the small one's feet so its base doesn't end in a hard line.
        let fx = Wd / 2 + 36 * S, fy = ground - (12 * S).rounded()
        // Back row (higher, darker) hides his lower body; front row reaches down to the grass line.
        bush(Bush(x: fx - 20 * S, y: fy + 2 * S, r: Hd * 0.06, dark: true, ph: 0.9, f: nil))
        bush(Bush(x: fx + 14 * S, y: fy + 2 * S, r: Hd * 0.055, dark: true, ph: 1.3, f: nil))
        bush(Bush(x: fx - 4 * S, y: fy + 4 * S, r: Hd * 0.065, dark: false, ph: 2.9, f: (fx - 8 * S, fy)))
        bush(Bush(x: fx + 26 * S, y: fy + 6 * S, r: Hd * 0.045, dark: false, ph: 0.4, f: nil))
        bush(Bush(x: fx - 14 * S, y: ground - 2 * S, r: Hd * 0.06, dark: false, ph: 2.2, f: nil))
        bush(Bush(x: fx + 6 * S, y: ground - 3 * S, r: Hd * 0.065, dark: true, ph: 3.6, f: (fx + 10 * S, ground - 8 * S)))
        bush(Bush(x: fx + 24 * S, y: ground - 1 * S, r: Hd * 0.055, dark: false, ph: 1.7, f: nil))
    }

    /// Frames per second SurfaceView drives this at. The drifting elements below move a
    /// fixed step per *frame* (as in the original HTML), so turning that into a position
    /// at `t` seconds needs the rate.
    static let fps = 18.0

    /// `start` drifted by `step` per frame for `t` seconds, wrapped into `low..<high`.
    /// Deriving the position instead of accumulating it is what lets the scene be rebuilt
    /// mid-animation — every panel resize does that — without the frame jumping.
    private func drift(_ start: Double, step: Double, from low: Double, to high: Double) -> Double {
        let span = high - low
        var p = (start - low + step * t * PixelScene.fps).truncatingRemainder(dividingBy: span)
        if p < 0 { p += span }
        return p + low
    }

    /// Advances the animation to `time` (seconds) and returns the frame.
    func render(time: Double) -> CGImage {
        t = time
        let Wd = Double(W), Hd = Double(H)
        memcpy(ctx.data, sky.data, W * totalH * 4)
        if P.stars { for s in twk where sin(t * 2 + s.ph) > 0.4 { R(s.x, s.y, 1, 1, "#ffffff") } }
        for c in clouds {
            var moved = c
            moved.x = drift(c.x, step: -c.s, from: -Wd * 0.3, to: Wd * 1.3)
            cloud(moved)
        }
        if P.water {
            let y0 = Int((Hd * 0.56).rounded()), y1 = Int((Hd * 0.76).rounded())
            for y in y0..<y1 {
                let f = Double(y - y0) / Double(y1 - y0)
                let cr = (29 + (87 - 29) * f).rounded(), cg = (110 + (184 - 110) * f).rounded(), cb = (168 + (214 - 168) * f).rounded()
                ctx.setFillColor(CGColor(srgbRed: cr / 255, green: cg / 255, blue: cb / 255, alpha: 1))
                rect(ctx, 0, Double(y), Wd, 1)
            }
            for i in 0..<9 {
                let wy = Double(y0 + 3 + i * Int((Double(y1 - y0) / 9).rounded())), ph = Double(i) * 1.7
                let off = (t * Double(6 + i)).truncatingRemainder(dividingBy: Wd + 40)
                for k in 0..<4 {
                    let x = (off + Double(k) * 70 + sin(t * 1.4 + ph) * 4).truncatingRemainder(dividingBy: Wd + 30) - 15
                    R(x, wy, (Wd * 0.045).rounded(), 1, "#d8f0f8")
                }
            }
            R(0, Double(y1), Wd, Hd - Double(y1), P.gr)
            var r7 = Rnd(77)
            for _ in 0..<Int((Wd * 1.2).rounded()) {
                let x = r7.next() * Wd, y = Double(y1) + r7.next() * (Hd - Double(y1))
                R(x, y, 1, 1, r7.next() < 0.5 ? "#cfae74" : "#f2e0b4")
            }
            R(0, Double(y1), Wd, 2, "#c49a63")
        } else {
            R(0, (Hd * 0.74).rounded(), Wd, Hd - (Hd * 0.74).rounded(), P.gr) // to the scene's bottom edge only
            for b in bushes where b.y <= Hd * 0.78 { bush(b) }
            for i in 0..<2 {
                let p = rocks[i].map { ($0.0 * Wd, $0.1 * Hd) }
                poly(p, P.rk)
                poly(p.enumerated().map { ($0.element.0 + ($0.offset < 2 ? 0 : 2), $0.element.1 + 3) }, P.rkd)
            }
        }
        mac()
        for b in bushes where b.y > Hd * 0.78 { bush(b) }
        if !P.water { poly(rocks[2].map { ($0.0 * Wd, $0.1 * Hd) }, P.rk) }
        let u = max(1, (Hd / 170 * 2).rounded())
        for (i, b) in blades.enumerated() {
            let dx = sin(t * 1.6 + b.ph) * (Hd / 170) * 1.7
            fill(ctx, b.c ? P.blL : P.bl)
            var k = 0.0
            while k < b.h { rect(ctx, (b.x + dx * (k / b.h)).rounded(), (b.y - k).rounded(), 1, 1); k += 1 }
            if b.c && (i & 3) == 0 { R(b.x + dx, b.y - b.h, u, u, P.fl) }
        }
        if P.water {
            for q in gulls {
                let x = drift(q.x, step: q.sp, from: -8, to: Wd + 8)
                let yy = q.y + sin(t * 0.8 + q.ph) * 3, f2: Double = sin(t * 5 + q.ph) > 0 ? 1 : 0
                R(x, yy, 1, 1, "#3d4a52"); R(x - 2, yy - f2, 1, 1, "#3d4a52"); R(x + 2, yy - f2, 1, 1, "#3d4a52")
            }
        } else {
            for var m in motes {
                m.y = drift(m.y, step: -m.sp, from: Hd * 0.2, to: Hd)
                if P.stars {
                    if sin(t * 3 + m.ph) > 0 { R(m.x + sin(t + m.ph) * 4, m.y, 1, 1, P.mote) }
                } else {
                    R(m.x + sin(t + m.ph) * 3, m.y, 1, 1, P.mote)
                }
            }
        }
        return ctx.makeImage()!
    }
}
