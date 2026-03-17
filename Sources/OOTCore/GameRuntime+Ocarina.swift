import OOTDataModel
import simd

extension GameRuntime {
    public var isOcarinaSessionActive: Bool {
        ocarinaSession != nil
    }

    public func beginOcarinaTeaching(_ song: QuestSong) {
        statusMessage = "Listen to \(song.title), then repeat it."
        ocarinaSession = OcarinaSessionState(
            mode: .teachingPlayback,
            teachingSong: song,
            enteredNotes: [],
            promptNotes: song.ocarinaNotes,
            highlightedPromptNoteIndex: nil,
            playbackFrameCounter: 0
        )
    }
}

extension GameRuntime {
    private enum OcarinaConstants {
        static let noteLimit = 8
        static let playbackStepFrames = 14
        static let recognitionFrames = 120
    }

    private struct OcarinaTagContext {
        let trigger: SceneCutsceneTrigger
        let type: Int
        let switchFlag: Int?
        let expectedSong: QuestSong?
        let acceptsScarecrowStyleSong: Bool
    }

    func toggleOcarinaSession() {
        guard inventoryState.canUse(.ocarina) else {
            return
        }

        if isOcarinaSessionActive {
            finishOcarinaSession(message: "Stopped playing the ocarina.")
            return
        }

        activeSlingshotAimState = nil
        statusMessage = "Ocarina ready."
        ocarinaRecognition = nil
        ocarinaSession = OcarinaSessionState(
            mode: .freePlay,
            teachingSong: nil,
            enteredNotes: [],
            promptNotes: [],
            highlightedPromptNoteIndex: nil,
            playbackFrameCounter: 0,
            noteLimit: OcarinaConstants.noteLimit
        )
    }

    @discardableResult
    func updateOcarinaState(
        currentInput: ControllerInputState,
        previousInput: ControllerInputState
    ) -> Bool {
        tickOcarinaRecognitionState()

        guard var session = ocarinaSession else {
            return false
        }

        if currentInput.bPressed, previousInput.bPressed == false {
            finishOcarinaSession(message: "Stopped playing the ocarina.")
            return true
        }

        switch session.mode {
        case .freePlay:
            processOcarinaNoteInput(
                currentInput: currentInput,
                previousInput: previousInput,
                session: &session
            )
        case .teachingPlayback:
            advanceTeachingPlayback(session: &session)
        case .teachingRepeat:
            processOcarinaNoteInput(
                currentInput: currentInput,
                previousInput: previousInput,
                session: &session
            )
        }

        if ocarinaSession != nil {
            ocarinaSession = session
        }

        return true
    }

    func tickOcarinaRecognitionState() {
        guard var recognition = ocarinaRecognition else {
            return
        }

        recognition.remainingFrames -= 1
        if recognition.remainingFrames <= 0 {
            ocarinaRecognition = nil
            return
        }

        ocarinaRecognition = recognition
    }

    func advanceTeachingPlayback(session: inout OcarinaSessionState) {
        guard session.promptNotes.isEmpty == false else {
            session.mode = .teachingRepeat
            statusMessage = "Now repeat the melody."
            return
        }

        let noteIndex = session.playbackFrameCounter / OcarinaConstants.playbackStepFrames
        session.highlightedPromptNoteIndex = session.promptNotes.indices.contains(noteIndex) ? noteIndex : nil
        session.playbackFrameCounter += 1

        if noteIndex >= session.promptNotes.count {
            session.mode = .teachingRepeat
            session.playbackFrameCounter = 0
            session.highlightedPromptNoteIndex = nil
            statusMessage = "Now repeat the melody."
        }
    }

    func processOcarinaNoteInput(
        currentInput: ControllerInputState,
        previousInput: ControllerInputState,
        session: inout OcarinaSessionState
    ) {
        let triggeredNotes = ocarinaNotesTriggered(
            currentInput: currentInput,
            previousInput: previousInput
        )

        for note in triggeredNotes {
            recordOcarina(
                note: note,
                session: &session
            )
            guard ocarinaSession != nil else {
                return
            }
        }
    }

