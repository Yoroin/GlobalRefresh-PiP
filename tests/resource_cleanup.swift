import Foundation
import Darwin

enum ResourceSnapshotHarness {
    struct ThreadUsageSnapshot {
        let totalCPUUsage: Double
        let maxThreadCPUUsage: Double
        let threadCount: Int
        let runningThreadCount: Int
        let waitingThreadCount: Int
        let stoppedThreadCount: Int
        let uninterruptibleThreadCount: Int
        let haltedThreadCount: Int
    }

    static func runTests() {
        let ownThread = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, ownThread) }
        func references() -> mach_port_urefs_t {
            var count: mach_port_urefs_t = 0
            precondition(mach_port_get_refs(mach_task_self_, ownThread, MACH_PORT_RIGHT_SEND, &count) == KERN_SUCCESS)
            return count
        }
        let before = references()
        for _ in 0..<256 {
            let snapshot = threadUsageSnapshot()
            precondition(snapshot.threadCount > 0)
            let count = threadUsageSnapshot(countOnly: true)
            precondition(count.threadCount > 0 && count.totalCPUUsage == 0 && count.maxThreadCPUUsage == 0)
        }
        let after = references()
        precondition(before == after, "Thread rights leaked: \(before) -> \(after)")
        print("PASS: 256 full + 256 count-only snapshots leave send-right refs unchanged (\(before) -> \(after))")
    }
