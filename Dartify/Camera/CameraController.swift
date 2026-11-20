//
//  CameraController.swift
//  Dartify
//

import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import Observation

/// Main-actor facing camera state for SwiftUI: calibration, locking, and dart events for the match.
@Observable
final class CameraController {
    private(set) var detection = DetectionResult.none
    /// Latest dart detection status once the board is locked.
    private(set) var dartState: DartState?
    private(set) var isLocked = false
    private(set) var permissionDenied = false

    /// A dart landed (called on the main actor).
    @ObservationIgnored var onDart: ((DetectedDart) -> Void)?
    /// The darts were pulled out of the board.
    @ObservationIgnored var onDartsPulled: (() -> Void)?

    @ObservationIgnored private let engine = CaptureEngine()
    @ObservationIgnored private var calibratedStreak = 0
    /// Calibrated frames (~2 s) before the board locks and dart detection starts.
    @ObservationIgnored private let framesBeforeLock = 30
    /// Darts of the current visit and whether it is over, as the match sees them.
    @ObservationIgnored private var visitDarts: [DetectedDart] = []
    @ObservationIgnored private var visitComplete = false

    var session: AVCaptureSession { engine.session }

    /// Short, player-facing camera status ("" when ready to score).
    var status: String {
        if permissionDenied { return "Camera access is off" }
        if !isLocked { return detection.found ? "Calibrating – hold still" : "Point the camera at the board" }
        if let s = dartState?.status, s.hasPrefix("Checking") || s.hasPrefix("Camera moved") { return s }
        return ""
    }

    init() {
        engine.onResult = { [weak self] result in
            Task { @MainActor [weak self] in
                self?.handle(result)
            }
        }
        engine.onDarts = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handle(state)
            }
        }
        engine.onRecalibrated = { [weak self] result in
            Task { @MainActor [weak self] in
                self?.detection = result
            }
        }
    }

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            permissionDenied = true
            return
        }
        engine.start()
    }

    func stop() {
        engine.stop()
    }

    /// Unlocks the board and goes back to searching/calibrating. The current visit is kept.
    func recalibrate() {
        isLocked = false
        dartState = nil
        calibratedStreak = 0
        engine.unlock()
    }

    /// Locks the current calibration right away instead of waiting for the automatic lock.
    func lockNow() {
        guard !isLocked, let homography = detection.boardToImage else { return }
        isLocked = true
        engine.lock(homography, imageSize: detection.imageSize, darts: visitDarts, complete: visitComplete)
    }

    /// Tells the detector which darts are in the board this visit and whether the visit is over
    /// (then the next change means the darts were pulled).
    func setVisit(_ darts: [DetectedDart], complete: Bool) {
        visitDarts = darts
        visitComplete = complete
        engine.setVisit(darts, complete: complete)
    }

    /// Starts a fresh visit from the board as it looks now (e.g. after "Next" without pulling darts).
    func startNewVisit() {
        visitDarts = []
        visitComplete = false
        engine.nextTurn()
    }

    /// Pauses detection while the player corrects a dart (they will probably pick the phone up).
    func beginEditing() {
        engine.pause()
    }

    /// Resumes detection; the engine first checks whether the camera moved and recalibrates if so.
    func endEditing() {
        engine.resume(darts: visitDarts, complete: visitComplete)
    }

    // MARK: - Events

    private func handle(_ result: DetectionResult) {
        guard !isLocked else { return }
        detection = result
        // An occasional frame without calibration only sets the countdown back a little.
        calibratedStreak = result.boardToImage != nil ? calibratedStreak + 1 : max(0, calibratedStreak - 3)
        if calibratedStreak >= framesBeforeLock {
            lockNow()
        }
    }

    private func handle(_ state: DartState) {
        guard isLocked else { return }
        dartState = state
        switch state.event {
        case .dart(let dart):
            onDart?(dart)
        case .cleared:
            onDartsPulled?()
        case .cameraMoved, nil:
            break
        }
    }
}

