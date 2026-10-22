import Foundation
import AVFoundation
import CoreVideo
import AudioToolbox
import Darwin

struct EncoderError: Error, CustomStringConvertible {
    let description: String
    init(_ message: String) { description = message }
}

func diagnostic(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func waitUntilReady(_ input: AVAssetWriterInput, _ writer: AVAssetWriter) throws {
    let deadline = Date().addingTimeInterval(60)
    while !input.isReadyForMoreMediaData {
        guard writer.status == .writing else {
            throw EncoderError(writer.error?.localizedDescription ?? "Video writer stopped")
        }
        guard Date() < deadline else { throw EncoderError("Timed out waiting for the Apple encoder") }
        Thread.sleep(forTimeInterval: 0.002)
    }
}

func encode() throws {
    let args = CommandLine.arguments
    guard args.count == 8,
          let width = Int(args[3]), let height = Int(args[4]), let fps = Int32(args[5]),
          let quality = Int(args[6]), (16...8192).contains(width), (16...8192).contains(height),
          (1...1000).contains(fps), (0...51).contains(quality), width % 2 == 0, height % 2 == 0 else {
        throw EncoderError("Usage: streplay-encoder output H264|H265|ProRes4444 width height fps quality wav-or-empty (even dimensions, 16..8192)")
    }
    let codec: AVVideoCodecType
    switch args[2] {
    case "H264": codec = .h264
    case "H265": codec = .hevc
    case "ProRes4444": codec = .proRes4444
    default: throw EncoderError("Unsupported video format: \(args[2])")
    }
    let output = URL(fileURLWithPath: args[1])
    guard !FileManager.default.fileExists(atPath: output.path) else {
        throw EncoderError("Output already exists: \(output.path)")
    }
    let working = output.deletingLastPathComponent().appendingPathComponent(".streplay-\(UUID().uuidString).partial")
    defer { try? FileManager.default.removeItem(at: working) }
    let writer = try AVAssetWriter(outputURL: working, fileType: codec == .proRes4444 ? .mov : .mp4)
    defer { if writer.status == .writing { writer.cancelWriting() } }
    writer.shouldOptimizeForNetworkUse = true
    var settings: [String: Any] = [
        AVVideoCodecKey: codec, AVVideoWidthKey: width, AVVideoHeightKey: height,
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
        ]
    ]
    if codec != .proRes4444 {
        let bitsPerPixel = 0.06 + Double(51 - quality) / 51.0 * 0.54
        let bitrate = min(240_000_000, max(500_000, Double(width * height) * Double(fps) * bitsPerPixel))
        settings[AVVideoCompressionPropertiesKey] = [
            AVVideoAverageBitRateKey: Int(bitrate), AVVideoExpectedSourceFrameRateKey: Int(fps),
            AVVideoMaxKeyFrameIntervalKey: Int(fps) * 2
        ]
    }
    guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
        throw EncoderError("This Mac cannot encode \(args[2]) at \(width)x\(height) / \(fps) fps. Choose H.264 or PNG.")
    }
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    video.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        kCVPixelBufferIOSurfacePropertiesKey as String: [:]
    ])
    guard writer.canAdd(video) else { throw EncoderError("Cannot add video input") }
    writer.add(video)

    var reader: AVAssetReader?
    var audioOutput: AVAssetReaderTrackOutput?
    var audioInput: AVAssetWriterInput?
    if !args[7].isEmpty {
        let asset = AVURLAsset(url: URL(fileURLWithPath: args[7]))
        guard let track = asset.tracks(withMediaType: .audio).first,
              let format = track.formatDescriptions.first else { throw EncoderError("WAV has no audio track") }
        let description = format as! CMAudioFormatDescription
        guard let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              stream.mChannelsPerFrame > 0 else { throw EncoderError("Invalid WAV format") }
        reader = try AVAssetReader(asset: asset)
        audioOutput = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        guard reader!.canAdd(audioOutput!) else { throw EncoderError("Cannot read WAV samples") }
        reader!.add(audioOutput!)
        var audioSettings: [String: Any] = [AVSampleRateKey: stream.mSampleRate, AVNumberOfChannelsKey: Int(stream.mChannelsPerFrame)]
        if codec == .proRes4444 {
            audioSettings.merge([AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
                                 AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsFloatKey: false,
                                 AVLinearPCMIsNonInterleaved: false]) { _, new in new }
        } else {
            audioSettings.merge([AVFormatIDKey: kAudioFormatMPEG4AAC, AVEncoderBitRateKey: 320_000]) { _, new in new }
        }
        guard writer.canApply(outputSettings: audioSettings, forMediaType: .audio) else { throw EncoderError("Cannot encode WAV audio") }
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        guard writer.canAdd(audioInput!) else { throw EncoderError("Cannot add audio input") }
        writer.add(audioInput!)
    }
    guard writer.startWriting() else { throw EncoderError(writer.error?.localizedDescription ?? "Cannot start writer") }
    writer.startSession(atSourceTime: .zero)
    if let reader, !reader.startReading() { throw EncoderError(reader.error?.localizedDescription ?? "Cannot start WAV reader") }
    let audioDone = DispatchSemaphore(value: 0)
    let audioQueue = DispatchQueue(label: "streplay.audio")
    if let audioInput, let audioOutput {
        audioQueue.async {
            defer { audioDone.signal() }
            do {
                while let sample = audioOutput.copyNextSampleBuffer() {
                    try waitUntilReady(audioInput, writer)
                    guard audioInput.append(sample) else { throw EncoderError(writer.error?.localizedDescription ?? "Cannot append audio") }
                }
                audioInput.markAsFinished()
            } catch { diagnostic("Audio: \(error)"); writer.cancelWriting() }
        }
    } else { audioDone.signal() }
    diagnostic("READY")
    let frameBytes = width * height * 4
    var frame = [UInt8](repeating: 0, count: frameBytes)
    var count: Int64 = 0
    while true {
        let bytesRead = try frame.withUnsafeMutableBytes { destination -> Int in
            var offset = 0
            while offset < frameBytes {
                let n = Darwin.read(STDIN_FILENO, destination.baseAddress!.advanced(by: offset), frameBytes - offset)
                if n == 0 { break }
                if n < 0 {
                    if errno == EINTR { continue }
                    throw EncoderError("Cannot read frame from stdin (errno \(errno))")
                }
                offset += n
            }
            return offset
        }
        if bytesRead == 0 { break }
        guard bytesRead == frameBytes else { throw EncoderError("Truncated RGBA frame: \(bytesRead)/\(frameBytes) bytes") }
        try autoreleasepool {
            try waitUntilReady(video, writer)
            guard let pool = adaptor.pixelBufferPool else { throw EncoderError("No pixel buffer pool") }
            var pixel: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixel) == kCVReturnSuccess, let pixel else {
                throw EncoderError("Cannot allocate pixel buffer")
            }
            CVPixelBufferLockBaseAddress(pixel, [])
            let destination = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixel)
            frame.withUnsafeBufferPointer { source in
                for y in 0..<height {
                    let src = source.baseAddress!.advanced(by: (height - 1 - y) * width * 4)
                    let dst = destination.advanced(by: y * stride)
                    for x in 0..<width {
                        dst[x * 4] = src[x * 4 + 2]; dst[x * 4 + 1] = src[x * 4 + 1]
                        dst[x * 4 + 2] = src[x * 4]; dst[x * 4 + 3] = 255
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adaptor.append(pixel, withPresentationTime: CMTime(value: count, timescale: fps)) else {
                throw EncoderError(writer.error?.localizedDescription ?? "Cannot append video frame")
            }
        }
        count += 1
    }
    guard count > 0 else { writer.cancelWriting(); throw EncoderError("No video frames received") }
    video.markAsFinished()
    guard audioDone.wait(timeout: .now() + 60) == .success else {
        writer.cancelWriting(); throw EncoderError("Timed out finishing audio")
    }
    if let reader, reader.status == .failed { throw EncoderError(reader.error?.localizedDescription ?? "WAV read failed") }
    guard writer.status == .writing else { throw EncoderError(writer.error?.localizedDescription ?? "Writer failed") }
    writer.endSession(atSourceTime: CMTime(value: count, timescale: fps))
    let finished = DispatchSemaphore(value: 0)
    writer.finishWriting { finished.signal() }
    guard finished.wait(timeout: .now() + 60) == .success, writer.status == .completed else {
        throw EncoderError(writer.error?.localizedDescription ?? "Could not finalize movie")
    }
    try FileManager.default.moveItem(at: working, to: output)
    diagnostic("Saved \(count) frames")
}

do { try encode() }
catch { diagnostic("Encoder error: \(error)"); exit(1) }
