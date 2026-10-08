for baseY: CGFloat in [372, 410, 452] {
    for topY: CGFloat in [250, 340, 440] {
        for referenceHeight: CGFloat in [80, 120, 180] {
            let chinese = LayoutProbe(
                layout: Metrics(versionFAQRowCenterY: baseY),
                versionDescriptionFrame: CGRect(x: 0, y: topY, width: 300, height: referenceHeight),
                versionDescriptionReferenceHeight: referenceHeight
            )
            assert(chinese.diagnosticsDescriptionExpansion == 0)
            assert(chinese.diagnosticsFAQRowCenterY == chinese.fixedFAQRowCenterY)
            for extraHeight: CGFloat in [20, 60, 120] {
                let english = LayoutProbe(
                    layout: chinese.layout,
                    versionDescriptionFrame: CGRect(x: 0, y: topY, width: 300, height: referenceHeight + extraHeight),
                    versionDescriptionReferenceHeight: referenceHeight
                )
                assert(english.diagnosticsFAQRowCenterY == chinese.diagnosticsFAQRowCenterY)
                assert(english.fixedFAQRowCenterY >= english.versionDescriptionFrame.maxY + 35)
                assert(english.diagnosticsDescriptionExpansion == extraHeight)
                let originalCopyY = chinese.versionDescriptionFrame.maxY + 120
                let translatedCopyY = english.versionDescriptionFrame.maxY + 120
                    - english.diagnosticsDescriptionExpansion
                assert(originalCopyY == translatedCopyY)
            }
        }
    }
}
let initial = LayoutProbe(
    layout: Metrics(versionFAQRowCenterY: 452),
    versionDescriptionFrame: .zero,
    versionDescriptionReferenceHeight: 0
)
assert(initial.diagnosticsFAQRowCenterY == 452)
assert(initial.diagnosticsDescriptionExpansion == 0)
print("PASS: diagnostics stay at the Chinese layout position; FAQ still clears the translated description")
