import Foundation
import OOTDataModel

public struct TimeSystem: Sendable, Equatable {
    public static let updateInterval: Duration = .milliseconds(100)

    public var gameMinutesPerRealSecond: Double

    public init(gameMinutesPerRealSecond: Double = 1.0) {
        self.gameMinutesPerRealSecond = gameMinutesPerRealSecond
    }

    public func advance(
        _ gameTime: GameTime,
        byRealSeconds realSeconds: Double
    ) -> GameTime {
        guard realSeconds > 0 else {
            return gameTime
        }

        var updated = gameTime
        updated.frameCount += max(1, Int((realSeconds * 60.0).rounded()))
        updated.timeOfDay = normalizedTimeOfDay(
            gameTime.timeOfDay + ((realSeconds * gameMinutesPerRealSecond) / 60.0)
        )
        return updated
    }

    public func initialTimeOfDay(for environment: SceneEnvironmentFile?) -> Double? {
        guard let time = environment?.time else {
            return nil
        }

        guard (0..<24).contains(time.hour), (0..<60).contains(time.minute) else {
            return nil
        }

        return Double(time.hour) + (Double(time.minute) / 60.0)
    }

    public func normalizedTimeOfDay(_ timeOfDay: Double) -> Double {
        let wrapped = timeOfDay.truncatingRemainder(dividingBy: 24.0)
        return wrapped >= 0 ? wrapped : wrapped + 24.0
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        let seconds = Double(components.seconds)
        let attoseconds = Double(components.attoseconds) / 1_000_000_000_000_000_000.0
        return seconds + attoseconds
    }
}
