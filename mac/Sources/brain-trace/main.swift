import BrainTraces
import Foundation

// brain-trace <dir or file>... : run golden traces against the Swift brain and print readable diffs.
var args = Array(CommandLine.arguments.dropFirst())
// brain-trace --dump <trace.json>: print one canonical line per event (used by tools/diff_brains.py)
if args.first == "--dump", args.count == 2 {
    for line in try TraceRunner.dump(file: URL(fileURLWithPath: args[1])) { print(line) }
    exit(0)
}
guard !args.isEmpty else { print("usage: brain-trace <core/traces dir or trace.json>..."); exit(2) }
var files: [URL] = []
for a in args {
    var isDir: ObjCBool = false
    FileManager.default.fileExists(atPath: a, isDirectory: &isDir)
    if isDir.boolValue {
        files += try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: a), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    } else { files.append(URL(fileURLWithPath: a)) }
}
var failed = 0
for f in files {
    let r = try TraceRunner.run(file: f)
    if r.failures.isEmpty { print("PASS \(r.name) (\(r.stepsChecked) events)") }
    else {
        failed += 1
        print("FAIL \(r.name): \(r.failures.count) mismatches")
        for m in r.failures.prefix(6) { print("  " + m) }
    }
}
print(failed == 0 ? "all \(files.count) traces pass" : "\(failed) of \(files.count) traces fail")
exit(failed == 0 ? 0 : 1)
