import Foundation
import AVFoundation
import CoreVideo

let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
guard let track = asset.tracks(withMediaType: .video).first else { fatalError("No video track") }
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(output)
guard reader.startReading() else { fatalError("Cannot decode") }
var count = 0
var top: [Int] = [], bottom: [Int] = []
var times: [Double] = []
while let sample = output.copyNextSampleBuffer() {
    count += 1
    times.append(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample)))
    if count == 1, let pixel = CMSampleBufferGetImageBuffer(sample) {
        CVPixelBufferLockBaseAddress(pixel, .readOnly)
        let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
        let w = CVPixelBufferGetWidth(pixel), h = CVPixelBufferGetHeight(pixel), stride = CVPixelBufferGetBytesPerRow(pixel)
        let t = base.advanced(by: (h / 4) * stride + (w / 2) * 4)
        let b = base.advanced(by: (h * 3 / 4) * stride + (w / 2) * 4)
        top = [Int(t[2]), Int(t[1]), Int(t[0])]
        bottom = [Int(b[2]), Int(b[1]), Int(b[0])]
        CVPixelBufferUnlockBaseAddress(pixel, .readOnly)
    }
}
guard reader.status == .completed else { fatalError("Decode failed: \(String(describing: reader.error))") }
var audioSamples = 0
if let audioTrack = asset.tracks(withMediaType: .audio).first {
    let audioReader = try AVAssetReader(asset: asset)
    let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
    audioReader.add(audioOutput)
    guard audioReader.startReading() else { fatalError("Cannot decode audio") }
    while let sample = audioOutput.copyNextSampleBuffer() { audioSamples += CMSampleBufferGetNumSamples(sample) }
    guard audioReader.status == .completed else { fatalError("Audio decode failed") }
}
let format = track.formatDescriptions.first as! CMFormatDescription
let subtype = CMFormatDescriptionGetMediaSubType(format)
let fourcc = String(bytes: [UInt8((subtype >> 24) & 255), UInt8((subtype >> 16) & 255), UInt8((subtype >> 8) & 255), UInt8(subtype & 255)], encoding: .ascii)!
let result: [String: Any] = ["frames": count, "duration": CMTimeGetSeconds(asset.duration), "times": times,
    "top": top, "bottom": bottom, "audioSamples": audioSamples, "codec": fourcc,
    "audioDuration": asset.tracks(withMediaType: .audio).first.map { CMTimeGetSeconds($0.timeRange.duration) } ?? 0]
let json = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(data: json, encoding: .utf8)!)
