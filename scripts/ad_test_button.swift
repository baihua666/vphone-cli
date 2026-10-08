// Locate only the Orblino test-panel load button; never an advertisement CTA.
import Foundation
import Vision
import ImageIO

guard CommandLine.arguments.count == 3,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fputs("Usage: ad_test_button.swift screenshot.jpg exact-label\n", stderr)
    exit(2)
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["zh-Hans", "en-US"]
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: image).perform([request])
let label = CommandLine.arguments[2]
let matches = (request.results ?? []).filter {
    $0.topCandidates(1).first?.string.replacingOccurrences(of: " ", with: "") == label
}
guard matches.count == 1, let match = matches.first else {
    fputs("Expected exactly one visible test button: \(label); found \(matches.count)\n", stderr)
    exit(1)
}
let rect = match.boundingBox
let result: [String: Any] = ["label": label, "x": rect.midX, "y": 1 - rect.midY,
                             "image_width": image.width, "image_height": image.height]
let output = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: output, as: UTF8.self))
