import OOTDataModel
import simd

public struct SceneEnvironmentState: Sendable, Equatable {
    public var ambientColor: SIMD4<Float>
    public var directionalLightColor: SIMD4<Float>
    public var directionalLightDirection: SIMD4<Float>
    public var fogColor: SIMD4<Float>
    public var fogNear: Float
    public var fogFar: Float
    public var skyColor: SIMD4<Float>

    public init(
        ambientColor: SIMD4<Float>,
        directionalLightColor: SIMD4<Float>,
        directionalLightDirection: SIMD4<Float>,
        fogColor: SIMD4<Float>,
        fogNear: Float,
        fogFar: Float,
        skyColor: SIMD4<Float>
    ) {
        self.ambientColor = ambientColor
        self.directionalLightColor = directionalLightColor
        self.directionalLightDirection = directionalLightDirection
        self.fogColor = fogColor
        self.fogNear = fogNear
        self.fogFar = fogFar
        self.skyColor = skyColor
    }

    public static let `default` = SceneEnvironmentState(
        ambientColor: SIMD4<Float>(repeating: 0.35),
        directionalLightColor: SIMD4<Float>(0.8, 0.8, 0.75, 1.0),
        directionalLightDirection: SIMD4<Float>(0.0, -1.0, -0.2, 0.0),
        fogColor: SIMD4<Float>(0.0, 0.0, 0.0, 1.0),
        fogNear: 2_000.0,
        fogFar: 8_000.0,
        skyColor: SIMD4<Float>(45.0 / 255.0, 155.0 / 255.0, 52.0 / 255.0, 1.0)
    )
}

public struct EnvironmentRenderer: Sendable {
    private let environment: SceneEnvironmentFile?

    public init(environment: SceneEnvironmentFile?) {
        self.environment = environment
    }

    public func currentState(timeOfDay: Double) -> SceneEnvironmentState {
        guard let environment else {
            return .default
        }

        guard let firstSetting = environment.lightSettings.first else {
            return .default
        }

        guard environment.skybox.environmentLightingMode == "LIGHT_MODE_TIME" else {
            return makeState(from: firstSetting)
        }

        guard environment.lightSettings.count > 1 else {
            return makeState(from: firstSetting)
        }

        let interval = resolvedInterval(for: environment, timeOfDay: timeOfDay)
        let currentSetting = resolvedLightSetting(at: interval.lightSetting, environment: environment) ?? firstSetting
        let nextSetting = resolvedLightSetting(at: interval.nextLightSetting, environment: environment) ?? currentSetting
        let blend = interval.blendFactor(for: normalizedMinuteOfDay(timeOfDay))
        return blendedState(
            current: currentSetting,
            next: nextSetting,
            blend: blend
        )
    }
}

private extension EnvironmentRenderer {
    struct TimeBasedLightInterval {
        let startMinute: Int
        let endMinute: Int
        let lightSetting: Int
        let nextLightSetting: Int

        func contains(minuteOfDay: Int) -> Bool {
            minuteOfDay >= startMinute && minuteOfDay < endMinute
        }

        func blendFactor(for minuteOfDay: Int) -> Float {
            let duration = max(endMinute - startMinute, 1)
            let offset = max(0, min(minuteOfDay - startMinute, duration))
            return Float(offset) / Float(duration)
        }
    }

