import AppKit

/// Procedural pixel-art landscape with a smiling retro computer, ported from
/// `pixel_computer_landscape_four_scenes.html`. Renders one `width × height`
/// pixel frame per `render(time:)` call; the caller scales it up with nearest-
/// neighbour interpolation so the pixels stay crisp.
final class PixelScene {
    /// Raw values are what the scene preference stores, so don't rename them.
    enum Kind: String, CaseIterable {
        case meadow, dusk, night, coast, rain, moon, desert, autumn, mars

        /// The scenes the switcher steps through. The meadow, golden hour and night are
        /// the clock's own — one landscape at three times of day, and "follow the clock"
        /// is the way to see it. Pinning one would put an evening sky over the panel at
        /// ten in the morning; pinning the meadow in the evening read as a duplicate of
        /// the golden hour it followed.
        static var pickable: [Kind] { allCases.filter { !clocks.contains($0) } }

        /// What the clock chooses between (`kind(forHour:)`).
        static let clocks: Set<Kind> = [.meadow, .dusk, .night]

        /// German name, for the button's tooltip.
        var label: String {
            switch self {
            case .meadow: return "Wiese"
            case .dusk: return "Goldene Stunde"
            case .night: return "Nacht"
            case .coast: return "Küste"
            case .rain: return "Regentag"
            case .moon: return "Mondbasis"
            case .desert: return "Wüste"
            case .autumn: return "Herbstwald"
            case .mars: return "Roter Planet"
            }
        }
    }

    /// How the ground is made: `land` grows bushes and grass over a flat band,
    /// `desert` bakes dunes, `regolith` bakes the moon's crater field, `mars` bakes
    /// mesas over a dust plain. Only `land` has anything growing on it.
    enum Mode { case land, desert, regolith, mars }

