import AppKit
import SceneKit
import SwiftUI
import FocusUI

/// The pairing code as a little garden (owner, 2026-10-24: "like tree.icqr.com ... exactly the same animation", summer only, no sound, in
/// Hushd's green). A leafy tree stands on a tiled plaza in an isometric view. Tap it and the leaves fall away, the tree sinks into the
/// ground, and the camera swings over the top: what is left is the pairing QR code, drawn in flat green and cream tiles. Tap again and it
/// grows back. The dark modules of the code are the tree's canopy (columns under the leaves) and the three finder squares are patches
/// of grass, as on the site that inspired it.
///
/// Everything is driven by one number, `t`, 0 for the tree and 1 for the code, so a tap in mid-flight reverses from wherever it is, and
/// any frame can be drawn offscreen for a test. At exactly 1 the camera is straight overhead and orthographic, the tiles are unlit flat
/// colors and nothing stands above them, so the code scans (a test decodes it).
final class GardenScene {
    // MARK: palette (Hushd's green; every dark shade is dark enough to scan against the cream)
    static let cream = NSColor(srgbRed: 0.953, green: 0.937, blue: 0.890, alpha: 1)
    static let darks: [NSColor] = [(0.07, 0.30, 0.17), (0.10, 0.36, 0.20), (0.06, 0.26, 0.15), (0.12, 0.40, 0.23), (0.09, 0.33, 0.24)]
        .map { NSColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: 1) }
    static let leaves: [NSColor] = [(0.42, 0.80, 0.46), (0.50, 0.85, 0.52), (0.33, 0.72, 0.42), (0.58, 0.88, 0.60), (0.38, 0.76, 0.54)]
        .map { NSColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: 1) }
    static let grass: [NSColor] = [(0.16, 0.58, 0.30), (0.24, 0.68, 0.36), (0.34, 0.76, 0.40), (0.28, 0.64, 0.34)]
        .map { NSColor(srgbRed: $0.0, green: $0.1, blue: $0.2, alpha: 1) }
    static let trunk = NSColor(srgbRed: 0.40, green: 0.27, blue: 0.21, alpha: 1)
    static let slab = NSColor(srgbRed: 0.76, green: 0.74, blue: 0.72, alpha: 1)

    /// The quiet zone left around the code when seen from above, in modules.
    static let quiet: Double = 4

    let scene = SCNScene()
    let n: Int
    let yaw = SCNNode(), pitch = SCNNode(), cameraNode = SCNNode()
    private let modules: [[Bool]]

    private struct Column { let node: SCNNode; let bottom: Double, top: Double }
    private var columns: [Column] = []
    private struct Cluster { let node: SCNNode; let home: SCNVector3; let delay: Double; let phase: Double; let spin: Double }
    private var clusters: [Cluster] = []
    private var grassNodes: [SCNNode] = []
    private let trunkNode = SCNNode()
    private let shade = SCNNode()
    private let canopy = SCNNode()
    private var codeFloor = SCNNode()

    init(modules: [[Bool]]) {
        self.modules = modules; n = modules.count
        var rng = Rng(seed: UInt64(modules.count) &* 7919)
        scene.background.contents = Self.cream
        buildCamera()
        buildLights()
        buildFloor(&rng)
        buildColumns(&rng)
        buildLeaves(&rng)
        buildGrass(&rng)
        buildTrunk(&rng)
        apply(t: 0, time: 0, intro: 1)
    }

    // MARK: building

    private func buildCamera() {
        let cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.zNear = 1; cam.zFar = 400
        cameraNode.camera = cam; cameraNode.position = SCNVector3(0, 0, 120)
        pitch.addChildNode(cameraNode); yaw.addChildNode(pitch); scene.rootNode.addChildNode(yaw)
    }

    private func buildLights() {
        let amb = SCNNode(); amb.light = SCNLight(); amb.light!.type = .ambient; amb.light!.intensity = 700; amb.light!.color = NSColor(white: 1, alpha: 1)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 900
        sun.light!.color = NSColor(srgbRed: 1, green: 0.97, blue: 0.9, alpha: 1)
        sun.eulerAngles = SCNVector3(-0.95, 0.55, 0)
        scene.rootNode.addChildNode(amb); scene.rootNode.addChildNode(sun)
    }

    private func gridX(_ c: Int) -> Double { Double(c) - Double(n) / 2 + 0.5 }
    private func gridZ(_ r: Int) -> Double { Double(r) - Double(n) / 2 + 0.5 }

    private func buildFloor(_ rng: inout Rng) {
        // Two floors. The plaza under the tree is plain cream tiles; the code is drawn on a second floor that fades in as the tree goes, so
        // the code never shows through the tree. Both are unlit, so every module is exactly its color.
        let px = 24, size = n * px
        var shadeRng = rng
        let darkPick = (0..<(n * n)).map { _ in Int(shadeRng.next() * Double(Self.darks.count)) % Self.darks.count }
        let tint = (0..<(n * n)).map { _ in shadeRng.next() }
        func image(code: Bool) -> NSImage {
            NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
                for r in 0..<self.n { for c in 0..<self.n {
                    let v = tint[r * self.n + c]
                    let color: NSColor = code && self.modules[r][c] ? Self.darks[darkPick[r * self.n + c]]
                        : NSColor(srgbRed: 0.953 - 0.03 * v * ((r + c) % 2 == 0 ? 1 : 0.5), green: 0.937 - 0.03 * v, blue: 0.890 - 0.035 * v, alpha: 1)
                    color.setFill(); NSRect(x: c * px, y: r * px, width: px, height: px).fill()
                } }
                return true
            }
        }
        func plane(_ img: NSImage, y: Double) -> SCNNode {
            let g = SCNPlane(width: Double(n), height: Double(n))
            let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = img
            m.diffuse.magnificationFilter = .nearest; m.diffuse.minificationFilter = .linear; m.diffuse.mipFilter = .none
            g.materials = [m]
            let node = SCNNode(geometry: g); node.eulerAngles.x = -.pi / 2; node.position.y = y
            scene.rootNode.addChildNode(node)
            return node
        }
        _ = plane(image(code: false), y: 0.002)
        codeFloor = plane(image(code: true), y: 0.004)

        let slab = SCNBox(width: Double(n), height: 0.9, length: Double(n), chamferRadius: 0)
        let sm = SCNMaterial(); sm.lightingModel = .lambert; sm.diffuse.contents = Self.slab
        slab.materials = [sm]
        let slabNode = SCNNode(geometry: slab); slabNode.position.y = -0.45
        scene.rootNode.addChildNode(slabNode)

        // A soft shadow under the canopy, gone by the time the code is showing.
        let d = 256
        let blob = NSImage(size: NSSize(width: d, height: d), flipped: false) { r in
            NSGradient(colors: [NSColor(white: 0, alpha: 0.28), NSColor(white: 0, alpha: 0)])?.draw(in: r, relativeCenterPosition: .zero)
            return true
        }
        let sp = SCNPlane(width: Double(n) * 1.1, height: Double(n) * 1.1)
        let bm = SCNMaterial(); bm.lightingModel = .constant; bm.diffuse.contents = blob; bm.transparencyMode = .aOne; bm.writesToDepthBuffer = false
        sp.materials = [bm]
        shade.geometry = sp; shade.eulerAngles.x = -.pi / 2; shade.position.y = 0.02
        scene.rootNode.addChildNode(shade)
    }

    private func isFinder(_ r: Int, _ c: Int) -> Bool {
        let e = n - 7
        return (r < 7 && c < 7) || (r < 7 && c >= e) || (r >= e && c < 7)
    }

    /// The dark modules outside the finder squares become columns of the canopy: tall near the middle, low at the edge, floating above
    /// the plaza so the trunk and the floor show underneath.
    private func buildColumns(_ rng: inout Rng) {
        let geo = SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0)
        var mats: [SCNMaterial] = []
        for color in Self.darks { let m = SCNMaterial(); m.lightingModel = .lambert; m.diffuse.contents = color; mats.append(m) }
        for r in 0..<n { for c in 0..<n where modules[r][c] && !isFinder(r, c) {
            let x = gridX(c), z = gridZ(r)
            let rad = min(1, hypot(x, z) / (Double(n) * 0.5))
            let top = 17 + 14 * pow(1 - rad * rad, 0.8) + rng.next() * 3.5
            let bottom = 11.5 + 2.5 * rad + rng.next() * 1.8
            let node = SCNNode(geometry: geo.copy() as? SCNGeometry)
            node.geometry?.materials = [mats[(r * 7 + c * 3) % mats.count]]
            node.pivot = SCNMatrix4MakeTranslation(0, -0.5, 0)
            node.position = SCNVector3(x, bottom, z); node.scale = SCNVector3(0.98, top - bottom, 0.98)
            scene.rootNode.addChildNode(node)
            columns.append(Column(node: node, bottom: bottom, top: top))
        } }
    }

    private func leafShape(_ color: NSColor) -> SCNGeometry {
        // A five-lobed leaf drawn as a path, flat, a unit and a half across.
        let path = NSBezierPath()
        let pts = 20
        for i in 0..<pts {
            let a = Double(i) / Double(pts) * 2 * .pi
            let lobe = 0.58 + 0.42 * abs(cos(2.5 * a))
            let rr = 0.78 * lobe
            let p = NSPoint(x: rr * sin(a), y: rr * cos(a))
            if i == 0 { path.move(to: p) } else { path.line(to: p) }
        }
        path.close(); path.flatness = 0.02
        let shape = SCNShape(path: path, extrusionDepth: 0)
        let m = SCNMaterial(); m.lightingModel = .lambert; m.diffuse.contents = color; m.isDoubleSided = true
        shape.materials = [m]
        return shape
    }

    private func buildLeaves(_ rng: inout Rng) {
        scene.rootNode.addChildNode(canopy)
        let shapes = Self.leaves.map(leafShape)
        // Leaves go in clusters merged into one node each, so a hundred draws carry a couple of thousand leaves.
        let cell = 4.0
        var buckets: [String: [SCNNode]] = [:]
        for col in columns {
            let x = Double(col.node.position.x), z = Double(col.node.position.z)
            for _ in 0..<(13 + Int(rng.next() * 5)) {
                let y = col.bottom + (col.top - col.bottom) * pow(rng.next(), 0.55)
                let p = SCNVector3(x + (rng.next() - 0.5) * 2.0, y, z + (rng.next() - 0.5) * 2.0)
                let leaf = SCNNode(geometry: shapes[Int(rng.next() * Double(shapes.count)) % shapes.count])
                leaf.position = p
                let out = SCNVector3(p.x * 0.02, (p.y - 14) * 0.03, p.z * 0.02)
                leaf.eulerAngles = SCNVector3(-.pi / 2 + (rng.next() - 0.5) * 1.3 + out.y, rng.next() * 2 * .pi, (rng.next() - 0.5) * 1.3 + out.x)
                let s = 1.25 + rng.next() * 0.8; leaf.scale = SCNVector3(s, s, s)
                let gx = Int(((x + 40) / cell).rounded(.down)), gz = Int(((z + 40) / cell).rounded(.down)), gy = Int(y / 5)
                buckets["\(gx)_\(gz)_\(gy)", default: []].append(leaf)
            }
        }
        for (_, leaves) in buckets {
            let c = leaves.reduce(SCNVector3Zero) { SCNVector3($0.x + $1.position.x, $0.y + $1.position.y, $0.z + $1.position.z) }
            let k = CGFloat(leaves.count)
            let centroid = SCNVector3(c.x / k, c.y / k, c.z / k)
            let holder = SCNNode()
            for l in leaves { l.position = SCNVector3(l.position.x - centroid.x, l.position.y - centroid.y, l.position.z - centroid.z); holder.addChildNode(l) }
            let merged = holder.flattenedClone()
            merged.position = centroid
            canopy.addChildNode(merged)
            clusters.append(Cluster(node: merged, home: centroid, delay: rng.next() * 0.3, phase: rng.next() * 6.28, spin: (rng.next() - 0.5) * 4))
        }
    }

    private func buildGrass(_ rng: inout Rng) {
        let blade = SCNCone(topRadius: 0, bottomRadius: 0.13, height: 1); blade.radialSegmentCount = 4
        let mats = Self.grass.map { color -> SCNMaterial in let m = SCNMaterial(); m.lightingModel = .lambert; m.diffuse.contents = color; return m }
        let e = n - 7
        for (r0, c0) in [(0, 0), (0, e), (e, 0)] {
            let holder = SCNNode()
            for r in r0..<(r0 + 7) { for c in c0..<(c0 + 7) where modules[r][c] {
                for _ in 0..<8 {
                    let b = SCNNode(geometry: blade.copy() as? SCNGeometry)
                    b.geometry?.materials = [mats[Int(rng.next() * 4) % 4]]
                    let h = 1.1 + rng.next() * 1.5
                    b.scale = SCNVector3(1, h, 1)
                    b.position = SCNVector3(gridX(c) + (rng.next() - 0.5) * 0.9, h / 2, gridZ(r) + (rng.next() - 0.5) * 0.9)
                    b.eulerAngles = SCNVector3((rng.next() - 0.5) * 0.55, 0, (rng.next() - 0.5) * 0.55)
                    holder.addChildNode(b)
                }
            } }
            let merged = holder.flattenedClone()
            scene.rootNode.addChildNode(merged); grassNodes.append(merged)
        }
    }

    private func buildTrunk(_ rng: inout Rng) {
        let holder = SCNNode()
        let mat = SCNMaterial(); mat.lightingModel = .lambert; mat.diffuse.contents = Self.trunk
        let main = SCNCone(topRadius: 0.2, bottomRadius: 0.62, height: 16); main.materials = [mat]
        let mn = SCNNode(geometry: main); mn.position.y = 8; holder.addChildNode(mn)
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi + rng.next() * 0.6
            let len = 5.0 + rng.next() * 3
            let cyl = SCNCylinder(radius: 0.1, height: len); cyl.materials = [mat]
            let b = SCNNode(geometry: cyl)
            let tilt = 0.5 + rng.next() * 0.35
            b.position = SCNVector3(sin(a) * len / 2 * sin(tilt), 12.5 + cos(tilt) * len / 2, cos(a) * len / 2 * sin(tilt))
            b.eulerAngles = SCNVector3(0, a, -tilt)
            holder.addChildNode(b)
        }
        let merged = holder.flattenedClone()
        trunkNode.addChildNode(merged)
        scene.rootNode.addChildNode(trunkNode)
    }

    // MARK: motion

    @inline(__always) private func smooth(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
    @inline(__always) private func seg(_ p: Double, _ a: Double, _ b: Double) -> Double { smooth((p - a) / (b - a)) }

    /// Puts every piece where it is at progress `t` (0 the tree, 1 the code). `time` drives the sway; `intro` (0 to 1) grows the tree in.
    func apply(t: Double, time: Double, intro: Double) {
        let p = t <= 0 ? 0 : t >= 1 ? 1 : (t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2)   // ease in out, cubic
        let flat = p >= 1
        let sway = 1 - seg(p, 0, 0.25)

        // Camera: isometric to straight overhead, with a twist on the way that is gone at both ends.
        let isoPitch = -0.58, isoYaw = Double.pi / 4
        let a = seg(p, 0.0, 1.0)
        yaw.eulerAngles = SCNVector3(0, flat ? 0 : (isoYaw * (1 - a) + 0.2 * sin(.pi * p)), 0)
        pitch.eulerAngles = SCNVector3(flat ? -.pi / 2 : isoPitch * (1 - a) + (-.pi / 2) * a, 0, 0)
        let nd = Double(n)
        yaw.position = SCNVector3(0, flat ? 0 : nd * 0.48 * (1 - a), 0)
        cameraNode.camera?.orthographicScale = flat ? nd / 2 + Self.quiet : (nd * 0.86 * (1 - a) + (nd / 2 + Self.quiet) * a)

        codeFloor.opacity = CGFloat(seg(p, 0.55, 0.95))
        shade.opacity = CGFloat(1 - seg(p, 0, 0.5))
        shade.isHidden = p >= 0.99

        // Leaves: each cluster pops in with the intro, then lets go and falls shrinking.
        for (i, cl) in clusters.enumerated() {
            let q = seg(p, 0.0 + cl.delay * 0.5, 0.45 + cl.delay)
            let grow = seg(intro, cl.home.y > 0 ? Double(cl.home.y) / 60 : 0, Double(cl.home.y) / 60 + 0.5)
            let s = max(0.0005, (1 - q) * grow)
            cl.node.scale = SCNVector3(s, s, s)
            cl.node.position = SCNVector3(cl.home.x * (1 + 0.25 * q), cl.home.y - 7 * q * q - 3 * q, cl.home.z * (1 + 0.25 * q))
            cl.node.eulerAngles = SCNVector3(0, cl.spin * q, sin(time * 1.3 + cl.phase) * 0.022 * sway)
            cl.node.isHidden = flat || s < 0.002
            _ = i
        }
        canopy.isHidden = flat

        // Columns sink to the plaza as the leaves go, ending flat and hidden (the plaza image carries their color).
        let c = seg(p, 0.12, 0.85)
        for col in columns {
            let bottom = col.bottom * (1 - c), top = col.top * (1 - c)
            col.node.position.y = CGFloat(bottom)
            col.node.scale = SCNVector3(0.98, max(0.0001, top - bottom), 0.98)
            col.node.isHidden = flat || c > 0.995
        }

        // Grass lies down into the finder squares; the trunk sinks.
        let g = seg(p, 0.2, 0.8)
        for (i, node) in grassNodes.enumerated() {
            node.scale = SCNVector3(1, max(0.0001, (1 - g) * (0.4 + 0.6 * intro)), 1)
            node.eulerAngles = SCNVector3(0, 0, sin(time * 1.5 + Double(i) * 2) * 0.01 * sway)
            node.isHidden = flat || g > 0.995
        }
        let k = seg(p, 0.3, 0.85)
        trunkNode.scale = SCNVector3(1 - 0.0 * k, max(0.0001, (1 - k) * intro), 1)
        trunkNode.isHidden = flat || k > 0.995
    }
}

