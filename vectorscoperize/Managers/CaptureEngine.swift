import Foundation
@preconcurrency import ScreenCaptureKit
import Combine
import CoreMedia
import OSLog

@MainActor
class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate, ObservableObject {
    
    private let logger = Logger(subsystem: "com.zhaoluchen.vectorscoperize", category: "CaptureEngine")
    
    @Published var isCapturing = false
    @Published var availableDisplays: [SCDisplay] = []
    
    // The sink for the frames, to be consumed by ScopeRenderer
    let frameSubject = PassthroughSubject<CMSampleBuffer, Never>()
    
    private var stream: SCStream?
    private var displayID: CGDirectDisplayID?
    private var selectionRect: CGRect = .zero // capture rect
    
    override init() {
        super.init()
    }
    
    func checkPermissions() async -> Bool {
        do {
            // Just trying to fetch content is enough to trigger permission check or fail
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            logger.error("Failed to check permissions: \(error.localizedDescription)")
            return false
        }
    }
    
    func refreshContent() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            self.availableDisplays = content.displays
        } catch {
            logger.error("Failed to get shareable content: \(error.localizedDescription)")
        }
    }
    
    func startCapture(display: SCDisplay, rect: CGRect) async {
        // Stop existing
        if let stream = stream {
            try? await stream.stopCapture()
        }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        // We probably want to crop to the rect. 
        // SCContentFilter allows setting a 'contentRect' if using initWithDisplay:including... 
        // But the 'rect' might need to be verified against display bounds.
        
        // Configuration
        let config = SCStreamConfiguration()
        // Improve performance: We don't need retina resolution for scopes usually, 
        // but let's capture at 1x scale of the rect size.
        config.width = Int(rect.width)
        config.height = Int(rect.height)
        config.sourceRect = rect
        config.showsCursor = false
        config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_32BGRA // Metal friendly
        config.colorSpaceName = CGColorSpace.sRGB
        config.capturesAudio = false
        
        do {
            stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.vectorscoperize.capture"))
            try await stream?.startCapture()
            self.isCapturing = true
            logger.info("Capture started for rect: \(rect.debugDescription)")
        } catch {
            logger.error("Failed to start capture: \(error.localizedDescription)")
        }
    }
    
    func stopCapture() async {
        do {
            try await stream?.stopCapture()
            self.isCapturing = false
            stream = nil
        } catch {
            logger.error("Failed to stop capture: \(error.localizedDescription)")
        }
    }
    
    func updateCaptureRect(_ rect: CGRect) async {
        guard let stream = stream else { return }
        
        let config = SCStreamConfiguration()
        config.width = Int(rect.width)
        config.height = Int(rect.height)
        config.sourceRect = rect
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        
        do {
            try await stream.updateConfiguration(config)
        } catch {
            logger.error("Failed to update config: \(error.localizedDescription)")
        }
    }
    
    // MARK: - SCStreamOutput
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        Task { @MainActor in
            // print("CaptureEngine: frame received") // Comment out to avoid spam, but useful for initial debug
            self.frameSubject.send(sampleBuffer)
        }
    }
    
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            self.logger.error("Stream stopped with error: \(error.localizedDescription)")
            self.isCapturing = false
        }
    }
}
