// embed: cosine distance between a task and a window description, using Apple's built-in sentence embeddings
// (NaturalLanguage framework, on-device, no download). JSON lines in -> JSON lines out.
// Request: {"id", "task", "doc"}   Response: {"id", "distance"} (0 identical, about 1 unrelated, up to 2 opposite)
import Foundation
import NaturalLanguage

guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
    print("{\"status\":\"unavailable\"}")
    exit(2)
}
print("{\"status\":\"available\",\"dimension\":\(embedding.dimension)}")
fflush(stdout)

while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = req["id"] as? String, let task = req["task"] as? String, let doc = req["doc"] as? String else {
        print("{\"id\":\"?\",\"error\":\"bad_request\"}"); fflush(stdout); continue
    }
    let d = embedding.distance(between: task, and: doc, distanceType: .cosine)
    let out: [String: Any] = ["id": id, "distance": d.isFinite ? d : 2.0]
    if let o = try? JSONSerialization.data(withJSONObject: out), let s = String(data: o, encoding: .utf8) {
        print(s); fflush(stdout)
    }
}