    /// What drifts through the air in front of everything else.
    enum Weather { case motes, rain, leaves, dust, sparks, devil }

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
        /// Surface speckle tones of bare ground, carried on into the soil below it so the
        /// texture doesn't stop dead at the scene's last row (see `underground`). Unused
        /// by the scenes that grow grass and bushes over the join.
        var grain = ("", "")
        /// The two tones the scene's ground dithers with where it meets the soil below.
        /// Empty falls back to `(gr, dk)`, which is right wherever `dk` is the ground's
        /// own dark tone rather than a bush colour.
        var edge = ("", "")
        var mode: Mode = .land
        var weather: Weather = .motes
        /// Roots in the soil below the scene — only under ground that grows something.
        var roots = true
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
                soil: ("#b09877", "#a08768"), root: "#96794f", rootD: "#7d6340", pebble: "#8e8c84",
                grain: ("#cfae74", "#f2e0b4"), edge: ("#e6cf9c", "#d6bb85"), roots: false)
        case .rain:
            // Same meadow, an hour into a downpour: the greens drop a step, the sky
            // and clouds go flat grey, and the body loses its highlight.
            return Palette(sky: [(64, 72, 86), (150, 160, 172)], cl: ["#8a93a3", "#6b7382"], nC: 5,
                dk: "#153a1e", md: "#2a5c2b", lt: "#3f7a36", fl: "#e8dd7a", fl2: "#cfc25e", gr: "#25541c",
                rk: "#5b6b76", rkd: "#3e4b55", bl: "#25541c", blL: "#6a9c37", mote: "#cfe4f0", sh: "#1c4415",
                bd: "#b9581f", bdL: "#cc6b2c", bdH: "#dd8a4a", bdD: "#8d3f14", bz: "#a34a1f", s1: "#5b2a15", s2: "#4a2011", fc: "#f2913f",
                b2: "#35788c", b2L: "#4a92a6", b2H: "#79b8c8", b2D: "#245a6b",
                soil: ("#33251a", "#2b1e15"), root: "#6b4c33", rootD: "#4a3322", pebble: "#514b45",
                weather: .rain)
        case .moon:
            // No air, so nothing sways: the ground is baked craters and the only
            // movement is drifting dust and the odd shooting star.
            return Palette(sky: [(4, 5, 14), (16, 20, 40)], cl: ["#3a4a72", "#2a3557"], nC: 0, stars: true,
                dk: "#45434b", md: "#5d5b63", lt: "#7a7883", fl: "#cfe6ff", fl2: "#9fb4cc", gr: "#5d5b63",
                rk: "#7a7883", rkd: "#45434b", bl: "#5d5b63", blL: "#7a7883", mote: "#cfe6ff", sh: "#403e46",
                bd: "#8a4020", bdL: "#a05128", bdH: "#c06a38", bdD: "#5c2712", bz: "#5c2712", s1: "#123a3c", s2: "#0d2a2c", fc: "#7fe6d8",
                b2: "#27596b", b2L: "#336d82", b2H: "#4b8ea6", b2D: "#193c48",
                soil: ("#46444c", "#3c3a42"), root: "#5a5560", rootD: "#443f4a", pebble: "#6e6c75",
                grain: ("#55535b", "#6e6c75"), edge: ("#5d5b63", "#55535b"),
                mode: .regolith, weather: .sparks, roots: false)
        case .desert:
            return Palette(sky: [(228, 150, 84), (250, 224, 176)], cl: ["#ffe9c8", "#eec79a"], nC: 2, sun: true,
                dk: "#2f6b3c", md: "#3f8a4a", lt: "#57a75c", fl: "#ff8fb0", fl2: "#ffd0dd", gr: "#e0bd80",
                rk: "#b08a5c", rkd: "#8c6a42", bl: "#c9a86e", blL: "#e0c68c", mote: "#fff0c8", sh: "#b58a55",
                bd: "#d9692b", bdL: "#e8813b", bdH: "#f5a45e", bdD: "#b84d1c", bz: "#a34a1f", s1: "#5b2a15", s2: "#4a2011", fc: "#f2913f",
                b2: "#3f8fa8", b2L: "#57a9c0", b2H: "#8fd0e0", b2D: "#2c6a80",
                soil: ("#b59a70", "#a68b62"), root: "#98794f", rootD: "#7f653f", pebble: "#94866c",
                grain: ("#c39a5f", "#f0d9a6"), edge: ("#cda468", "#c39a5f"),
                mode: .desert, weather: .dust, roots: false)
        case .mars:
            // Rust plain under a dust-scattered sky: mesas on the skyline, two small
            // moons, and a dust devil crossing. The body is a step brighter than the
            // meadow's so he still reads against the ground.
            return Palette(sky: [(196, 108, 74), (242, 196, 160)], cl: ["#f2d4be", "#dcb59c"], nC: 1,
                dk: "#7c3f26", md: "#9c5433", lt: "#b0603a", fl: "#ffd9b0", fl2: "#e8b48a", gr: "#9c5433",
                rk: "#7c3f26", rkd: "#5e2e1b", bl: "#7c3f26", blL: "#a8623a", mote: "#ffd9b0", sh: "#7a3e24",
                bd: "#e8813b", bdL: "#f59a52", bdH: "#ffbc7e", bdD: "#a8471a", bz: "#8f3a17", s1: "#3f1a10", s2: "#2c110a", fc: "#ffd08a",
                b2: "#3f8fa8", b2L: "#57a9c0", b2H: "#8fd0e0", b2D: "#2c6a80",
                soil: ("#7c4228", "#6b3821"), root: "#8f5535", rootD: "#6e3520", pebble: "#8f5c3c",
                grain: ("#88462a", "#b06a44"), edge: ("#9c5433", "#93502f"),
                mode: .mars, weather: .devil, roots: false)
        case .autumn:
            return Palette(sky: [(110, 150, 190), (236, 220, 190)], cl: ["#ffeed8", "#e2c9ae"], nC: 3,
                dk: "#8a3a1a", md: "#c26a20", lt: "#e8a02e", fl: "#ffd45c", fl2: "#f0902e", gr: "#7a5a24",
                rk: "#8a7f72", rkd: "#635a4f", bl: "#8a6a2a", blL: "#c99a3a", mote: "#ffd9a0", sh: "#5f4519",
                bd: "#d9692b", bdL: "#e8813b", bdH: "#f5a45e", bdD: "#b84d1c", bz: "#a34a1f", s1: "#5b2a15", s2: "#4a2011", fc: "#f2913f",
                b2: "#3f8fa8", b2L: "#57a9c0", b2H: "#8fd0e0", b2D: "#2c6a80",
                soil: ("#4a3a24", "#3f311e"), root: "#8f6a45", rootD: "#66482c", pebble: "#6e655c",
                weather: .leaves)
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
    /// Colour of the soil at the bitmap's bottom edge, so the caller can extend the
    /// panel below it without a step.
    var groundColor: NSColor {
        let c = soil(max(0, totalH - H - 1), dark: true)
        return NSColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
    }

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
    private struct Drop { var x, y, sp: Double; var len: Int }
    private struct Splash { var x, y, ph: Double }
    private struct Leaf { var x, y, sp, ph, c: Double }
    private struct Cactus { var x, y, h: Double; var arm, fl: Bool }

    private var clouds: [Cloud] = [], bushes: [Bush] = [], blades: [Blade] = []
    private var motes: [Mote] = [], twk: [Twinkle] = [], gulls: [Gull] = []
    private var drops: [Drop] = [], splashes: [Splash] = [], leaves: [Leaf] = [], cacti: [Cactus] = []
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
        if P.sun {
            // The desert's sun sits high and pale; the golden hour's hangs low and warm.
            if P.mode == .desert { circ(sky, Wd * 0.24, Hd * 0.30, Int((Hd * 0.11).rounded()), "#fff0c0") }
            else { circ(sky, Wd * 0.30, Hd * 0.52, 13, "#ffe0a8") }
        }
        if P.mode == .regolith { planet(Wd * 0.76, Hd * 0.24, Int((Hd * 0.13).rounded())) }
        if P.mode == .mars {
            circ(sky, Wd * 0.70, Hd * 0.17, 4, "#cbb6a4")
            circ(sky, Wd * 0.70 - 1, Hd * 0.17 - 1, 2, "#e0cec0")
            circ(sky, Wd * 0.87, Hd * 0.30, 2, "#bda694")
        }

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
        blades = []
        func mass(_ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ n: Int, _ seed: Int) {
            var p = Rnd(seed)
            for _ in 0..<n {
                let px = x0 + p.next() * (x1 - x0), py = y0 + p.next() * (y1 - y0), rad = Hd * (0.035 + p.next() * 0.06)
                let dark = p.next() < 0.45, ph = p.next() * 6.28
                let f: (Double, Double)? = p.next() < 0.5 ? (px + (p.next() - 0.5) * rad, py - rad * 0.55) : nil
                bushes.append(Bush(x: px, y: py, r: rad, dark: dark, ph: ph, f: f))
            }
        }
        // Only the land scenes grow anything; the desert, the moon and Mars are bare
        // ground, so they skip the bushes and grass entirely.
        if P.mode == .land {
            if !P.water {
                mass(-Wd * 0.04, Wd * 0.30, Hd * 0.55, Hd * 0.76, 30, 3)
                mass(Wd * 0.70, Wd * 1.04, Hd * 0.52, Hd * 0.74, 28, 9)
            }
            mass(-Wd * 0.04, Wd * 1.04, Hd * 0.78, Hd * 1.04, P.water ? 18 : 46, 15)
            var r3 = Rnd(33)
            let nb = Int((Wd * (P.water ? 0.35 : 0.95)).rounded())
            for _ in 0..<nb {
                blades.append(Blade(x: r3.next() * Wd, y: Hd * (0.80 + r3.next() * 0.22), h: Hd * (0.03 + r3.next() * 0.07), ph: r3.next() * 6.28, c: r3.next() < 0.35))
            }
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
        let gy = (Hd * 0.74).rounded()
        drops = []
        splashes = []
        var r7 = Rnd(71)
        for _ in 0..<Int((Wd * 0.4).rounded()) {
            drops.append(Drop(x: r7.next() * Wd, y: r7.next() * Hd, sp: 2.4 + r7.next() * 1.8, len: 3 + Int(r7.next() * 4)))
        }
        for _ in 0..<10 { splashes.append(Splash(x: r7.next() * Wd, y: gy + r7.next() * (Hd - gy), ph: r7.next() * 6.28)) }
        leaves = []
        var r8 = Rnd(89)
        for _ in 0..<26 {
            leaves.append(Leaf(x: r8.next() * Wd, y: r8.next() * Hd, sp: 0.35 + r8.next() * 0.5, ph: r8.next() * 6.28, c: r8.next()))
        }
        cacti = []
        if P.mode == .desert {
            var r9 = Rnd(23)
            for i in 0..<5 {
                var cx = (0.06 + Double(i) * 0.21 + r9.next() * 0.05) * Wd
                // Nothing right where the computers stand.
                if abs(cx - Wd / 2) < Wd * 0.14 { cx += Wd * 0.2 }
                cacti.append(Cactus(x: cx, y: Hd * (0.78 + r9.next() * 0.16), h: Hd * (0.10 + r9.next() * 0.10),
                                    arm: r9.next() < 0.7, fl: r9.next() < 0.5))
            }
        }
        bakeGround()
    }

    /// Earth over the moon base: a shaded disc with a couple of continents.
    private func planet(_ cx: Double, _ cy: Double, _ r: Int) {
        let rd = Double(r)
        for dy in -r...r {
            let w = Double(Int(Double(r * r - dy * dy).squareRoot()))
            fill(sky, "#2f63a4"); rect(sky, cx - w, cy + Double(dy), w * 2 + 1, 1)
            fill(sky, "#22497b"); rect(sky, cx + w - (w * 0.5).rounded(), cy + Double(dy), (w * 0.5).rounded() + 1, 1)
        }
        circ(sky, cx - rd * 0.25, cy - rd * 0.2, Int((rd * 0.34).rounded()), "#3f8b57")
        circ(sky, cx + rd * 0.1, cy + rd * 0.35, Int((rd * 0.26).rounded()), "#3f8b57")
        circ(sky, cx - rd * 0.55, cy + rd * 0.42, Int((rd * 0.16).rounded()), "#4f9c63")
        fill(sky, "#cfe2f5")
        rect(sky, cx - rd * 0.7, cy - rd * 0.55, (rd * 0.5).rounded(), 1)
        rect(sky, cx - rd * 0.2, cy + rd * 0.05, (rd * 0.45).rounded(), 1)
    }

    /// Ground that never moves, painted into the static background. `land` is not baked:
    /// its grass band goes down per frame because the bushes and blades draw over it.
    private func bakeGround() {
        let Wd = Double(W), Hd = Double(H), gy = (Hd * 0.74).rounded()
        var r = Rnd(77)
        /// Sand/dust laid down in sine-edged bands, each one nearer than the last.
        func bands(_ list: [(Double, Double, Double, String)]) {
            for (i, b) in list.enumerated() {
                fill(sky, b.3)
                for x in 0..<W {
                    let y = (b.0 + sin(Double(x) * b.2 + Double(i) * 2.1) * b.1).rounded()
                    rect(sky, Double(x), y, 1, Hd - y)
                }
            }
        }
        func speckle(_ n: Int, _ top: Double, _ a: String, _ b: String) {
            for _ in 0..<n {
                let x = r.next() * Wd, y = top + r.next() * (Hd - top)
                fill(sky, r.next() < 0.5 ? a : b); rect(sky, x, y, 1, 1)
            }
        }
        switch P.mode {
        case .land:
            return
        case .desert:
            bands([(Hd * 0.56, 4, 0.045, "#e8cd98"), (Hd * 0.64, 5, 0.032, "#dcbb7e"), (gy, 6, 0.026, "#cda468")])
            speckle(Int((Wd * 1.6).rounded()), Hd * 0.58, "#c39a5f", "#f0d9a6")
        case .regolith:
            fill(sky, P.gr); rect(sky, 0, gy - 4, Wd, Hd - gy + 4)
            fill(sky, "#6b6971")
            for x in 0..<W {
                let y = (gy - 4 + sin(Double(x) * 0.05) * 2 + sin(Double(x) * 0.13) * 1.4).rounded()
                rect(sky, Double(x), y, 1, 3)
            }
            speckle(Int((Wd * 1.8).rounded()), gy, "#55535b", "#6e6c75")
            // Craters: a rim, a lit inner wall, and the floor in the ground's own tone.
            for c in [(0.16, 0.86, 9.0), (0.42, 0.94, 6.0), (0.80, 0.84, 7.0), (0.62, 0.99, 5.0)] {
                let rad = Int(max(3, (c.2 * Wd / 240).rounded()))
                circ(sky, c.0 * Wd, c.1 * Hd, rad, P.rkd)
                circ(sky, c.0 * Wd, c.1 * Hd - 1, rad - 1, "#67656e")
                circ(sky, c.0 * Wd, c.1 * Hd - 2, max(0, rad - 3), P.gr)
            }
        case .mars:
            // Mesas: a flat cap, skirts sloping in over the outer tenth, the right
            // face in shadow, and strata banding down the front.
            for m in [(-0.02, 0.24, 0.15), (0.38, 0.13, 0.09), (0.76, 0.28, 0.13)] {
                let x0 = m.0 * Wd, w0 = m.1 * Wd, hh = m.2 * Hd
                for i in 0..<Int(w0.rounded()) {
                    let f = Double(i) / w0
                    var top = gy - hh
                    if f < 0.10 { top = gy - hh * (f / 0.10) }
                    if f > 0.90 { top = gy - hh * ((1 - f) / 0.10) }
                    fill(sky, f > 0.62 ? "#6e3520" : "#8a4429")
                    rect(sky, x0 + Double(i), top, 1, gy - top)
                    fill(sky, "#b2653c")
                    rect(sky, x0 + Double(i), top, 1, f < 0.10 || f > 0.90 ? 1 : 2)
                }
                for k in 1..<3 {
                    fill(sky, k % 2 == 0 ? "#80412a" : "#93502f")
                    rect(sky, x0 + w0 * 0.12, gy - hh + hh * Double(k) / 3, w0 * 0.76, 1)
                }
            }
            bands([(Hd * 0.66, 4, 0.03, "#b0603a"), (gy, 5, 0.024, P.gr)])
            speckle(Int((Wd * 1.8).rounded()), Hd * 0.66, "#88462a", "#b06a44")
            for _ in 0..<9 {
                let x = r.next() * Wd, y = gy + 2 + r.next() * (Hd - gy - 2), w = 1 + (r.next() * 2).rounded()
                fill(sky, "#6e3520"); rect(sky, x, y, w, w)
                fill(sky, "#5e2c1a"); rect(sky, x, y + w, w, 1)
            }
        }
    }

    /// How deep the underground is *generated*, in scene pixels, regardless of how much
    /// of it the panel currently shows. Anything below the panel is clipped by the
    /// context. Deriving this from the panel's height instead reshuffled the whole
    /// pattern on every resize, because both the pebble count and the roots' RNG
    /// consumption changed with it.
    private static let groundDepth = 600

    /// How deep the soil takes to reach its base tone. Grass and bushes hide the join,
    /// so a dozen rows is plenty there; bare ground has nothing to hide behind, and any
    /// step at all reads as the landscape being cut off — it fades over hundreds of
    /// rows. A constant, not the panel height: deriving it from `totalH` re-tinted
    /// every soil pixel on each resize (the same lesson as `groundDepth`).
    private var soilFade: Double { P.roots ? Double(max(14, H / 6)) : Double(PixelScene.groundDepth) / 2 }

    private func rgb(_ hex: String) -> (Double, Double, Double) {
        var s = hex; s.removeFirst()
        let v = UInt32(s, radix: 16) ?? 0
        return (Double((v >> 16) & 255), Double((v >> 8) & 255), Double(v & 255))
    }
    private func lerp(_ a: (Double, Double, Double), _ b: (Double, Double, Double), _ t: Double) -> (Double, Double, Double) {
        let f = max(0, min(1, t))
        return (a.0 + (b.0 - a.0) * f, a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f)
    }
    private func cg(_ c: (Double, Double, Double)) -> CGColor {
        CGColor(srgbRed: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
    }

    /// Soil colour `depth` rows below the scene — the scene's own ground tone at the
    /// top, `P.soil` once `soilFade` rows down. `dark` picks the dither's other half.
    private func soil(_ depth: Int, dark: Bool) -> (Double, Double, Double) {
        let e = P.edge.0.isEmpty ? (P.gr, P.dk) : P.edge
        return lerp(rgb(dark ? e.1 : e.0), rgb(dark ? P.soil.1 : P.soil.0), Double(depth) / soilFade)
    }

    /// A thing *in* the soil — root, pebble, rock band — faded in with depth, so nothing
    /// pops out of the ground right where the landscape ends.
    private func buried(_ hex: String, _ depth: Int, boost: Double = 1.6) -> CGColor {
        cg(lerp(soil(depth, dark: false), rgb(hex), Double(depth) / soilFade * boost))
    }

    /// Soil with roots and pebbles for the rows below the scene, baked into `sky`
    /// (the static background) so the animation loop doesn't pay for it.
    private func underground() {
        guard totalH > H else { return }
        let Wd = Double(W), top = H
        // No line where the landscape ends: the soil simply carries on in the scene's
        // own ground colour and darkens with depth (see `soil`).
        for y in top..<totalH {
            let light = cg(soil(y - top, dark: false)), dark = cg(soil(y - top, dark: true))
            for x in 0..<W {
                sky.setFillColor(((x + y) & 1 == 0) ? light : dark)
                rect(sky, Double(x), Double(y), 1, 1)
            }
        }
        // The meadow hides the join under grass, bushes and roots; bare ground has
        // nothing growing over it, so its surface speckle carries on into the soil
        // instead — same tones, thinning out and blending into the soil colour on the
        // way down. Without this the baked texture stops dead at the scene's last row
        // and the join reads as a hard line however well the colours match.
        if !P.roots {
            var rg = Rnd(93)
            let fade = 44.0
            for _ in 0..<(W * 2) {
                let x = Double(Int(rg.next() * Wd))
                let d = Int(fade * (1 - rg.next().squareRoot())) // densest at the seam
                let tone = rgb(rg.next() < 0.5 ? P.grain.0 : P.grain.1)
                sky.setFillColor(cg(lerp(tone, soil(d, dark: false), Double(d) / fade)))
                rect(sky, x, Double(top + d), 1, 1)
            }
        }
        // Pebbles.
        var rp = Rnd(97)
        for _ in 0..<(PixelScene.groundDepth * W / 700) {
            let x = Double(Int(rp.next() * Wd))
            let y = Double(top + 3 + Int(rp.next() * Double(PixelScene.groundDepth - 3)))
            let big = rp.next() < 0.3, d = Int(y) - top
            sky.setFillColor(buried(P.pebble, d)); rect(sky, x, y, big ? 3 : 2, big ? 2 : 1)
            sky.setFillColor(cg(soil(d, dark: true))); rect(sky, x, y + (big ? 2 : 1), big ? 3 : 2, 1)
        }
        // Roots: random walks down from the grass line that thin out and branch.
        var rr = Rnd(101)
        func grow(x0: Int, y0: Int, length: Int, width: Int, drift: Double) {
            var x = x0, dx = drift
            for i in 0..<length {
                let y = y0 + i
                // Deliberately no early exit below the visible depth: stopping here left
                // the RNG in a different state, so a taller panel changed every root
                // after this one. The context clips what falls outside.
                if rr.next() < 0.35 { dx += (rr.next() - 0.5) * 1.2 }
                dx = max(-1.2, min(1.2, dx))
                x += Int(dx.rounded())
                let w = i > length * 2 / 3 ? 1 : width
                sky.setFillColor(buried(P.root, y - H)); rect(sky, Double(x), Double(y), Double(w), 1)
                sky.setFillColor(buried(P.rootD, y - H)); rect(sky, Double(x + w), Double(y), 1, 1)
                if i > 4, width > 1, rr.next() < 0.06 {
                    grow(x0: x, y0: y, length: length / 2, width: 1, drift: dx > 0 ? -1 : 1)
                }
            }
        }
        // Bare ground has no roots to show, so the soil below it gets rock strata
        // instead: sand shelves under the desert, dust-grey ones under the moon,
        // rust bands under Mars. Otherwise the panel's lower half is a flat slab.
        guard P.roots else { return strata(below: top) }
        let nRoots = max(3, W / 28)
        for i in 0..<nRoots {
            let x = Int((Double(i) + 0.3 + rr.next() * 0.4) * Wd / Double(nRoots))
            let length = 16 + Int(rr.next() * 34), width = rr.next() < 0.5 ? 2 : 1
            grow(x0: x, y0: top + 1, length: length, width: width, drift: (rr.next() - 0.5) * 0.8)
        }
    }

    /// Layered rock under the scenes that grow nothing. Each band is seeded and laid
    /// down top-down, so a taller panel only ever adds bands below the ones it had.
    private func strata(below top: Int) {
        var r = Rnd(107)
        var y = Double(top + 6)
        while y < Double(totalH) {
            let light = r.next() < 0.5, d = Int(y) - top
            let band = buried(light ? P.root : P.rootD, d, boost: 0.85)
            sky.setFillColor(band)
            for x in 0..<W {
                let yy = (y + sin(Double(x) * 0.035 + y * 0.7) * 1.8 + sin(Double(x) * 0.011) * 1.2).rounded()
                rect(sky, Double(x), yy, 1, light ? 2 : 3)
            }
            // A lighter lip on the band, the way sediment catches the light.
            sky.setFillColor(buried(P.pebble, d, boost: 0.7))
            for x in stride(from: 0, to: W, by: 3) {
                let yy = (y + sin(Double(x) * 0.035 + y * 0.7) * 1.8 + sin(Double(x) * 0.011) * 1.2).rounded()
                if r.next() < 0.5 { rect(sky, Double(x), yy, 2, 1) }
            }
            y += 7 + r.next() * 11
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

    /// A saguaro: a rounded column, a lit edge, one or two arms and a flower.
    private func cactus(_ c: Cactus) {
        let w = max(3, (Double(H) * 0.032).rounded())
        rr(c.x - w / 2, c.y - c.h, w, c.h, (w / 2).rounded(), P.md)
        R(c.x - w / 2 + 1, c.y - c.h + 2, 1, c.h - 4, P.lt)
        if c.arm {
            let ay = c.y - c.h * 0.62
            R(c.x + w / 2, ay, (w * 1.1).rounded(), max(2, (w * 0.55).rounded()), P.md)
            rr(c.x + w / 2 + (w * 0.6).rounded(), ay - c.h * 0.3, max(2, (w * 0.7).rounded()), c.h * 0.34, 2, P.md)
            R(c.x - w / 2 - (w * 0.9).rounded(), ay + 3, (w * 0.9).rounded(), max(2, (w * 0.5).rounded()), P.dk)
            rr(c.x - w / 2 - (w * 0.9).rounded(), ay - c.h * 0.16, max(2, (w * 0.6).rounded()), c.h * 0.22, 2, P.dk)
        }
        if c.fl { R(c.x - 1, c.y - c.h - 2, 2, 2, P.fl); R(c.x + 2, c.y - c.h, 1, 1, P.fl2) }
    }

    /// Ground detail a particular weather leaves behind: rain puts puddles in the grass,
    /// autumn a litter of fallen leaves. Per frame, not baked, because the grass band is
    /// repainted over the background every frame.
    private func groundCover() {
        let Wd = Double(W), Hd = Double(H), gy = (Hd * 0.74).rounded(), k = Wd / 240
        switch P.weather {
        case .rain:
            for p in [(0.30, 0.92, 16.0), (0.66, 0.86, 12.0), (0.12, 0.99, 10.0)] {
                let cx = p.0 * Wd, cy = p.1 * Hd, w = p.2 * k
                for dy in -2...2 {
                    let ww = (w * max(0, 1 - Double(dy * dy) / 6).squareRoot()).rounded()
                    R(cx - ww, cy + Double(dy), ww * 2, 1, "#3f5a5e")
                }
                R(cx - w * 0.5, cy - 2, w * 0.7, 1, "#7d99a0")
            }
        case .leaves:
            var r = Rnd(87)
            let tones = ["#c9691f", "#e8a02e", "#a5401a", "#d98a2a"]
            for _ in 0..<Int((Wd * 0.5).rounded()) {
                let x = r.next() * Wd, y = gy + 2 + r.next() * (Hd - gy - 2)
                R(x, y, 2, 1, tones[Int(r.next() * 4)])
            }
        default: break
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
        let shR = bw * 0.46 * (1 - 0.25 * sin(.pi * joy))
        let shY = by + hop + bh - (2 * S).rounded()
        if P.mode == .land && !P.water {
            // Grass and bushes swallow the shape here, so the round blob reads fine.
            circ(cx, shY, Int(shR.rounded()), P.sh)
        } else {
            // Open ground shows the whole shadow, and a solid dark disc read as a hole
            // in the sand. A flat pool instead — squashed, dither-edged so the ground's
            // grain shows through — nudged off-centre when a sun hangs in the sky.
            groundShadow(cx: cx + (P.sun ? shR * 0.3 : 0), y: shY, rx: shR)
        }
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

    /// Shadow on open ground: a flattened ellipse under the feet, solid at the core and
    /// checker-dithered towards the rim so it reads as thin shade over the ground's own
    /// texture rather than a stamped-out shape. (A solid bar was tried on the beach once
    /// and read as a plank; the dithered rim is what keeps this from doing the same.)
    private func groundShadow(cx: Double, y: Double, rx: Double) {
        let ry = max(2, (rx * 0.16).rounded())
        let icx = cx.rounded(), icy = y.rounded()
        fill(ctx, P.sh)
        var dy = -ry
        while dy <= ry {
            let w = (rx * (1 - dy * dy / (ry * ry + 1)).squareRoot()).rounded()
            var dx = -w
            while dx <= w {
                let nx = dx / (rx * 0.68), ny = dy / (ry * 0.68 + 0.5)
                if nx * nx + ny * ny <= 1 || (Int(icx + dx + icy + dy) & 1) == 0 {
                    rect(ctx, icx + dx, icy + dy, 1, 1)
                }
                dx += 1
            }
            dy += 1
        }
    }

    /// Main computer plus a smaller, differently coloured one peeking out behind it.
    private func mac() {
        let Wd = Double(W), Hd = Double(H)
        let S = Hd / 170 * 1.16, ground = (Hd * 0.30).rounded() + (62 * S).rounded()
        computer(cx: (Wd / 2 + 36 * S).rounded(), groundY: ground - (6 * S).rounded(), scale: 0.6, phase: 2.1,
                 body: (P.b2, P.b2L, P.b2H, P.b2D), face: (P.b2D, "#12333c", "#0c262d", "#bff2ff"))
        computer(cx: Wd / 2, groundY: ground, scale: 1, phase: 0, body: (P.bd, P.bdL, P.bdH, P.bdD), face: (P.bz, P.s1, P.s2, P.fc))
        // Foreground bushes at the small one's feet so its base doesn't end in a hard line.
        // Bare-ground scenes have none: there the round shadow does that job on its own.
        guard P.mode == .land else { return }
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
        if P.mode == .desert {
            // The dunes are baked; only the rock on the skyline is drawn here.
            let rock = [(0.80, 0.76), (0.86, 0.70), (0.93, 0.77), (0.91, 0.86), (0.81, 0.85)]
            poly(rock.map { ($0.0 * Wd, $0.1 * Hd) }, P.rk)
        } else if P.mode == .regolith || P.mode == .mars {
            // Fully baked: craters, mesas and dust never move.
        } else if P.water {
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
            groundCover()
            for b in bushes where b.y <= Hd * 0.78 { bush(b) }
            for i in 0..<2 {
                let p = rocks[i].map { ($0.0 * Wd, $0.1 * Hd) }
                poly(p, P.rk)
                poly(p.enumerated().map { ($0.element.0 + ($0.offset < 2 ? 0 : 2), $0.element.1 + 3) }, P.rkd)
            }
        }
        mac()
        if P.mode == .land {
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
        }
        // Cacti stand in front of the pair, like the meadow's foreground bushes do.
        if P.mode == .desert { for c in cacti { cactus(c) } }
        weather()
        return ctx.makeImage()!
    }

    /// Everything drifting in front of the scene. Like the rest of the frame it is a
    /// function of `t` alone — nothing is accumulated — so a rebuild mid-shower or
    /// mid-flash lands on exactly the same frame.
    private func weather() {
        let Wd = Double(W), Hd = Double(H), gy = (Hd * 0.74).rounded()
        switch P.weather {
        case .motes:
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
        case .rain:
            for d in drops {
                let y = drift(d.y, step: d.sp, from: -6, to: Hd)
                let x = drift(d.x, step: -d.sp * 0.28, from: -6, to: Wd + 6)
                for k in 0..<d.len { R(x + Double(k) * 0.28, y - Double(k), 1, 1, k == 0 ? "#dbeaf2" : "#9fbccb") }
            }
            // Splashes ring out where the drops land, each on its own phase.
            for s in splashes {
                let ph = (t * 2.4 + s.ph).truncatingRemainder(dividingBy: 1)
                if ph < 0.5 {
                    let rad = (ph * 6).rounded()
                    R(s.x - rad, s.y, 1, 1, "#cfe4f0"); R(s.x + rad, s.y, 1, 1, "#cfe4f0")
                }
            }
            // Lightning every 7.4 s: two frames of flash, and a bolt down the right.
            let lc = t.truncatingRemainder(dividingBy: 7.4)
            if lc < 0.16 {
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: lc < 0.07 ? 0.30 : 0.14))
                rect(ctx, 0, 0, Wd, Hd)
                var px = Wd * 0.66, py = Hd * 0.06
                for seg in [(-3.0, 0.047), (2.0, 0.047), (-4.0, 0.107), (3.0, 0.067), (-1.0, 0.067)] {
                    px += seg.0 * (Wd / 240)
                    let h = seg.1 * Hd
                    R(px, py, 2, h, "#fdfbe8")
                    py += h
                }
            }
        case .leaves:
            for l in leaves {
                let y = drift(l.y, step: l.sp, from: -4, to: Hd)
                let x = l.x + sin(t * 1.1 + l.ph) * 7
                let flip = sin(t * 4 + l.ph) > 0
                R(x, y, flip ? 2 : 1, flip ? 1 : 2, l.c < 0.33 ? "#e8a02e" : (l.c < 0.66 ? "#d9601f" : "#b8842a"))
                R(x + (flip ? 0 : 1), y + 1, 1, 1, "#8a4a16")
            }
        case .dust:
            for m in motes {
                let x = drift(m.x, step: 0.35 + m.sp, from: -2, to: Wd)
                R(x, m.y * 0.35 + Hd * 0.6 + sin(t + m.ph) * 2, 1, 1, "#f2dcae")
            }
            // Tumbleweed: a ring of pixels rolling along the near edge of the dunes.
            let tx = (t * 16).truncatingRemainder(dividingBy: Wd + 40) - 20
            let ty = gy + Hd * 0.14 - abs(sin(t * 3)) * 3, rad = max(2, (Hd * 0.045).rounded())
            for k in 0..<12 {
                let a = Double(k) * 0.52 + t * 3.4
                R(tx + cos(a) * rad, ty + sin(a) * rad, 1, 1, "#b98f52")
                R(tx + cos(a) * rad * 0.55, ty + sin(a) * rad * 0.55, 1, 1, "#a67d43")
            }
            R(tx - rad, ty + rad + 1, rad * 2, 1, "#c9a469")
        case .sparks:
            for m in motes {
                let y = drift(m.y, step: -m.sp * 0.3, from: Hd * 0.3, to: Hd)
                if sin(t * 3 + m.ph) > 0 { R(m.x + sin(t * 0.5 + m.ph) * 4, y, 1, 1, P.mote) }
            }
            let sh = (t * 0.6).truncatingRemainder(dividingBy: 9)
            if sh < 0.5 {
                let sx = Wd * 0.1 + sh * Wd * 0.9, sy = Hd * 0.1 + sh * Hd * 0.5
                for k in 0..<6 { R(sx - Double(k) * 2, sy - Double(k), 1, 1, k < 2 ? "#ffffff" : "#9fc6ff") }
            }
        case .devil:
            // A dust devil crossing the plain: a column of pixels on a widening spiral.
            let cx = (t * 9).truncatingRemainder(dividingBy: Wd + 60) - 30
            for k in 0..<Int((Hd * 0.34).rounded()) {
                let yy = gy + 2 - Double(k), rad = 1.5 + Double(k) * 0.30, a = t * 5 + Double(k) * 0.55
                R(cx + cos(a) * rad, yy, 1, 1, k < 6 ? "#c98f62" : "#d9a97e")
                if k % 2 == 0 { R(cx + cos(a + .pi) * rad * 0.7, yy, 1, 1, "#b87c50") }
            }
            R(cx - 3, gy + 2, 7, 1, "#b87c50")
            for m in motes {
                let x = drift(m.x, step: 0.3 + m.sp, from: -2, to: Wd)
                R(x, Hd * 0.62 + m.y * 0.22 + sin(t + m.ph) * 2, 1, 1, "#e8b48a")
            }
        }
    }
}