/// A small deterministic random source, so the same code always grows the same tree.
struct Rng {
    var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

/// Steps the scene toward the tree or the code and draws it. Stops drawing once it rests on the code, so a code that is up for five
/// minutes costs nothing; the tree sways at 30 frames a second.
final class GardenController: NSObject, SCNSceneRendererDelegate {
    let garden: GardenScene
    weak var view: SCNView?
    private let lock = NSLock()
    private var t: Double
    private var target: Double
    private var last: TimeInterval = 0
    private var born: TimeInterval = 0
    private var snap: Bool
    static let seconds = 1.15

    init(modules: [[Bool]], startsAsCode: Bool) {
        garden = GardenScene(modules: modules)
        t = startsAsCode ? 1 : 0; target = t; snap = startsAsCode
        super.init()
    }

    func go(toCode: Bool, animated: Bool) {
        lock.lock(); target = toCode ? 1 : 0; if !animated { snap = true }; lock.unlock()
        DispatchQueue.main.async { [weak self] in self?.wake() }
    }

    func wake() { view?.isPlaying = true; view?.preferredFramesPerSecond = 60 }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if born == 0 { born = time }
        let dt = last == 0 ? 0 : min(0.05, time - last); last = time
        lock.lock()
        if snap { t = target; snap = false }
        else if t < target { t = min(target, t + dt / Self.seconds) }
        else if t > target { t = max(target, t - dt / Self.seconds) }
        let now = t, goal = target
        lock.unlock()
        let intro = min(1, (time - born) / 1.4)
        garden.apply(t: now, time: time, intro: now == 1 ? 1 : intro)
        if now == goal {
            if now == 1 { DispatchQueue.main.async { [weak self] in self?.view?.isPlaying = false } }
            else if intro >= 1 { DispatchQueue.main.async { [weak self] in self?.view?.preferredFramesPerSecond = 30 } }
        }
    }
}

