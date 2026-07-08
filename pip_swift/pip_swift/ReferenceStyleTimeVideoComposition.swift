//
//  ReferenceStyleTimeVideoComposition.swift
//  pip_swift
//

import AVFoundation
import CoreVideo
import Foundation
import UIKit

final class ReferenceStyleTimeVideoComposition: NSObject, AVVideoCompositing {
    private let renderQueue = DispatchQueue(label: "pip.referenceStyleTimeVideoComposition")
    private var renderContext: AVVideoCompositionRenderContext?

    let sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [
            kCVPixelFormatType_32BGRA,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
    ]

    let requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]

    var supportsWideColorSourceFrames: Bool { false }
    var supportsHDRSourceFrames: Bool { false }
    var supportsSourceTaggedBuffers: Bool { false }
    var canConformColorOfSourceFrames: Bool { false }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderQueue.sync {
            renderContext = newRenderContext
        }
    }

    func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            guard let self else {
                asyncVideoCompositionRequest.finishCancelledRequest()
                return
            }

            let renderContext = self.renderContext ?? asyncVideoCompositionRequest.renderContext
            guard let outputBuffer = renderContext.newPixelBuffer() else {
                asyncVideoCompositionRequest.finish(with: NSError(domain: "ReferenceStyleTimeVideoComposition", code: 1))
                return
            }

            self.drawReferenceFrame(
                into: outputBuffer,
                renderSize: renderContext.size,
                compositionTime: asyncVideoCompositionRequest.compositionTime
            )
            asyncVideoCompositionRequest.finish(withComposedVideoFrame: outputBuffer)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        renderQueue.async { }
    }

    private func drawReferenceFrame(into pixelBuffer: CVPixelBuffer, renderSize: CGSize, compositionTime: CMTime) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return
        }

        let bounds = CGRect(x: 0, y: 0, width: max(renderSize.width, 1), height: max(renderSize.height, 1))
        context.setFillColor(UIColor.white.cgColor)
        context.fill(bounds)
        context.saveGState()
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)

        let frameIndex = Int64(CMTimeGetSeconds(compositionTime) * 120)
        let whiteLevel: CGFloat = frameIndex.isMultiple(of: 2) ? 0.992 : 0.984
        context.setFillColor(UIColor(white: whiteLevel, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: min(bounds.width, 2), height: min(bounds.height, 2)))
        UIGraphicsPopContext()
        context.restoreGState()
    }
}

final class ReferenceStyleTimeVideoCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = false
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    let requiredSourceSampleDataTrackIDs: [NSValue]? = nil

    init(timeRange: CMTimeRange, sourceTrackID: CMPersistentTrackID) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: sourceTrackID)]
        super.init()
    }
}
