import Combine
import CoreMedia
import Foundation
import Metal
import MetalKit

@MainActor
class ScopeRenderer: NSObject, MTKViewDelegate, ObservableObject {
    var device: MTLDevice?
    var commandQueue: MTLCommandQueue?

    enum DisplayMode {
        case vectorScope
        case rgbParade
        case split  // Left/Right ? For now let's just do toggle or both.
    }

    @Published var displayMode: DisplayMode = .vectorScope {
        didSet {
            // Trigger redraw immediately when mode changes
            mtkView?.setNeedsDisplay(mtkView?.bounds ?? .zero)
        }
    }

    // Pipelines
    var vectorScopeState: MTLComputePipelineState?
    var rgbParadeState: MTLComputePipelineState?
    var clearVectorState: MTLComputePipelineState?
    var clearParadeState: MTLComputePipelineState?

    // Textures
    var outputTexture: MTLTexture?  // The visual result of the scope

    // View Reference for Redraw Trigger
    weak var mtkView: MTKView?

    // Buffers
    var configBuffer: MTLBuffer?

    private var cancellables = Set<AnyCancellable>()
    var currentSampleBuffer: CMSampleBuffer?

    // Texture Cache
    var textureCache: CVMetalTextureCache?

    override init() {
        super.init()
        self.device = MTLCreateSystemDefaultDevice()
        self.commandQueue = device?.makeCommandQueue()

        if let device = device {
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        }

        buildPipelines()
        createConfigBuffer()
    }

    func createConfigBuffer() {
        // Must run on device
        guard let device = device else { return }
        var config = ScopeConstants.makeMetalConfig()
        configBuffer = device.makeBuffer(
            bytes: &config, length: MemoryLayout<ScopeConstants.MetalConfig>.size,
            options: .cpuCacheModeWriteCombined)
    }

    func buildPipelines() {
        guard let device = device else { return }

        do {
            // Debugging Bundle
            print("Bundle.module path: \(Bundle.module.bundlePath)")
            if let resourceURL = Bundle.module.resourceURL {
                print("Resource URL: \(resourceURL.path)")
                // List files
                do {
                    let files = try FileManager.default.contentsOfDirectory(
                        atPath: resourceURL.path)
                    print("Files in resource bundle: \(files)")
                } catch { print(error) }
            }

            let library: MTLLibrary
            do {
                if let libURL = Bundle.module.url(forResource: "default", withExtension: "metallib")
                {
                    print("Found default.metallib at \(libURL.path)")
                    library = try device.makeLibrary(URL: libURL)
                } else if let sourceURL = Bundle.module.url(
                    forResource: "ScopeShaders", withExtension: "metal")
                {
                    print(
                        "Found ScopeShaders.metal source at \(sourceURL.path), compiling at runtime..."
                    )
                    let source = try String(contentsOf: sourceURL, encoding: .utf8)
                    library = try device.makeLibrary(source: source, options: nil)
                } else {
                    print("Could not find default.metallib OR ScopeShaders.metal in Bundle.module")
                    library = try device.makeDefaultLibrary(bundle: Bundle.module)
                }
            } catch {
                print("Error loading from Bundle.module: \(error)")
                // Fallback attempts...
                if let defaultLib = device.makeDefaultLibrary() {
                    library = defaultLib
                } else {
                    throw error
                }
            }

            print("Compiled Library Function Names: \(library.functionNames)")

            guard let vsFunc = library.makeFunction(name: "vectorscope_accumulate"),
                let paradeFunc = library.makeFunction(name: "rgb_parade_accumulate"),
                let clearVecFunc = library.makeFunction(name: "clear_vector"),
                let clearParadeFunc = library.makeFunction(name: "clear_parade")
            else {
                print("Error: Could not find shader functions")
                return
            }

            vectorScopeState = try device.makeComputePipelineState(function: vsFunc)
            rgbParadeState = try device.makeComputePipelineState(function: paradeFunc)
            clearVectorState = try device.makeComputePipelineState(function: clearVecFunc)
            clearParadeState = try device.makeComputePipelineState(function: clearParadeFunc)

        } catch {
            print("Error building pipelines: \(error)")
        }
    }