    func ocarinaNotesTriggered(
        currentInput: ControllerInputState,
        previousInput: ControllerInputState
    ) -> [OcarinaNote] {
        var triggered: [OcarinaNote] = []

        if currentInput.aPressed, previousInput.aPressed == false {
            triggered.append(.a)
        }
        if currentInput.cUpPressed, previousInput.cUpPressed == false {
            triggered.append(.cUp)
        }
        if currentInput.cLeftPressed, previousInput.cLeftPressed == false {
            triggered.append(.cLeft)
        }
        if currentInput.cRightPressed, previousInput.cRightPressed == false {
            triggered.append(.cRight)
        }
        if currentInput.cDownPressed, previousInput.cDownPressed == false {
            triggered.append(.cDown)
        }

        return triggered
    }

    func recordOcarina(
        note: OcarinaNote,
        session: inout OcarinaSessionState
    ) {
        session.enteredNotes.append(note)
        if session.enteredNotes.count > session.noteLimit {
            session.enteredNotes.removeFirst(session.enteredNotes.count - session.noteLimit)
        }

        switch session.mode {
        case .freePlay:
            guard let song = recognizedFreePlaySong(from: session.enteredNotes) else {
                if session.enteredNotes.count >= session.noteLimit {
                    finishOcarinaSession(message: "That melody does not match a learned song.")
                }
                return
            }

            completeOcarinaRecognition(song: song)
        case .teachingPlayback:
            return
        case .teachingRepeat:
            guard let teachingSong = session.teachingSong else {
                finishOcarinaSession(message: "The teaching sequence ended unexpectedly.")
                return
            }

            let expectedNotes = teachingSong.ocarinaNotes
            if expectedNotes.starts(with: session.enteredNotes) == false {
                let summary = "That was not \(teachingSong.title)."
                ocarinaRecognition = OcarinaRecognitionState(
                    song: teachingSong,
                    summary: summary,
                    remainingFrames: OcarinaConstants.recognitionFrames,
                    learnedThroughTeaching: false
                )
                finishOcarinaSession(message: summary)
                return
            }

            if session.enteredNotes == expectedNotes {
                inventoryContext.questStatus.songs.insert(teachingSong)
                persistActiveSaveSlotState()
                completeOcarinaRecognition(
                    song: teachingSong,
                    learnedThroughTeaching: true
                )
            }
        }
    }

    func recognizedFreePlaySong(from notes: [OcarinaNote]) -> QuestSong? {
        let learnedChildSongs = QuestSong.childEraSongs.filter { inventoryContext.questStatus.songs.contains($0) }

        return learnedChildSongs.first { song in
            guard notes.count >= song.ocarinaNotes.count else {
                return false
            }

            return Array(notes.suffix(song.ocarinaNotes.count)) == song.ocarinaNotes
        }
    }

    func completeOcarinaRecognition(
        song: QuestSong,
        learnedThroughTeaching: Bool = false
    ) {
        let effect = resolveOcarinaWorldEffect(
            for: song,
            learnedThroughTeaching: learnedThroughTeaching
        )
        lastResolvedOcarinaEffect = effect
        ocarinaRecognition = OcarinaRecognitionState(
            song: song,
            summary: effect.summary,
            remainingFrames: OcarinaConstants.recognitionFrames,
            learnedThroughTeaching: learnedThroughTeaching
        )
        finishOcarinaSession(message: effect.summary)
    }

