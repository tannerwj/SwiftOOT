import Foundation
import OOTDataModel

public enum MusicPlaybackPhase: String, Codable, Sendable, Equatable {
    case stopped
    case playing
    case paused
    case crossfading
}

public struct MusicTrackReference: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var kind: AudioTrackKind
    public var sequenceID: Int
    public var sequenceEnumName: String

    public init(
        id: String,
        title: String,
        kind: AudioTrackKind,
        sequenceID: Int,
        sequenceEnumName: String
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.sequenceID = sequenceID
        self.sequenceEnumName = sequenceEnumName
    }

    public init(track: AudioTrackManifest) {
        self.init(
            id: track.id,
            title: track.title,
            kind: track.kind,
            sequenceID: track.sequenceID,
            sequenceEnumName: track.sequenceEnumName
        )
    }
}

public struct MusicPlaybackState: Codable, Sendable, Equatable {
    public var phase: MusicPlaybackPhase
    public var currentTrack: MusicTrackReference?
    public var pendingTrack: MusicTrackReference?

    public init(
        phase: MusicPlaybackPhase = .stopped,
        currentTrack: MusicTrackReference? = nil,
        pendingTrack: MusicTrackReference? = nil
    ) {
        self.phase = phase
        self.currentTrack = currentTrack
        self.pendingTrack = pendingTrack
    }
}

public enum MusicPlaybackControllerError: Error, LocalizedError, Equatable, Sendable {
    case missingPlayableSample(String)

    public var errorDescription: String? {
        switch self {
        case .missingPlayableSample(let trackID):
            "Audio track \(trackID) did not include any playable sample assets."
        }
    }
}

@MainActor
public protocol MusicPlaybackControlling: AnyObject {
    func play(
        track: AudioTrackManifest,
        crossfadeDuration: TimeInterval
    ) throws
    func stop()
    func pause()
    func resume()
}
