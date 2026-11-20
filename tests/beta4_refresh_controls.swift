import Foundation

struct CAFrameRateRange {
    let minimum: Float
    let maximum: Float
    let preferred: Float
    static let `default` = CAFrameRateRange(minimum: 0, maximum: 0, preferred: 0)
}
final class CADisplayLink {
    var preferredFrameRateRange = CAFrameRateRange.default
    var preferredFramesPerSecond = 0
}
enum AppDebugLogger { static func logRuntime(_ message: String) {} }

func runBeta4RefreshTests() {
    let defaults = UserDefaults.standard
    let keys = [PiPRefreshRequestTrial.background120Key, PiPRefreshRequestTrial.content120Key,
                PiPRefreshRequestTrial.content60Key, PiPRefreshRequestTrial.baselineMigrationKey,
                PiPRefreshRequestTrial.backgroundModeKey, PiPRefreshRequestTrial.releaseBaselineMigrationKey,
                "beta3.test.unrelated"]
    defer { keys.forEach { defaults.removeObject(forKey: $0) } }
    defaults.removeObject(forKey: PiPRefreshRequestTrial.releaseBaselineMigrationKey)
    for background in [false, true] {
        for content in [false, true] {
            for sixty in [false, true] {
                defaults.removeObject(forKey: PiPRefreshRequestTrial.baselineMigrationKey)
                defaults.set(background, forKey: PiPRefreshRequestTrial.background120Key)
                defaults.set(content, forKey: PiPRefreshRequestTrial.content120Key)
                defaults.set(sixty, forKey: PiPRefreshRequestTrial.content60Key)
                defaults.set("preserved", forKey: "beta3.test.unrelated")
                PiPRefreshRequestTrial.migrateDefaultBaselineIfNeeded()
                precondition(!PiPRefreshRequestTrial.background120)
                precondition(!PiPRefreshRequestTrial.content120)
                precondition(PiPRefreshRequestTrial.baselineContentFPS == 30)
                precondition(defaults.string(forKey: "beta3.test.unrelated") == "preserved")
                let link = CADisplayLink()
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
                PiPRefreshRequestTrial.configureContent(link, maximumFPS: 120)
                precondition(link.preferredFramesPerSecond == 30)
                precondition(link.preferredFrameRateRange.maximum == 0)
                precondition(!PiPRefreshRequestTrial.requestsBackground120(eligible: true))
                PiPRefreshRequestTrial.migrateDefaultBaselineIfNeeded()
                precondition(PiPRefreshRequestTrial.baselineContentFPS == 30)
            }
        }
    }
    precondition(String(format: "%.0f MB", 42.6) == "43 MB")
    for mode in PiPRefreshRequestTrial.BackgroundMode.allCases {
        for fps in [30, 60] {
            for content120 in [false, true] {
                PiPRefreshRequestTrial.select(background: mode, contentFPS: fps, content120: content120)
                precondition(PiPRefreshRequestTrial.backgroundMode == mode)
                precondition(PiPRefreshRequestTrial.baselineContentFPS == fps)
                precondition(PiPRefreshRequestTrial.requestsBackground120(eligible: true) == (mode == .explicit120))
                precondition(!PiPRefreshRequestTrial.requestsBackground120(eligible: false))
                for eligible in [false, true] {
                    for background in [false, true] {
                        for visibility in [false, true] {
                            precondition(PiPRefreshRequestTrial.shouldPauseBackgroundDriver(
                                eligible: eligible, isBackground: background, visibilityPause: visibility
                            ) == (eligible && background && visibility && mode == .visibilityPaused))
                        }
                    }
                }
                for maximum in [60, 120] {
                    let link = CADisplayLink()
                    PiPRefreshRequestTrial.configureContent(link, maximumFPS: maximum)
                    if content120 {
                        precondition(link.preferredFrameRateRange.preferred == Float(min(120, maximum)))
                    } else {
                        precondition(link.preferredFramesPerSecond == min(fps, maximum))
                        precondition(link.preferredFrameRateRange.maximum == 0)
                    }
                }
                PiPRefreshRequestTrial.migrateDefaultBaselineIfNeeded()
                precondition(PiPRefreshRequestTrial.backgroundMode == mode, "Existing beta4 selection must survive startup")
            }
        }
    }
    PiPRefreshRequestTrial.select(background: .systemDefault, contentFPS: 60, content120: true)
    let restoredLink = CADisplayLink()
    PiPRefreshRequestTrial.configureContent(restoredLink, maximumFPS: 120)
    PiPRefreshRequestTrial.select(background: .systemDefault, contentFPS: 60)
    PiPRefreshRequestTrial.configureContent(restoredLink, maximumFPS: 120)
    precondition(restoredLink.preferredFrameRateRange.maximum == 0 && restoredLink.preferredFramesPerSecond == 60)
    PiPRefreshRequestTrial.select(background: .explicit120, contentFPS: 60, content120: true)
    PiPRefreshRequestTrial.migrateDefaultBaselineIfNeeded(isReleaseBuild: true)
    precondition(PiPRefreshRequestTrial.backgroundMode == .visibilityPaused && !PiPRefreshRequestTrial.background120)
    precondition(!PiPRefreshRequestTrial.content120 && PiPRefreshRequestTrial.baselineContentFPS == 30)
    precondition(defaults.string(forKey: "beta3.test.unrelated") == "preserved")
    precondition(defaults.bool(forKey: PiPRefreshRequestTrial.releaseBaselineMigrationKey))
    PiPRefreshRequestTrial.select(background: .systemDefault, contentFPS: 30)
    PiPRefreshRequestTrial.migrateDefaultBaselineIfNeeded(isReleaseBuild: true)
    precondition(PiPRefreshRequestTrial.backgroundMode == .systemDefault, "Release migration must only run once")
    print("PASS: beta4 defaults and all12 policy combinations; visibility-only pause, no foreground/other-route pause;30/60 and hardware-capped120; override restoration; selections survive startup")
}