    func resolveOcarinaWorldEffect(
        for song: QuestSong,
        learnedThroughTeaching: Bool
    ) -> OcarinaWorldEffectResult {
        if learnedThroughTeaching {
            return OcarinaWorldEffectResult(
                song: song,
                kind: .teachingSuccess,
                summary: "You learned \(song.title)."
            )
        }

        switch song {
        case .zeldasLullaby:
            if let trigger = activeOcarinaTag(for: song) {
                return applyOcarinaTriggerEffect(
                    song: song,
                    trigger: trigger,
                    summary: "Zelda's Lullaby activates the crest."
                )
            }
            return OcarinaWorldEffectResult(
                song: song,
                kind: .practice,
                summary: "Zelda's Lullaby echoes, but nothing nearby responds."
            )
        case .eponasSong:
            return OcarinaWorldEffectResult(
                song: song,
                kind: .callEpona,
                summary: "Epona's Song rings out across the field."
            )
        case .sariasSong:
            return OcarinaWorldEffectResult(
                song: song,
                kind: .contactSaria,
                summary: "Saria's Song reaches out for a reply."
            )
        case .sunsSong:
            let nextTimeOfDay = gameTime.timeOfDay >= 6.0 && gameTime.timeOfDay < 18.0 ? 18.0 : 6.0
            gameTime.timeOfDay = nextTimeOfDay
            let summary = nextTimeOfDay == 18.0
                ? "Sun's Song shifts Hyrule toward night."
                : "Sun's Song shifts Hyrule toward day."
            return OcarinaWorldEffectResult(
                song: song,
                kind: nextTimeOfDay == 18.0 ? .advanceToNight : .advanceToDay,
                summary: summary
            )
        case .songOfTime:
            if let trigger = activeOcarinaTag(for: song) {
                return applyOcarinaTriggerEffect(
                    song: song,
                    trigger: trigger,
                    summary: "The Song of Time stirs the hidden mechanism."
                )
            }
            return OcarinaWorldEffectResult(
                song: song,
                kind: .practice,
                summary: "The Song of Time resonates, but no nearby block or seal responds."
            )
        case .songOfStorms:
            if let trigger = activeOcarinaTag(for: song) {
                return applyOcarinaTriggerEffect(
                    song: song,
                    trigger: trigger,
                    summary: "The Song of Storms whips the windmill into motion."
                )
            }
            if let trigger = activeWeatherSongTrigger() {
                return applyWeatherSongEffect(
                    song: song,
                    trigger: trigger
                )
            }
            return OcarinaWorldEffectResult(
                song: song,
                kind: .startRain,
                summary: "Storm clouds gather, but no nearby weather trigger responds."
            )
        case .minuetOfForest,
             .boleroOfFire,
             .serenadeOfWater,
             .requiemOfSpirit,
             .nocturneOfShadow,
             .preludeOfLight:
            return OcarinaWorldEffectResult(
                song: song,
                kind: .practice,
                summary: "\(song.title) is not wired into child-era world logic yet."
            )
        }
    }

    private func applyOcarinaTriggerEffect(
        song: QuestSong,
        trigger: OcarinaTagContext,
        summary: String
    ) -> OcarinaWorldEffectResult {
        let eventFlag = makeSongEventFlag(
            roomID: trigger.trigger.roomID,
            actorID: trigger.trigger.id,
            params: Int(trigger.trigger.params),
            center: trigger.trigger.volume.center
        )

        if inventoryState.hasTriggeredDungeonEvent(eventFlag) == false {
            inventoryState.markDungeonEventTriggered(eventFlag)
            persistActiveSaveSlotState()
        }

        return OcarinaWorldEffectResult(
            song: song,
            kind: .worldTrigger,
            summary: summary,
            eventFlag: eventFlag
        )
    }

    func applyWeatherSongEffect(
        song: QuestSong,
        trigger: SceneEventRegionTrigger
    ) -> OcarinaWorldEffectResult {
        let summary = switch trigger.kind {
        case "thunderstormGraveyard":
            "Rain crashes down over the graveyard."
        case "thunderstormKakariko":
            "A storm rolls across Kakariko."
        case "rainLakeHylia":
            "Rain sweeps over Lake Hylia."
        default:
            "The Song of Storms stirs the weather."
        }

        let eventFlag = makeSongEventFlag(
            roomID: trigger.roomID,
            actorID: trigger.id,
            params: Int(trigger.params),
            center: trigger.volume.center
        )

        if inventoryState.hasTriggeredDungeonEvent(eventFlag) == false {
            inventoryState.markDungeonEventTriggered(eventFlag)
            persistActiveSaveSlotState()
        }

        return OcarinaWorldEffectResult(
            song: song,
            kind: .startRain,
            summary: summary,
            eventFlag: eventFlag
        )
    }

