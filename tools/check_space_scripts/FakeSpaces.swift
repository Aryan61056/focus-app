import AppKit

// A stand-in for Arc and Dia that follows their scripting dictionaries (windows, spaces or profiles, tabs; focus and select).
// It lets the app's real AppleScript text run through Cocoa scripting without Automation permission, because the script talks to this
// same process. It tests the scripts' control flow, not the real browsers.

func cd(_ c: AnyClass) -> NSScriptClassDescription { NSClassDescription(for: c) as! NSScriptClassDescription }

enum Model {
    static var windows: [FWindow] = []
}

@objc(FApp) final class FApp: NSApplication {
    @objc var appleScriptWindows: [FWindow] { Model.windows }
}

@objc(FWindow) final class FWindow: NSObject {
    let wid: String; var mode = "normal"
    var spaces: [FSpace] = []; var profiles: [FProfile] = []
    var activeSpaceObj: FSpace?; var activeProfileObj: FProfile?
    init(_ id: String) { wid = id }
    @objc var id: String { wid }
    @objc var windowId: String { wid }
    @objc var title: String { "window \(wid)" }
    @objc var name: String { "window \(wid)" }
    @objc var isIncognito: Bool { mode == "incognito" }
    @objc(mode) var modeText: String { mode }
    @objc var orderedIndex: Int {
        get { (Model.windows.firstIndex(of: self) ?? 0) + 1 }
        set { if let i = Model.windows.firstIndex(of: self) { Model.windows.remove(at: i); Model.windows.insert(self, at: max(0, min(Model.windows.count, newValue - 1))) } }
    }
    @objc var activeSpace: FSpace? { activeSpaceObj }
    @objc var activeProfile: FProfile? { activeProfileObj }
    @objc var activeTab: FTab? { activeSpaceObj?.selected ?? activeProfileObj?.selected }
    @objc var appleScriptSpaces: [FSpace] { spaces }
    @objc var appleScriptProfiles: [FProfile] { profiles }
    @objc var appleScriptTabs: [FTab] { spaces.flatMap { $0.tabs } + profiles.flatMap { $0.tabs } }
    override var objectSpecifier: NSScriptObjectSpecifier? {
        NSIndexSpecifier(containerClassDescription: cd(FApp.self), containerSpecifier: nil, key: "appleScriptWindows", index: orderedIndex - 1)
    }
}

@objc(FSpace) final class FSpace: NSObject {
    let sid: String; let label: String; var tabs: [FTab] = []; var selected: FTab?; weak var window: FWindow?
    init(_ id: String, _ label: String) { sid = id; self.label = label }
    @objc var id: String { sid }
    @objc var title: String { label }
    @objc var appleScriptTabs: [FTab] { tabs }
    @objc(focus:) func focus(_ c: NSScriptCommand) { window?.activeSpaceObj = self }
    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let w = window, let i = w.spaces.firstIndex(of: self) else { return nil }
        return NSIndexSpecifier(containerClassDescription: cd(FWindow.self), containerSpecifier: w.objectSpecifier, key: "appleScriptSpaces", index: i)
    }
}

@objc(FProfile) final class FProfile: NSObject {
    let label: String; var tabs: [FTab] = []; var selected: FTab?; weak var window: FWindow?
    init(_ label: String) { self.label = label }
    @objc var name: String { label }
    @objc var orderedIndex: Int { (window?.profiles.firstIndex(of: self) ?? 0) + 1 }
    @objc var appleScriptTabs: [FTab] { tabs }
    @objc(focus:) func focus(_ c: NSScriptCommand) { window?.activeProfileObj = self }
    override var objectSpecifier: NSScriptObjectSpecifier? {
        guard let w = window, let i = w.profiles.firstIndex(of: self) else { return nil }
        return NSIndexSpecifier(containerClassDescription: cd(FWindow.self), containerSpecifier: w.objectSpecifier, key: "appleScriptProfiles", index: i)
    }
}