    static let timeBasedLightConfigs: [[TimeBasedLightInterval]] = [
        [
            .init(startMinute: 0, endMinute: 241, lightSetting: 3, nextLightSetting: 3),
            .init(startMinute: 241, endMinute: 360, lightSetting: 3, nextLightSetting: 0),
            .init(startMinute: 360, endMinute: 481, lightSetting: 0, nextLightSetting: 1),
            .init(startMinute: 481, endMinute: 960, lightSetting: 1, nextLightSetting: 1),
            .init(startMinute: 960, endMinute: 1_021, lightSetting: 1, nextLightSetting: 2),
            .init(startMinute: 1_021, endMinute: 1_141, lightSetting: 2, nextLightSetting: 3),
            .init(startMinute: 1_141, endMinute: 1_440, lightSetting: 3, nextLightSetting: 3),
        ],
        [
            .init(startMinute: 0, endMinute: 241, lightSetting: 7, nextLightSetting: 7),
            .init(startMinute: 241, endMinute: 360, lightSetting: 7, nextLightSetting: 4),
            .init(startMinute: 360, endMinute: 481, lightSetting: 4, nextLightSetting: 5),
            .init(startMinute: 481, endMinute: 960, lightSetting: 5, nextLightSetting: 5),
            .init(startMinute: 960, endMinute: 1_021, lightSetting: 5, nextLightSetting: 6),
            .init(startMinute: 1_021, endMinute: 1_141, lightSetting: 6, nextLightSetting: 7),
            .init(startMinute: 1_141, endMinute: 1_440, lightSetting: 7, nextLightSetting: 7),
        ],
        [
            .init(startMinute: 0, endMinute: 121, lightSetting: 3, nextLightSetting: 3),
            .init(startMinute: 121, endMinute: 241, lightSetting: 3, nextLightSetting: 0),
            .init(startMinute: 241, endMinute: 481, lightSetting: 0, nextLightSetting: 0),
            .init(startMinute: 481, endMinute: 600, lightSetting: 0, nextLightSetting: 1),
            .init(startMinute: 600, endMinute: 841, lightSetting: 1, nextLightSetting: 1),
            .init(startMinute: 841, endMinute: 960, lightSetting: 1, nextLightSetting: 2),
            .init(startMinute: 960, endMinute: 1_201, lightSetting: 2, nextLightSetting: 2),
            .init(startMinute: 1_201, endMinute: 1_320, lightSetting: 2, nextLightSetting: 3),
            .init(startMinute: 1_320, endMinute: 1_440, lightSetting: 3, nextLightSetting: 3),
        ],
        [
            .init(startMinute: 0, endMinute: 301, lightSetting: 11, nextLightSetting: 11),
            .init(startMinute: 301, endMinute: 360, lightSetting: 11, nextLightSetting: 8),
            .init(startMinute: 360, endMinute: 420, lightSetting: 8, nextLightSetting: 8),
            .init(startMinute: 420, endMinute: 481, lightSetting: 8, nextLightSetting: 9),
            .init(startMinute: 481, endMinute: 960, lightSetting: 9, nextLightSetting: 9),
            .init(startMinute: 960, endMinute: 1_021, lightSetting: 9, nextLightSetting: 10),
            .init(startMinute: 1_021, endMinute: 1_081, lightSetting: 10, nextLightSetting: 10),
            .init(startMinute: 1_081, endMinute: 1_141, lightSetting: 10, nextLightSetting: 11),
            .init(startMinute: 1_141, endMinute: 1_440, lightSetting: 11, nextLightSetting: 11),
        ],
        [
            .init(startMinute: 0, endMinute: 241, lightSetting: 23, nextLightSetting: 23),
            .init(startMinute: 241, endMinute: 360, lightSetting: 23, nextLightSetting: 20),
            .init(startMinute: 360, endMinute: 481, lightSetting: 20, nextLightSetting: 21),
            .init(startMinute: 481, endMinute: 960, lightSetting: 21, nextLightSetting: 21),
            .init(startMinute: 960, endMinute: 1_021, lightSetting: 21, nextLightSetting: 22),
            .init(startMinute: 1_021, endMinute: 1_141, lightSetting: 22, nextLightSetting: 23),
            .init(startMinute: 1_141, endMinute: 1_440, lightSetting: 23, nextLightSetting: 23),
        ],
    ]

    func resolvedInterval(
        for environment: SceneEnvironmentFile,
        timeOfDay: Double
    ) -> TimeBasedLightInterval {
        let configIndex = min(
            max(environment.skybox.skyboxConfig, 0),
            Self.timeBasedLightConfigs.count - 1
        )
        let config = Self.timeBasedLightConfigs[configIndex]
        let minuteOfDay = normalizedMinuteOfDay(timeOfDay)
        return config.first(where: { $0.contains(minuteOfDay: minuteOfDay) }) ?? config[config.count - 1]
    }

    func normalizedMinuteOfDay(_ timeOfDay: Double) -> Int {
        let wrappedTime = timeOfDay.truncatingRemainder(dividingBy: 24.0)
        let normalizedTime = wrappedTime >= 0 ? wrappedTime : wrappedTime + 24.0
        return Int((normalizedTime * 60.0).rounded(.down))
    }

