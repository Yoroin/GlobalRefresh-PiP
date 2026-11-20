import Foundation
import CoreGraphics

@main
enum HomeViewportLayoutTests {
    static func main() {
        for size in [CGSize(width: 390, height: 714), CGSize(width: 393, height: 710), CGSize(width: 393, height: 748)] {
            let layout = PiPHomeViewportLayout(size: size)
            precondition(layout.usesCompactControls)
            precondition(layout.controlsBottomPadding(base: 40) == 36)
        }

        for size in [CGSize(width: 390, height: 620), CGSize(width: 382, height: 678), CGSize(width: 466, height: 676)] {
            let layout = PiPHomeViewportLayout(size: size)
            precondition(layout.usesCompactControls)
            precondition(layout.controlsBottomPadding(base: 12) == 18)
        }

        for size in [CGSize(width: 402, height: 728), CGSize(width: 402, height: 755), CGSize(width: 430, height: 780)] {
            let layout = PiPHomeViewportLayout(size: size)
            precondition(!layout.usesCompactControls)
            precondition(layout.controlsBottomPadding(base: 40) == 24)
        }

        for size in [CGSize(width: 834, height: 640), CGSize(width: 865, height: 669), CGSize(width: 720, height: 834), .zero] {
            let layout = PiPHomeViewportLayout(size: size)
            precondition(!layout.usesCompactControls)
            precondition(layout.controlsBottomPadding(base: 40) == 40)
        }
        print("PASS: compact 13/15 Pro and Duo cover, reduced padding on taller phones, unchanged Duo inner and wide layouts")
    }
}