    func setInput(publisher: PassthroughSubject<CMSampleBuffer, Never>) {
        publisher
            .receive(on: DispatchQueue.main)  // MTKView draw needs main thread usually, or we can trigger from bg
            .sink { [weak self] buffer in
                self?.currentSampleBuffer = buffer
                // Efficiently redraw only when new frame arrives
                self?.mtkView?.setNeedsDisplay(self?.mtkView?.bounds ?? .zero)
            }
            .store(in: &cancellables)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Recreate output texture if needed
        createOutputTexture(size: size)
    }

    func draw(in view: MTKView) {
        // print("ScopeRenderer: draw called")
        guard let sBuffer = currentSampleBuffer else {
            // Sample buffer might not be ready yet, this is normal at startup
            return
        }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sBuffer),
            let commandBuffer = commandQueue?.makeCommandBuffer(),
            let drawable = view.currentDrawable,
            let vectorState = vectorScopeState,
            let paradeState = rgbParadeState,
            let clearVecState = clearVectorState,
            let clearParadeState = clearParadeState
        else {
            // print("ScopeRenderer: Missing metal components or buffers")
            return
        }

        // 1. Create Input Texture from CVPixelBuffer
        guard
            let inputTexture = makeTextureFromCVPixelBuffer(
                pixelBuffer: imageBuffer, pixelFormat: .bgra8Unorm)
        else { return }

        // 2. Ensure Output Texture exists
        let drawSize = view.drawableSize
        if outputTexture == nil || outputTexture!.width != Int(drawSize.width)
            || outputTexture!.height != Int(drawSize.height)
        {
            createOutputTexture(size: drawSize)
        }
        guard let outTex = outputTexture else { return }

        // 3. Clear Output (with Graticules)
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (outTex.width + 15) / 16, height: (outTex.height + 15) / 16, depth: 1)

        let clearEncoder = commandBuffer.makeComputeCommandEncoder()

        // 3. Clear Output (with Graticules)
        // ...

        switch displayMode {
        case .vectorScope:
            clearEncoder?.setComputePipelineState(clearVecState)
            if let configBuf = configBuffer {
                clearEncoder?.setBuffer(configBuf, offset: 0, index: 0)
            }
        case .rgbParade:
            clearEncoder?.setComputePipelineState(clearParadeState)
        case .split:
            clearEncoder?.setComputePipelineState(clearVecState)  // fallback
            if let configBuf = configBuffer {
                clearEncoder?.setBuffer(configBuf, offset: 0, index: 0)
            }
        }

        clearEncoder?.setTexture(outTex, index: 0)
        clearEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        clearEncoder?.endEncoding()

        // 4. Dispatch Scope Kernel
        let scopeEncoder = commandBuffer.makeComputeCommandEncoder()

        // Input dimensions determine dispatch size for scatter gather
        let inWidth = inputTexture.width
        let inHeight = inputTexture.height
        let inGroups = MTLSize(width: (inWidth + 15) / 16, height: (inHeight + 15) / 16, depth: 1)

        scopeEncoder?.setTexture(inputTexture, index: 0)
        scopeEncoder?.setTexture(outTex, index: 1)

        switch displayMode {
        case .vectorScope:
            scopeEncoder?.setComputePipelineState(vectorState)
            scopeEncoder?.dispatchThreadgroups(inGroups, threadsPerThreadgroup: threadGroupSize)
        case .rgbParade:
            scopeEncoder?.setComputePipelineState(paradeState)
            scopeEncoder?.dispatchThreadgroups(inGroups, threadsPerThreadgroup: threadGroupSize)
        case .split:
            // TODO: Implement split screen shader adjustment
            scopeEncoder?.setComputePipelineState(vectorState)
            scopeEncoder?.dispatchThreadgroups(inGroups, threadsPerThreadgroup: threadGroupSize)
        }

        scopeEncoder?.endEncoding()

        // 5. Blit
        let blitEncoder = commandBuffer.makeBlitCommandEncoder()
        blitEncoder?.copy(from: outTex, to: drawable.texture)
        blitEncoder?.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // Helpers

    func createOutputTexture(size: CGSize) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: Int(size.width), height: Int(size.height),
            mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        // Allow creating view
        outputTexture = device?.makeTexture(descriptor: descriptor)
    }

    func makeTextureFromCVPixelBuffer(pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat)
        -> MTLTexture?
    {
        guard let textureCache = textureCache else { return nil }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil, pixelFormat, width, height, 0,
            &cvTextureOut)

        guard let cvTexture = cvTextureOut, let inputTexture = CVMetalTextureGetTexture(cvTexture)
        else {
            return nil
        }
        return inputTexture
    }
}