    func resolvedLightSetting(
        at index: Int,
        environment: SceneEnvironmentFile
    ) -> SceneLightSetting? {
        guard environment.lightSettings.indices.contains(index) else {
            return environment.lightSettings.last
        }

        return environment.lightSettings[index]
    }

    func makeState(from lightSetting: SceneLightSetting) -> SceneEnvironmentState {
        let ambient = normalized(lightSetting.ambientColor)
        let directional = normalized(lightSetting.light1Color)
        let fog = normalized(lightSetting.fogColor)
        return SceneEnvironmentState(
            ambientColor: ambient,
            directionalLightColor: directional,
            directionalLightDirection: normalized(lightSetting.light1Direction),
            fogColor: fog,
            fogNear: Float(lightSetting.fogNear),
            fogFar: max(Float(lightSetting.zFar), Float(lightSetting.fogNear) + 1.0),
            skyColor: skyColor(ambient: ambient, directional: directional, fog: fog)
        )
    }

    func blendedState(
        current: SceneLightSetting,
        next: SceneLightSetting,
        blend: Float
    ) -> SceneEnvironmentState {
        let ambient = simd_mix(normalized(current.ambientColor), normalized(next.ambientColor), SIMD4<Float>(repeating: blend))
        let directional = simd_mix(normalized(current.light1Color), normalized(next.light1Color), SIMD4<Float>(repeating: blend))
        let direction = mixedDirection(current.light1Direction, next.light1Direction, blend: blend)
        let fog = simd_mix(normalized(current.fogColor), normalized(next.fogColor), SIMD4<Float>(repeating: blend))
        let fogNear = mix(Float(current.fogNear), Float(next.fogNear), t: blend)
        let fogFar = mix(Float(current.zFar), Float(next.zFar), t: blend)

        return SceneEnvironmentState(
            ambientColor: ambient,
            directionalLightColor: directional,
            directionalLightDirection: direction,
            fogColor: fog,
            fogNear: fogNear,
            fogFar: max(fogFar, fogNear + 1.0),
            skyColor: skyColor(ambient: ambient, directional: directional, fog: fog)
        )
    }

    func skyColor(
        ambient: SIMD4<Float>,
        directional: SIMD4<Float>,
        fog: SIMD4<Float>
    ) -> SIMD4<Float> {
        let fogColor = SIMD3<Float>(fog.x, fog.y, fog.z)
        let ambientColor = SIMD3<Float>(ambient.x, ambient.y, ambient.z)
        let directionalColor = SIMD3<Float>(directional.x, directional.y, directional.z)
        let blended = (fogColor * 0.55) + (ambientColor * 0.25) + (directionalColor * 0.20)
        let rgb = simd_clamp(
            blended,
            SIMD3<Float>(repeating: 0.0),
            SIMD3<Float>(repeating: 1.0)
        )
        return SIMD4<Float>(rgb, 1.0)
    }

    func normalized(_ color: RGB8) -> SIMD4<Float> {
        SIMD4<Float>(
            Float(color.red) / 255.0,
            Float(color.green) / 255.0,
            Float(color.blue) / 255.0,
            1.0
        )
    }

    func normalized(_ direction: Vector3b) -> SIMD4<Float> {
        let vector = SIMD3<Float>(
            Float(direction.x) / 127.0,
            Float(direction.y) / 127.0,
            Float(direction.z) / 127.0
        )
        let normalizedVector = simd_length_squared(vector) > 0.000_1
            ? simd_normalize(vector)
            : SIMD3<Float>(0.0, -1.0, 0.0)
        return SIMD4<Float>(normalizedVector, 0.0)
    }

    func mixedDirection(
        _ current: Vector3b,
        _ next: Vector3b,
        blend: Float
    ) -> SIMD4<Float> {
        let blended = simd_mix(
            SIMD3<Float>(
                Float(current.x),
                Float(current.y),
                Float(current.z)
            ),
            SIMD3<Float>(
                Float(next.x),
                Float(next.y),
                Float(next.z)
            ),
            SIMD3<Float>(repeating: blend)
        ) / 127.0
        let normalizedVector = simd_length_squared(blended) > 0.000_1
            ? simd_normalize(blended)
            : SIMD3<Float>(0.0, -1.0, 0.0)
        return SIMD4<Float>(normalizedVector, 0.0)
    }

    func mix(_ lhs: Float, _ rhs: Float, t: Float) -> Float {
        lhs + ((rhs - lhs) * t)
    }
}
