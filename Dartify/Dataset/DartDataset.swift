//
//  DartDataset.swift
//  Dartify
//

import CoreImage
import CoreVideo
import Foundation

/// Collects training data for a future tip-finding model while you play.
///
/// For every dart the camera finds, the full camera frames before and after the throw are saved as JPEGs, with
/// a JSON record of the calibration and where the detector put the tip. When the visit ends, the record gets
/// the final score: kept as detected, corrected, or removed (not a dart, or a dart that didn't count).
///
/// Everything lives in Documents/dataset, which the Files app shows (On My iPhone › Dartify):
/// `<id>.json` per dart and `frames/<frame>.jpg`. Consecutive darts share frames: a dart's "after" frame is
/// the next dart's "before" frame.
nonisolated final class DartDataset: @unchecked Sendable {
    static let shared = DartDataset()

    /// What the detector worked out about the tip, besides the position itself.
    struct TipInfo: Codable, Sendable {
        /// Tip in camera-frame pixels.
        var tipImage: [Double]?
        /// Unit vector in board millimetres (y up) from the tip toward the flight, as the change looked from the camera.
        var axis: [Double]
        /// Length (mm) of the change on the board view.
        var length: Double
        /// How far (mm) a faint point was followed beyond the clearly changed part.
        var tipExtension: Int
        /// "width" when the narrow end decided which end is the tip, "camera" when the camera position did.
        var tipBy: String
        /// How far the view had shifted since the lock (board-view pixels, x right, y down).
        var drift: [Double]
    }

    struct Record: Codable {
        enum Label: String, Codable {
            /// The visit hasn't ended yet.
            case pending
            /// The player kept the detected score.
            case confirmed
            /// The player changed the score.
            case corrected
            /// The player removed the dart, or it never counted (e.g. thrown during a bot's turn).
            case removed
        }

        var id: UUID
        var date: Date
        /// Frame file names in `frames/`; `before` is nil when no quiet frame was saved since the lock.
        var before: String?
        var after: String
        var imageWidth: Int
        var imageHeight: Int
        /// Board millimetres (origin at the bull, y up) → camera pixels, row-major 3×3.
        var boardToImage: [Double]
        var cameraFoot: [Double]?
        var cameraDistance: Double?
        /// Position of this dart in the visit (0–2).
        var dartIndex: Int
        /// Tip in board millimetres, corrected for drift.
        var detectedX: Double
        var detectedY: Double
        var detectedScore: BoardScore
        var tip: TipInfo?
        var label: Label = .pending
        var finalScore: BoardScore?
    }

    private let queue = DispatchQueue(label: "dartify.dataset", qos: .utility)
    private let context = CIContext()
    private let folder: URL?
    private let frames: URL?
    /// Darts recorded this visit that haven't been labelled yet (only touched on `queue`).
    private var pending: [UUID] = []
    /// Stop collecting after this many darts (~0.5 MB each), so a forgotten setting can't fill the phone.
    private let maxRecords = 5000
    private var recordCount = 0

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        folder = documents?.appendingPathComponent("dataset", isDirectory: true)
        frames = folder?.appendingPathComponent("frames", isDirectory: true)
        if let frames {
            try? FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        }
        if let folder, let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            recordCount = files.filter { $0.hasSuffix(".json") }.count
        }
    }

    var isFull: Bool { recordCount >= maxRecords }

    /// Saves a camera frame as a JPEG in the background and returns its file name right away.
    func saveFrame(_ pixelBuffer: CVPixelBuffer) -> String? {
        guard let frames, !isFull else { return nil }
        let name = UUID().uuidString + ".jpg"
        let url = frames.appendingPathComponent(name)
        let buffer = UncheckedBuffer(pixelBuffer)
        queue.async { [context] in
            let image = CIImage(cvPixelBuffer: buffer.value)
            let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.9]
            try? context.writeJPEGRepresentation(of: image, to: url,
                                                 colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: options)
        }
        return name
    }

    /// Records a detected dart: saves the frame after the throw and writes its record. Returns the record id and
    /// the saved frame's name (the next dart's "before" frame), or nil when collection is full.
    func recordDart(after pixelBuffer: CVPixelBuffer, before: String?, dart: DetectedDart, dartIndex: Int,
                    tip: TipInfo?, boardToImage: Homography, camera: (foot: (x: Double, y: Double), distance: Double)?) -> (id: UUID, frame: String)? {
        guard let folder, let after = saveFrame(pixelBuffer) else { return nil }
        let record = Record(
            id: UUID(),
            date: Date(),
            before: before,
            after: after,
            imageWidth: CVPixelBufferGetWidth(pixelBuffer),
            imageHeight: CVPixelBufferGetHeight(pixelBuffer),
            boardToImage: boardToImage.m,
            cameraFoot: camera.map { [$0.foot.x, $0.foot.y] },
            cameraDistance: camera?.distance,
            dartIndex: dartIndex,
            detectedX: dart.x,
            detectedY: dart.y,
            detectedScore: dart.score,
            tip: tip
        )
        recordCount += 1
        queue.async {
            self.write(record, in: folder)
            self.pending.append(record.id)
        }
        return (record.id, after)
    }

    /// Fills in the final scores once a visit is over. `darts` is the visit as it counted; recorded darts of
    /// this visit that aren't in it were removed.
    func labelVisit(_ darts: [DetectedDart]) {
        guard let folder else { return }
        let finals = darts.compactMap { dart in dart.captureID.map { ($0, dart.score) } }
        queue.async {
            for (id, score) in finals {
                self.update(id, in: folder) { record in
                    record.finalScore = score
                    record.label = score == record.detectedScore ? .confirmed : .corrected
                }
            }
            let kept = Set(finals.map(\.0))
            for id in self.pending where !kept.contains(id) {
                self.update(id, in: folder) { record in
                    record.finalScore = nil
                    record.label = .removed
                }
            }
            self.pending.removeAll()
        }
    }

    // MARK: - Files

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        // Hand-entered darts have no position.
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }()

    private func write(_ record: Record, in folder: URL) {
        guard let data = try? encoder.encode(record) else { return }
        try? data.write(to: folder.appendingPathComponent("\(record.id.uuidString).json"), options: .atomic)
    }

    private func update(_ id: UUID, in folder: URL, _ change: (inout Record) -> Void) {
        let url = folder.appendingPathComponent("\(id.uuidString).json")
        guard let data = try? Data(contentsOf: url), var record = try? decoder.decode(Record.self, from: data) else { return }
        change(&record)
        write(record, in: folder)
    }
}

/// Lets a camera frame be handed to the dataset queue; it is only read there.
private nonisolated struct UncheckedBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
    init(_ value: CVPixelBuffer) { self.value = value }
}