/// The scene view lets clicks through to the SwiftUI tap on top of it; it never takes the mouse itself.
private final class GardenSCNView: SCNView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct GardenRepresentable: NSViewRepresentable {
    let modules: [[Bool]]
    var showsCode: Bool
    var reduceMotion: Bool

    func makeCoordinator() -> GardenController { GardenController(modules: modules, startsAsCode: reduceMotion) }

    func makeNSView(context: Context) -> SCNView {
        let v = GardenSCNView()
        let c = context.coordinator
        v.scene = c.garden.scene; v.pointOfView = c.garden.cameraNode
        v.delegate = c; c.view = v
        v.antialiasingMode = .multisampling4X
        v.allowsCameraControl = false
        v.backgroundColor = GardenScene.cream
        v.preferredFramesPerSecond = 60
        v.isPlaying = true
        return v
    }

    static func dismantleNSView(_ v: SCNView, coordinator: GardenController) {
        // The render thread must not call a delegate that is going away.
        v.isPlaying = false; v.delegate = nil; v.scene = nil
    }

    func updateNSView(_ v: SCNView, context: Context) {
        context.coordinator.go(toCode: showsCode, animated: !reduceMotion)
    }
}

/// The pairing code: a tree to tap. See `GardenScene`.
struct PairingGarden: View {
    let url: String
    @State private var showsCode = false
    var body: some View { GardenCard(url: url, showsCode: showsCode) { showsCode.toggle() } }
}

/// The card itself: the scene, its caption and its tap. `showsCode` is owned by the caller so a test can drive it.
struct GardenCard: View {
    let url: String
    var showsCode: Bool
    var toggle: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            if let modules = QRCode.modules(for: url) {
                GardenRepresentable(modules: modules, showsCode: showsCode || reduceMotion, reduceMotion: reduceMotion)
                    .frame(width: 260, height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusCard, style: .continuous))
                    .contentShape(Rectangle())
                    .onTapGesture { if !reduceMotion { toggle() } }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(showsCode || reduceMotion ? "QR code for pairing your iPhone" : "A tree. Tap it to show the QR code for pairing your iPhone")
                    .accessibilityAddTraits(.isButton)
            }
            if !reduceMotion {
                Text(showsCode ? "Tap to see the tree" : "Tap the tree to see the QR code")
                    .font(Tokens.text(.caption)).foregroundStyle(Tokens.ink2)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Tokens.well))
                    .contentTransition(.interpolate).animation(.smooth(duration: 0.25), value: showsCode)
            }
        }
    }
}