    func finishOcarinaSession(message: String?) {
        ocarinaSession = nil
        statusMessage = message
    }

    private func activeOcarinaTag(for song: QuestSong) -> OcarinaTagContext? {
        let triggers = (playState?.scene ?? loadedScene)?.sceneHeader?.cutsceneTriggers ?? []
        return triggers
            .compactMap(ocarinaTagContext(for:))
            .first { context in
                context.expectedSong == song &&
                    isPlayerInside(cylinder: context.trigger.volume, roomID: context.trigger.roomID)
            }
    }

    func activeWeatherSongTrigger() -> SceneEventRegionTrigger? {
        let triggers = (playState?.scene ?? loadedScene)?.sceneHeader?.eventRegionTriggers ?? []
        return triggers.first { trigger in
            isPlayerInside(cylinder: trigger.volume, roomID: trigger.roomID) &&
                (trigger.kind.contains("thunderstorm") || trigger.kind.contains("rain"))
        }
    }

    private func ocarinaTagContext(for trigger: SceneCutsceneTrigger) -> OcarinaTagContext? {
        guard trigger.kind == "ocarinaTag" else {
            return nil
        }

        let params = UInt16(bitPattern: trigger.params)
        let type = Int((params >> 10) & 0x3F)
        let songIndex = Int((params >> 6) & 0x0F)
        let rawSwitchFlag = Int(params & 0x003F)
        let switchFlag = rawSwitchFlag == 0x3F ? nil : rawSwitchFlag

        let expectedSong: QuestSong?
        switch type {
        case 1, 6:
            expectedSong = .zeldasLullaby
        case 2:
            expectedSong = .songOfStorms
        case 4:
            expectedSong = .songOfTime
        case 7:
            expectedSong = QuestSong(ocarinaSongIndex: songIndex)
        default:
            expectedSong = nil
        }

        return OcarinaTagContext(
            trigger: trigger,
            type: type,
            switchFlag: switchFlag,
            expectedSong: expectedSong,
            acceptsScarecrowStyleSong: songIndex == 0x0F
        )
    }

    func isPlayerInside(
        cylinder: SceneCylinderTriggerVolume,
        roomID: Int
    ) -> Bool {
        guard
            let playerPosition = playerState?.position.simd,
            playState?.currentRoomID == roomID || playState?.currentRoomID == nil
        else {
            return false
        }

        let center = SIMD3<Float>(
            Float(cylinder.center.x),
            Float(cylinder.center.y),
            Float(cylinder.center.z)
        )
        let horizontalOffset = SIMD2<Float>(
            playerPosition.x - center.x,
            playerPosition.z - center.z
        )
        let withinRadius = simd_length(horizontalOffset) <= Float(cylinder.radius)
        let minimumY = Float(min(cylinder.minimumY ?? cylinder.center.y - 80, cylinder.maximumY ?? cylinder.center.y + 80))
        let maximumY = Float(max(cylinder.minimumY ?? cylinder.center.y - 80, cylinder.maximumY ?? cylinder.center.y + 80))

        return withinRadius && playerPosition.y >= minimumY && playerPosition.y <= maximumY
    }

    func makeSongEventFlag(
        roomID: Int,
        actorID: Int,
        params: Int,
        center: Vector3s
    ) -> DungeonEventFlagKey {
        let sceneIdentity = playState?.currentSceneIdentity ?? SceneIdentity(
            id: selectedSceneID,
            name: playState?.currentSceneName ?? loadedScene?.manifest.name ?? "Unknown"
        )
        return DungeonEventFlagKey(
            scene: sceneIdentity,
            kind: .songTriggered,
            roomID: roomID,
            actorID: actorID,
            params: params,
            positionX: Int(center.x),
            positionY: Int(center.y),
            positionZ: Int(center.z)
        )
    }
}
