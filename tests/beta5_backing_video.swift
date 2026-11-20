import Foundation
import AVFoundation

@main
struct BackingVideoTests {
    static func main() throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1])
        let fm = FileManager.default
        for long in [false, true] {
            let target = dir.appendingPathComponent(long ? "long.mov" : "short.mov")
            try Data([0, 1, 2, 3]).write(to: target)
            func generate(_ cancelled: @escaping () -> Bool) throws {
                try PlaceholderVideoFactory.prepare(at: target, size: CGSize(width: 192, height: 32),
                                                    text: "", longVideo: long, cancelled: cancelled)
            }
            try generate { false }
            let asset = AVURLAsset(url: target)
            let tracks = asset.tracks(withMediaType: .video)
            precondition(tracks.count == 1 && abs(asset.duration.seconds - (long ? 15 : 0.1)) < 0.005)
            let before = try target.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let bytes = try Data(contentsOf: target)
            try generate { false }
            let after = try target.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            precondition(before == after, "A completed cache hit must not re-encode")
            do { try generate { true }; preconditionFailure("Canceled request was accepted") } catch {}
            let preserved = try Data(contentsOf: target)
            precondition(bytes == preserved && bytes.count > 4)
        }
        let cancelled = dir.appendingPathComponent("cancelled.mov")
        var calls = 0
        let lock = NSLock()
        do {
            try PlaceholderVideoFactory.prepare(at: cancelled, size: CGSize(width: 192, height: 32),
                                                text: "", longVideo: true) {
                lock.lock(); defer { lock.unlock() }
                calls += 1
                return calls > 8
            }
            preconditionFailure("Canceled long encode was published")
        } catch {}
        let entries = try fm.contentsOfDirectory(atPath: dir.path).sorted()
        precondition(entries == ["long.mov", "short.mov"], "Unexpected partial files: \(entries)")
        print("PASS: real H.264 1/450-frame files, durations, invalid-cache replacement, cache hit and mid-encode cancellation")
    }
}
