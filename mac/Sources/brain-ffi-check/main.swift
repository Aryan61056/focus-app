import BrainTraces
import CFocusBrain
import Foundation

// brain-ffi-check <trace.json or dir>...: runs every event through the Swift brain and through the Rust brain called over its C ABI,
// and compares the effects. Needs core/brain-rs built in release mode (cargo build --release --offline).
let args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else { print("usage: brain-ffi-check <trace.json or dir>..."); exit(2) }
var files: [URL] = []
for a in args {
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: a, isDirectory: &isDir)
    if isDir.boolValue {
        files += try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: a), includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    } else { files.append(URL(fileURLWithPath: a)) }
}
var total = 0, failed = 0
for f in files {
    guard let rust = focus_brain_new() else { print("could not create a Rust brain"); exit(1) }
    defer { focus_brain_free(rust) }
    let r = try TraceRunner.crossCheck(file: f) { t, json in
        guard let out = focus_brain_step(rust, t, json) else { return nil }
        defer { focus_brain_free_string(out) }
        return String(cString: out)
    }
    total += r.events
    if r.mismatches.isEmpty { print("same \(f.lastPathComponent) (\(r.events) events)") }
    else { failed += 1; print("DIFF \(f.lastPathComponent): \(r.mismatches.count) of \(r.events) events"); for m in r.mismatches.prefix(3) { print("  " + m) } }
}
print(failed == 0 ? "Swift brain and Rust brain (over the C ABI) agree on \(total) events in \(files.count) traces" : "\(failed) of \(files.count) traces differ")
exit(failed == 0 ? 0 : 1)
