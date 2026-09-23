import Metal
import AppKit
import CoreMedia

@MainActor
final class CheckCaptureEngine: CaptureEngine {
    var regions: [(displayID: CGDirectDisplayID, rect: CGRect)] = []
    var pauseNextStart = false
    var pendingStart: CheckedContinuation<Void, Never>?

    override func checkPermissions() async -> Bool { true }

    override func startCapture(displayID: CGDirectDisplayID, rect: CGRect) async {
        if pauseNextStart {
            pauseNextStart = false
            await withCheckedContinuation { pendingStart = $0 }
        }
        regions.append((displayID, rect))
        isCapturing = true
    }

    override func stopCapture() async { isCapturing = false }
}

@main
enum ScopeRegressionCheck {
    @MainActor
    static func main() throws {
        // Independent BT.709 expectations for 75% R, MG, B, CY, G, YL.
        let expected: [SIMD2<Float>] = [
            SIMD2(-0.171858, -0.75), SIMD2(0.578142, -0.681229),
            SIMD2(0.75, 0.068771), SIMD2(0.171858, 0.75),
            SIMD2(-0.578142, 0.681229), SIMD2(-0.75, -0.068771),
        ]
        for gray: Float in [0, 0.18, 0.5, 1] {
            let point = ScopeConstants.position(for: SIMD3(repeating: gray))
            assert(abs(point.x) < 0.000001)
            assert(abs(point.y) < 0.000001)
        }
        for (actual, reference) in zip(ScopeConstants.defaultTargets, expected) {
            assert(abs(actual.x - reference.x) < 0.000002)
            assert(abs(actual.y - reference.y) < 0.000002)
        }

        _ = NSApplication.shared
        let capture = CheckCaptureEngine()
        let state = AppState(captureEngine: capture)
        let renderer = state.renderer
        let device = (renderer.device)!
        let queue = (renderer.commandQueue)!
        let pipeline = (renderer.vectorScopeState)!
        let config = (renderer.configBuffer)!
        let inputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float, width: 1, height: 1, mipmapped: false)
        inputDescriptor.storageMode = .shared
        inputDescriptor.usage = .shaderRead
        let input = (device.makeTexture(descriptor: inputDescriptor))!
        let size = 512
        let outputDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: size, height: size, mipmapped: false)
        outputDescriptor.storageMode = .shared
        outputDescriptor.usage = [.shaderRead, .shaderWrite]
        let output = (device.makeTexture(descriptor: outputDescriptor))!
        let blank = [UInt8](repeating: 0, count: size * size * 4)

        // Run the real Metal kernel: catches matrix binding, layout, and Y-flip regressions.
        for (rgb, reference) in zip(ScopeConstants.targetColors, expected) {
            var color = SIMD4<Float>(rgb * 0.75, 1)
            input.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                          withBytes: &color, bytesPerRow: MemoryLayout<SIMD4<Float>>.stride)
            blank.withUnsafeBytes {
                output.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
                               withBytes: $0.baseAddress!, bytesPerRow: size * 4)
            }
            let command = (queue.makeCommandBuffer())!
            let encoder = (command.makeComputeCommandEncoder())!
            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(input, index: 0)
            encoder.setTexture(output, index: 1)
            encoder.setBuffer(config, offset: 0, index: 0)
            encoder.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            encoder.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            assert(command.status == .completed)

            var pixels = blank
            pixels.withUnsafeMutableBytes {
                output.getBytes($0.baseAddress!, bytesPerRow: size * 4,
                                from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
            }
            let hits = (0..<(size * size)).filter {
                let index = $0 * 4
                return pixels[index] != 0 || pixels[index + 1] != 0 || pixels[index + 2] != 0
            }
            assert(hits.count == 1)
            let hit = (hits.first)!
            let x = Int(Float(size) * (0.5 + reference.x * 0.45))
            let y = Int(Float(size) * (0.5 + reference.y * 0.45))
            assert(abs(hit % size - x) <= 1)
            assert(abs(hit / size - y) <= 1)
        }

        func waitUntil(_ message: String, _ condition: () -> Bool) {
            let deadline = Date(timeIntervalSinceNow: 2)
            while !condition() && Date() < deadline {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
            }
            assert(condition(), message)
        }
        func selectionIsVisible() -> Bool {
            NSApp.windows.contains { $0.isVisible && $0.level == .screenSaver }
        }

        // A fresh launch selects a region; a stopped capture keeps the chosen region.
        state.reopen()
        assert(selectionIsVisible() && !state.isScopeVisible)
        assert(!capture.isCapturing && capture.regions.isEmpty)
        state.cancelSelection()
        let region = CGRect(x: 40, y: 80, width: 120, height: 90)
        state.selectRegion(displayID: 17, rect: region)
        defer { state.hideScopes() }
        waitUntil("Selecting a region did not start capture") { capture.isCapturing }
        let window = (state.scopeWindowController?.window)!
        window.performClose(nil)
        assert(!state.isScopeVisible)
        waitUntil("Close button left screen capture running") { !capture.isCapturing }
        state.reopen()
        assert(state.scopeWindowController?.window === window)
        assert(state.isScopeVisible && !selectionIsVisible())
        waitUntil("Reopening did not resume capture") { capture.isCapturing }
        assert(capture.regions.last!.displayID == 17 && capture.regions.last!.rect == region)

        state.toggleScopes()
        waitUntil("Menu hide left screen capture running") { !capture.isCapturing }
        state.toggleScopes()
        waitUntil("Menu show did not resume capture") { capture.isCapturing }
        assert(!selectionIsVisible() && capture.regions.last!.rect == region)

        // Closing during an asynchronous start must still stop that capture when it returns.
        state.hideScopes()
        waitUntil("Capture did not stop") { !capture.isCapturing }
        capture.pauseNextStart = true
        let startsBeforeClose = capture.regions.count
        state.reopen()
        waitUntil("Delayed capture did not start") { capture.pendingStart != nil }
        state.hideScopes()
        capture.pendingStart!.resume()
        capture.pendingStart = nil
        waitUntil("A late start left the hidden window capturing") {
            capture.regions.count > startsBeforeClose && !capture.isCapturing
        }
        assert(!state.isScopeVisible)

        let newRegionRect = CGRect(x: 400, y: 100, width: 80, height: 60)
        state.selectRegion(displayID: 23, rect: newRegionRect)
        waitUntil("Reselection did not start capture") { capture.isCapturing }
        let startsBeforeReopen = capture.regions.count
        state.hideScopes()
        state.reopen()
        waitUntil("Reopening lost the newly selected region") {
            capture.isCapturing && capture.regions.count > startsBeforeReopen
                && capture.regions.last!.displayID == 23
                && capture.regions.last!.rect == newRegionRect
        }
        assert(!selectionIsVisible())

        // A denied permission must offer a way back to selection without changing system permissions.
        for response in [NSApplication.ModalResponse.alertSecondButtonReturn, .alertThirdButtonReturn] {
            var alertWasPresented = false
            RunLoop.main.perform(inModes: [.modalPanel]) {
                assert(NSApp.modalWindow != nil, "Permission alert was not presented")
                alertWasPresented = true
                NSApp.stopModal(withCode: response)
            }
            state.showScreenRecordingPermissionAlert()
            assert(alertWasPresented)
            let selection = NSApp.windows.first { $0.isVisible && $0.level == .screenSaver }
            assert((selection != nil) == (response == .alertSecondButtonReturn),
                   "Permission alert did not honor reselect or cancel")
            state.cancelSelection()
            assert(selection?.isVisible != true, "Selection could not be cancelled")
        }

        // Static captures emit metadata-only frames. They must not replace the last image.
        func makeFrame(red: UInt8, green: UInt8, blue: UInt8) -> CMSampleBuffer {
            var pixelBuffer: CVPixelBuffer?
            let pixelStatus = CVPixelBufferCreate(
                kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA,
                [kCVPixelBufferMetalCompatibilityKey: true,
                 kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixelBuffer)
            assert(pixelStatus == kCVReturnSuccess)
            let pixel = pixelBuffer!
            CVPixelBufferLockBaseAddress(pixel, [])
            let bytes = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
            bytes[0] = blue; bytes[1] = green; bytes[2] = red; bytes[3] = 255
            CVPixelBufferUnlockBaseAddress(pixel, [])
            var format: CMVideoFormatDescription?
            let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescriptionOut: &format)
            assert(formatStatus == noErr)
            var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero,
                                            decodeTimeStamp: .invalid)
            var result: CMSampleBuffer?
            let frameStatus = CMSampleBufferCreateReadyWithImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescription: format!,
                sampleTiming: &timing, sampleBufferOut: &result)
            assert(frameStatus == noErr)
            return result!
        }
        let frame = makeFrame(red: 192, green: 64, blue: 32)
        var idle: CMSampleBuffer?
        let idleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault, dataBuffer: nil, formatDescription: frame.formatDescription,
            sampleCount: 0, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &idle)
        assert(idleStatus == noErr && CMSampleBufferGetImageBuffer(idle!) == nil)
        state.captureEngine.frameSubject.send(frame)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        state.captureEngine.frameSubject.send(idle!)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        assert(renderer.currentSampleBuffer === frame, "Idle frame replaced the cached image")

        // Read the real output at a parade divider; switching must work without a new frame.
        func outputValue(y: Int? = nil, channel: Int = 0) -> UInt8 {
            let texture = renderer.outputTexture!
            let readback = device.makeBuffer(length: 256, options: .storageModeShared)!
            let command = queue.makeCommandBuffer()!
            let blit = command.makeBlitCommandEncoder()!
            blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                      sourceOrigin: MTLOrigin(x: 0, y: y ?? texture.height / 3, z: 0),
                      sourceSize: MTLSize(width: 1, height: 1, depth: 1),
                      to: readback, destinationOffset: 0, destinationBytesPerRow: 256,
                      destinationBytesPerImage: 256)
            blit.endEncoding()
            command.commit()
            command.waitUntilCompleted()
            assert(command.status == .completed)
            return readback.contents().load(fromByteOffset: channel, as: UInt8.self)
        }
        renderer.displayMode = .vectorScope
        assert(outputValue() < 10)
        renderer.displayMode = .rgbParade
        assert(outputValue() > 100, "Static frame did not redraw as RGB parade")
        renderer.displayMode = .vectorScope
        assert(outputValue() < 10, "Static frame did not redraw as vectorscope")

        // Cached frames must redraw after reopening, and later frames must keep updating.
        renderer.displayMode = .rgbParade
        state.hideScopes()
        let newRegion = makeFrame(red: 32, green: 64, blue: 192)
        state.captureEngine.frameSubject.send(newRegion)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        assert(renderer.currentSampleBuffer === newRegion, "New region did not reach the renderer")
        state.showScopes()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let redY = Int((1 - Float(32) / 255) * Float(renderer.outputTexture!.height / 3 - 1))
        assert(outputValue(y: redY, channel: 2) > 100, "Reopened scopes still show the old region")

        let updatedRegion = makeFrame(red: 128, green: 64, blue: 192)
        state.captureEngine.frameSubject.send(updatedRegion)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let updatedY = Int((1 - Float(128) / 255) * Float(renderer.outputTexture!.height / 3 - 1))
        assert(outputValue(y: updatedY, channel: 2) > 100, "Reopened scopes stopped updating")
        print("PASS: color bars, capture visibility and region retention, permission recovery, idle frames, mode switching, and region refresh")
    }
}
