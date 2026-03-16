import OOTDataModel

struct SelectedSceneSkybox: Sendable, Equatable {
    let stateID: String
    let assetIDsByFace: [SceneSkyboxFace: UInt32]
}

struct SceneSkyboxSelector: Sendable {
    let skybox: SceneResolvedSkybox?

    func selection(timeOfDay: Double) -> SelectedSceneSkybox? {
        guard let skybox else {
            return nil
        }

        let state: SceneSkyboxAssetState?
        if skybox.schedule.isEmpty {
            state = skybox.states.first
        } else {
            let minuteOfDay = normalizedMinuteOfDay(timeOfDay)
            let selectedStateID = skybox.schedule.first(where: {
                minuteOfDay >= $0.startMinute && minuteOfDay < $0.endMinute
            })?.stateID ?? skybox.schedule.last?.stateID
            state = selectedStateID.flatMap { stateID in
                skybox.states.first(where: { $0.id == stateID })
            }
        }

        guard let state else {
            return nil
        }

        return SelectedSceneSkybox(
            stateID: state.id,
            assetIDsByFace: Dictionary(
                uniqueKeysWithValues: state.faces.map {
                    ($0.face, OOTAssetID.stableID(for: $0.assetName))
                }
            )
        )
    }

    private func normalizedMinuteOfDay(_ timeOfDay: Double) -> Int {
        let wrappedTime = timeOfDay.truncatingRemainder(dividingBy: 24.0)
        let normalizedTime = wrappedTime >= 0 ? wrappedTime : wrappedTime + 24.0
        return Int((normalizedTime * 60.0).rounded(.down))
    }
}