/// Owns the capture session and runs board or dart detection on camera frames off the main thread.
nonisolated final class CaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    var onResult: (@Sendable (DetectionResult) -> Void)?
    var onDarts: (@Sendable (DartState) -> Void)?
    /// The camera check found the board in a new place and re-locked to this calibration.
    var onRecalibrated: (@Sendable (DetectionResult) -> Void)?

    private enum Mode {
        /// Finding and calibrating the board.
        case calibrating
        /// Board locked; watching for darts.
        case locked
        /// Board locked, but the camera may have moved: re-detecting the board before continuing.
        case checkingCamera
        /// Board locked and probably still in place: quietly re-detecting it to refresh the calibration,
        /// giving up after a moment if it can't be seen (e.g. someone in front of the board).
        case refreshingCalibration
        /// Frames ignored (e.g. while the player edits a score).
        case paused
    }

    // Detection state, only touched on `videoQueue`.
    private var mode = Mode.calibrating
    private var boardDetector = BoardDetector()
    private var dartDetector: DartDetector?
    private var lockedHomography: Homography?
    private var lockedImageSize = CGSize.zero
    private var checker: BoardDetector?
    /// Training data: the last saved frame of the board as it is now, i.e. the next dart's "before" frame.
    private let dataset = DartDataset.shared
    private var baseFrame: String?

    private let sessionQueue = DispatchQueue(label: "dartify.camera.session")
    private let videoQueue = DispatchQueue(label: "dartify.camera.video", qos: .userInitiated)
    private var device: AVCaptureDevice?
    /// Focal length in pixels of the portrait frames, from the camera's field of view.
    private var focalLength = 1000.0
    /// Board movement (pixels) the camera check tolerates before re-locking; the dart detector lines up small shifts itself.
    private let movedTolerance = 3.0
    /// Routine refreshes re-lock when the board moved more than this (pixels), so creeping is corrected early.
    private let refreshTolerance = 1.0
    /// A routine refresh that finds the board this far away (pixels) is distrusted and ignored.
    private let refreshMaxShift = 60.0
    /// Drift (mm) since the lock after which an empty board is recalibrated, at most every `refreshInterval` s.
    private let refreshDrift = 1.5
    private let refreshInterval = 5.0
    /// Frames a routine refresh may take (~2 s) before it gives up and keeps the old calibration.
    private let refreshFrameLimit = 30
    private var refreshFrames = 0
    private var lastRefresh: TimeInterval = 0
    private let minFrameInterval = 1.0 / 15
    private var lastProcessed: TimeInterval = 0
    private var lastLogged: TimeInterval = 0
    private var configured = false

    func start() {
        sessionQueue.async {
            self.configureIfNeeded()
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func lock(_ boardToImage: Homography, imageSize: CGSize, darts: [DetectedDart], complete: Bool) {
        videoQueue.async {
            self.lockedHomography = boardToImage
            self.lockedImageSize = imageSize
            self.dartDetector = DartDetector(boardToImage: boardToImage, focalLength: self.focalLength, imageSize: imageSize,
                                             darts: darts, turnComplete: complete)
            self.baseFrame = nil
            self.mode = .locked
        }
        sessionQueue.async { self.setCaptureLocked(true) }
    }

    func unlock() {
        videoQueue.async {
            self.dartDetector = nil
            self.boardDetector = BoardDetector()
            self.mode = .calibrating
        }
        sessionQueue.async { self.setCaptureLocked(false) }
    }

    func nextTurn() {
        videoQueue.async {
            self.dartDetector?.nextTurn()
            self.baseFrame = nil
        }
    }

    func setVisit(_ darts: [DetectedDart], complete: Bool) {
        videoQueue.async { self.dartDetector?.setDarts(darts, turnComplete: complete) }
    }

    func pause() {
        videoQueue.async {
            if self.dartDetector != nil { self.mode = .paused }
        }
    }

    /// Resumes after a pause with the corrected darts, checking the camera position first.
    func resume(darts: [DetectedDart], complete: Bool) {
        videoQueue.async {
            guard let detector = self.dartDetector else { return }
            detector.setDarts(darts, turnComplete: complete)
            self.startCameraCheck()
        }
    }

    private func startCameraCheck() {
        checker = BoardDetector()
        mode = .checkingCamera
    }

    private func startRefresh(now: TimeInterval) {
        checker = BoardDetector()
        refreshFrames = 0
        lastRefresh = now
        mode = .refreshingCalibration
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // 1080p gives about 1 px per mm on a board 1.5 m away, so thin steel points still show.
        let longSide: Double
        if session.canSetSessionPreset(.hd1920x1080) {
            session.sessionPreset = .hd1920x1080
            longSide = 1920
        } else {
            session.sessionPreset = .hd1280x720
            longSide = 1280
        }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)
        self.device = device

        // The field of view spans the sensor's long side, which is the height of the portrait frames.
        let fov = Double(device.activeFormat.videoFieldOfView) * .pi / 180
        if fov > 0 { focalLength = longSide / 2 / tan(fov / 2) }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        // Deliver portrait frames so detection coordinates match the portrait preview.
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }

    /// Freezes exposure, white balance and focus while detecting darts, so frame differences are real changes.
    private func setCaptureLocked(_ locked: Bool) {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if locked {
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
        } else {
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastProcessed >= minFrameInterval,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        lastProcessed = now

        var lines: [String] = []
        switch mode {
        case .paused:
            return

        case .calibrating:
            let result = boardDetector.process(pixelBuffer)
            lines = result.debug.lines
            onResult?(result)

        case .locked:
            guard let dartDetector else { return }
            var state = dartDetector.process(pixelBuffer)
            collectTrainingData(&state, pixelBuffer, dartDetector)
            lines = [state.status] + state.debug.lines
            if state.event == .cameraMoved {
                startCameraCheck()
            } else if state.event == .cleared {
                // Darts just pulled: the player is walking back, a good moment to refresh the calibration.
                startRefresh(now: now)
            } else if state.event == nil, dartDetector.darts.isEmpty, !dartDetector.turnComplete,
                      dartDetector.driftSinceLock > refreshDrift, now - lastRefresh >= refreshInterval {
                startRefresh(now: now)
            }
            let rejected = state.debug.lines.contains { $0.hasPrefix("✗ change") || $0.hasPrefix("✗ no tip") }
            if state.event != nil || rejected {
                // Always log what led to an event, and keep the debug image of each dart (or rejected change) for tuning.
                let entry = "[Dartify] EVENT \(state.event.map { "\($0)" } ?? "rejected")\n  " + lines.joined(separator: "\n  ")
                print(entry)
                appendDebugLog(entry)
                if rejected { saveDebugImage(state.debug.mask, name: "rejected") }
                if case .dart = state.event { saveDebugImage(state.debug.mask, name: "dart") }
            }
            onDarts?(state)

        case .checkingCamera:
            lines = checkCamera(pixelBuffer)

        case .refreshingCalibration:
            lines = refreshCalibration(pixelBuffer)
        }

        if now - lastLogged >= 1 {
            lastLogged = now
            print("[Dartify]\n  " + lines.joined(separator: "\n  "))
            appendDebugLog("[\(mode)]\n  " + lines.joined(separator: "\n  "))
        }
    }

    /// Appends an event to Documents/debug/log.txt (debug builds only), so it survives a dropped Xcode connection.
    private func appendDebugLog(_ entry: String) {
        #if DEBUG
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("log.txt")
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let data = Data("\(formatter.string(from: Date())) \(entry)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
        #endif
    }

    /// Writes the detector's top-down debug view to Documents/debug (debug builds only), so it can be
    /// copied off the phone with `devicectl device copy from`.
    private func saveDebugImage(_ image: CGImage?, name: String) {
        #if DEBUG
        guard let image, let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appendingPathComponent("debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss-SSS"
        let url = folder.appendingPathComponent("\(name)-\(formatter.string(from: Date())).png")
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        #endif
    }

    /// Re-detects the board. If it is where the lock expects, detection resumes with the old reference;
    /// if it moved, detection re-locks to the new calibration (keeping the turn's darts).
    private func checkCamera(_ pixelBuffer: CVPixelBuffer) -> [String] {
        guard let checker, let locked = lockedHomography, let detector = dartDetector else {
            mode = .calibrating
            return []
        }
        let result = checker.process(pixelBuffer)
        var status = "Checking camera position…"

        if let homography = result.boardToImage {
            let shift = Self.maxShift(locked, homography)
            if shift <= movedTolerance {
                detector.resumeAfterCameraCheck()
                status = "Camera OK"
            } else {
                relock(homography, result: result, keeping: detector)
                status = String(format: "Camera moved %.0f px – recalibrated", shift)
            }
            mode = .locked
            self.checker = nil
        }

        let lines = [status] + result.debug.lines
        onDarts?(DartState(status: status, debug: DetectionDebug(lines: lines, mask: result.debug.mask)))
        return lines
    }

    /// Routine re-detection of a board that is probably in place. Re-locks (keeping the turn's darts) when it
    /// crept more than `refreshTolerance`; otherwise, or if the board can't be found, carries on as before.
    private func refreshCalibration(_ pixelBuffer: CVPixelBuffer) -> [String] {
        guard let checker, let locked = lockedHomography, let detector = dartDetector else {
            mode = .calibrating
            return []
        }
        let result = checker.process(pixelBuffer)
        refreshFrames += 1
        var status = "Auto-calibrating…"
        var done = false

        if let homography = result.boardToImage {
            let shift = Self.maxShift(locked, homography)
            if shift > refreshTolerance && shift <= refreshMaxShift {
                relock(homography, result: result, keeping: detector)
                status = String(format: "Auto-calibrated: board moved %.1f px (drift was %.1f mm)", shift, detector.driftSinceLock)
            } else {
                detector.resumeAfterRefresh()
                status = String(format: "Auto-calibration: board moved %.1f px, kept", shift)
            }
            done = true
        } else if refreshFrames >= refreshFrameLimit {
            detector.resumeAfterRefresh()
            status = "Auto-calibration: board not found, kept"
            done = true
        }
        if done {
            mode = .locked
            self.checker = nil
            print("[Dartify] " + status)
            appendDebugLog(status)
        }

        let lines = [status] + result.debug.lines
        onDarts?(DartState(status: status, debug: DetectionDebug(lines: lines, mask: result.debug.mask)))
        return lines
    }

    /// Saves frames and a record for each detected dart (see `DartDataset`) and tags the dart with the record id.
    private func collectTrainingData(_ state: inout DartState, _ pixelBuffer: CVPixelBuffer, _ detector: DartDetector) {
        switch state.event {
        case .dart(var dart):
            guard let homography = lockedHomography,
                  let saved = dataset.recordDart(after: pixelBuffer, before: baseFrame, dart: dart,
                                                 dartIndex: detector.darts.count - 1, tip: detector.lastTipInfo,
                                                 boardToImage: homography, camera: detector.cameraPose)
            else { return }
            dart.captureID = saved.id
            state.event = .dart(dart)
            baseFrame = saved.frame
        case .cleared:
            // This frame is the empty board the next darts are compared with.
            baseFrame = dataset.saveFrame(pixelBuffer)
        case .cameraMoved:
            baseFrame = nil
        case nil:
            // After a lock or a new turn, keep the first still frame as the "before" frame.
            if baseFrame == nil && (state.status.hasPrefix("Ready") || state.status.hasPrefix("New turn")) {
                baseFrame = dataset.saveFrame(pixelBuffer)
            }
        }
    }

    private func relock(_ homography: Homography, result: DetectionResult, keeping detector: DartDetector) {
        lockedHomography = homography
        lockedImageSize = result.imageSize
        dartDetector = DartDetector(boardToImage: homography, focalLength: focalLength,
                                    imageSize: result.imageSize, darts: detector.darts,
                                    turnComplete: detector.turnComplete)
        baseFrame = nil
        onRecalibrated?(result)
    }

    /// Largest image-space difference between two calibrations at the bull and the double ring.
    private static func maxShift(_ a: Homography, _ b: Homography) -> Double {
        let r = BoardGeometry.doubleOuter
        return [(0.0, 0.0), (r, 0), (-r, 0), (0, r), (0, -r)].compactMap { p -> Double? in
            guard let pa = a.apply(p.0, p.1), let pb = b.apply(p.0, p.1) else { return nil }
            return hypot(pa.x - pb.x, pa.y - pb.y)
        }.max() ?? .infinity
    }
}
