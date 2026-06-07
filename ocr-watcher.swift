import Foundation
import Vision
import AppKit

class OCRWatcher {
    let watchPath: String
    var eventStream: FSEventStreamRef?
    let eventQueue = DispatchQueue(label: "ocr.fsevents")

    init(watchPath: String) {
        self.watchPath = watchPath
        try? FileManager.default.createDirectory(atPath: watchPath, withIntermediateDirectories: true)
    }

    func startWatching() {
        setbuf(stdout, nil)
        setbuf(stderr, nil)

        print("[\(Date())] OCR Watcher starting...")
        print("[\(Date())] Watching directory: \(watchPath)")

        // Process any files already present at launch
        checkDirectory()

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
            let watcher = Unmanaged<OCRWatcher>.fromOpaque(clientCallBackInfo!).takeUnretainedValue()
            watcher.checkDirectory()
        }

        let pathsToWatch = [watchPath] as CFArray

        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.1,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )

        guard let stream = eventStream else {
            print("[\(Date())] ERROR: Failed to create FSEventStream")
            return
        }

        FSEventStreamSetDispatchQueue(stream, eventQueue)

        if !FSEventStreamStart(stream) {
            print("[\(Date())] ERROR: Failed to start FSEventStream")
            return
        }

        print("[\(Date())] Ready! Watching \(watchPath) — drop a screenshot here to OCR it")
        dispatchMain()
    }

    func checkDirectory() {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: watchPath)) ?? []
        for file in contents {
            let ext = (file as NSString).pathExtension.lowercased()
            guard ["png", "jpg", "jpeg"].contains(ext) else { continue }
            let fullPath = (watchPath as NSString).appendingPathComponent(file)
            waitForStableFile(at: fullPath) {
                self.processImage(at: fullPath)
            }
        }
    }

    // Poll the file size every 30ms until we see two consecutive stable reads,
    // then invoke `completion`. Bails out after `maxWait` regardless.
    func waitForStableFile(at path: String, maxWait: TimeInterval = 0.5, completion: @escaping () -> Void) {
        var lastSize: Int64 = -1
        var stableHits = 0
        let start = Date()
        let pollInterval: TimeInterval = 0.03

        func size() -> Int64 {
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? -1
        }

        func poll() {
            let s = size()
            if s > 0 && s == lastSize {
                stableHits += 1
                if stableHits >= 2 { completion(); return }
            } else {
                stableHits = 0
            }
            lastSize = s
            if Date().timeIntervalSince(start) > maxWait { completion(); return }
            eventQueue.asyncAfter(deadline: .now() + pollInterval, execute: poll)
        }
        poll()
    }

    func processImage(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }

        guard let image = NSImage(contentsOfFile: path) else {
            print("[\(Date())] ERROR: Failed to load image: \(path)")
            return
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("[\(Date())] ERROR: Failed to get CGImage")
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            if let error = error {
                print("OCR error: \(error)")
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                return
            }

            let recognizedText = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }.joined(separator: "\n")

            if !recognizedText.isEmpty {
                self.copyToClipboard(recognizedText)
                self.showNotification()
            }

            try? FileManager.default.removeItem(atPath: path)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform OCR: \(error)")
            }
        }
    }

    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        print("Text copied to clipboard (\(text.count) characters)")
    }

    func showNotification() {
        let script = """
        display notification "Text copied to clipboard" with title "OCR Complete"
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        do {
            try task.run()
        } catch {
            print("Failed to show notification: \(error)")
        }
    }

    deinit {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}

let watchPath = "/tmp/ocr-screenshots"
let watcher = OCRWatcher(watchPath: watchPath)
watcher.startWatching()