@objc(FTab) final class FTab: NSObject {
    let tid: String; let label: String; let address: String
    weak var space: FSpace?; weak var profile: FProfile?
    init(_ id: String, _ title: String, _ url: String) { tid = id; label = title; address = url }
    @objc var id: String { tid }
    @objc var tabId: String { tid }
    @objc var title: String { label }
    @objc(URL) var urlText: String { address }
    @objc var loading: Bool { false }
    @objc(select:) func selectTab(_ c: NSScriptCommand) {   // Arc: selecting a tab also brings its space forward
        if let s = space { s.selected = self; s.window?.activeSpaceObj = s }
    }
    @objc(close:) func closeTab(_ c: NSScriptCommand) {
        if let s = space { s.tabs.removeAll { $0 === self }; if s.selected === self { s.selected = s.tabs.first } }
        if let p = profile { p.tabs.removeAll { $0 === self }; if p.selected === self { p.selected = p.tabs.first } }
    }
    @objc(focus:) func focusTab(_ c: NSScriptCommand) {     // Dia: focusing a tab brings its profile and its window forward
        if let p = profile, let w = p.window { p.selected = self; w.activeProfileObj = p; w.orderedIndex = 1 }
    }
    override var objectSpecifier: NSScriptObjectSpecifier? {
        if let s = space, let i = s.tabs.firstIndex(of: self), let cs = s.objectSpecifier {
            return NSIndexSpecifier(containerClassDescription: cd(FSpace.self), containerSpecifier: cs, key: "appleScriptTabs", index: i)
        }
        if let p = profile, let i = p.tabs.firstIndex(of: self), let cs = p.objectSpecifier {
            return NSIndexSpecifier(containerClassDescription: cd(FProfile.self), containerSpecifier: cs, key: "appleScriptTabs", index: i)
        }
        return nil
    }
}

// MARK: test driver

func build(_ spec: [[String: Any]]) {
    Model.windows = spec.map { ws in
        let w = FWindow(ws["id"] as! String); w.mode = (ws["mode"] as? String) ?? "normal"
        for ss in (ws["spaces"] as? [[String: Any]]) ?? [] {
            let s = FSpace(ss["id"] as! String, ss["title"] as! String); s.window = w
            for ts in ss["tabs"] as! [[String: String]] { let t = FTab(ts["id"]!, ts["title"]!, ts["url"]!); t.space = s; s.tabs.append(t) }
            s.selected = s.tabs.first { $0.tid == (ss["selected"] as? String) } ?? s.tabs.first
            w.spaces.append(s)
        }
        for ps in (ws["profiles"] as? [[String: Any]]) ?? [] {
            let p = FProfile(ps["name"] as! String); p.window = w
            for ts in ps["tabs"] as! [[String: String]] { let t = FTab(ts["id"]!, ts["title"]!, ts["url"]!); t.profile = p; p.tabs.append(t) }
            p.selected = p.tabs.first { $0.tid == (ps["selected"] as? String) } ?? p.tabs.first
            w.profiles.append(p)
        }
        w.activeSpaceObj = w.spaces.first { $0.sid == (ws["activeSpace"] as? String) } ?? w.spaces.first
        w.activeProfileObj = w.profiles.first { $0.label == (ws["activeProfile"] as? String) } ?? w.profiles.first
        return w
    }
}

func snapshot() -> [String: Any] {
    ["order": Model.windows.map { $0.wid },
     "windows": Model.windows.map { w in
        ["id": w.wid, "space": w.activeSpaceObj?.sid ?? "", "profile": w.activeProfileObj?.label ?? "", "tab": w.activeTab?.tid ?? "", "tabs": w.appleScriptTabs.map { $0.tid }] as [String: Any] }]
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        let args = CommandLine.arguments
        guard args.count >= 3, let data = FileManager.default.contents(atPath: args[1]),
              let cases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { print("bad args"); exit(2) }
        var results: [[String: Any]] = []
        for c in cases {
            build(c["windows"] as! [[String: Any]])
            var err: NSDictionary?
            let script = NSAppleScript(source: c["script"] as! String)
            let out = script?.executeAndReturnError(&err)
            var r: [String: Any] = ["name": c["name"] as! String, "result": out?.stringValue ?? "", "final": snapshot()]
            if let e = err { r["error"] = (e[NSAppleScript.errorMessage] as? String) ?? "\(e)" }
            results.append(r)
        }
        let json = try! JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try! json.write(to: URL(fileURLWithPath: args[2]))
        exit(0)
    }
}

let app = FApp.shared
app.setActivationPolicy(.accessory)
let delegate = Delegate()
app.delegate = delegate
app.run()
