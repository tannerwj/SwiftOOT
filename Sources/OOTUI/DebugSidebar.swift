import Foundation
import SwiftUI
import OOTContent
import OOTCore
import OOTDataModel
import OOTRender

public enum DebugSidebarTab: String, CaseIterable, Identifiable {
    case commentary
    case actorInspector
    case sceneInfo
    case inventory
    case renderStats
    case map

    public var id: String { rawValue }

    var title: String {
        switch self {
        case .commentary:
            return "Commentary"
        case .actorInspector:
            return "Actor"
        case .sceneInfo:
            return "Scene"
        case .inventory:
            return "Inventory"
        case .renderStats:
            return "Render"
        case .map:
            return "Map"
        }
    }

    var iconName: String {
        switch self {
        case .commentary:
            return "text.quote"
        case .actorInspector:
            return "person.text.rectangle"
        case .sceneInfo:
            return "map"
        case .inventory:
            return "square.grid.3x3.topleft.filled"
        case .renderStats:
            return "chart.xyaxis.line"
        case .map:
            return "globe.americas.fill"
        }
    }
}

private struct ActorListEntry: Identifiable, Equatable {
    let id: ObjectIdentifier
    let title: String
    let subtitle: String
    let searchText: String
}

private struct EventFlagEntry: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let searchText: String
}

private struct SongPlaybackPlan {
    let song: QuestSong
    let notes: [String]
}

public struct DebugSidebar: View {
    private let runtime: GameRuntime
    private let frameStats: SceneFrameStats
    private let updateFrameTimeMilliseconds: Double
    private let framesPerSecond: Double
    private let errorMessage: String?
    private let objectTableByID: [Int: ObjectTableEntry]
    private let onSelectScene: @Sendable (Int) -> Void

    @Binding
    private var selectedActorID: ObjectIdentifier?

    @Binding
    private var xrayOverlaySettings: XRayOverlaySettings

    @Binding
    private var renderSettings: RenderSettings

    @Binding
    private var selectedTab: DebugSidebarTab

    @State
    private var actorSearchText = ""

    @State
    private var flagSearchText = ""

    @State
    private var activeSongPlan: SongPlaybackPlan?

    @State
    private var activeSongNoteIndex = 0

    @State
    private var songPlaybackTask: Task<Void, Never>?

    public init(
        runtime: GameRuntime,
        frameStats: SceneFrameStats = SceneFrameStats(),
        updateFrameTimeMilliseconds: Double = 0,
        framesPerSecond: Double = 0,
        errorMessage: String? = nil,
        objectTableByID: [Int: ObjectTableEntry] = [:],
        selectedActorID: Binding<ObjectIdentifier?> = .constant(nil),
        xrayOverlaySettings: Binding<XRayOverlaySettings> = .constant(XRayOverlaySettings()),
        renderSettings: Binding<RenderSettings> = .constant(RenderSettings()),
        selectedTab: Binding<DebugSidebarTab> = .constant(.actorInspector),
        onSelectScene: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
        self.runtime = runtime
        self.frameStats = frameStats
        self.updateFrameTimeMilliseconds = updateFrameTimeMilliseconds
        self.framesPerSecond = framesPerSecond
        self.errorMessage = errorMessage
        self.objectTableByID = objectTableByID
        self._selectedActorID = selectedActorID
        self._xrayOverlaySettings = xrayOverlaySettings
        self._renderSettings = renderSettings
        self._selectedTab = selectedTab
        self.onSelectScene = onSelectScene
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("SwiftOOT Debugger")
                        .font(.headline.weight(.semibold))
                    Spacer()
                    Text(runtime.currentState.rawValue.capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(DebugSidebarTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Label(tab.title, systemImage: tab.iconName)
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(tab == selectedTab ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(tab == selectedTab ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let errorMessage, errorMessage.isEmpty == false {
                        InspectorSection("Status") {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    switch selectedTab {
                    case .commentary:
                        commentaryContent
                    case .actorInspector:
                        actorInspectorContent
                    case .sceneInfo:
                        sceneInfoContent
                    case .inventory:
                        inventoryContent
                    case .renderStats:
                        renderStatsContent
                    case .map:
                        mapContent
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(selectedTab.title)
        .onAppear {
            if selectedActor == nil {
                selectedActorID = actorEntries.first?.id
            }
        }
        .onDisappear {
            songPlaybackTask?.cancel()
            songPlaybackTask = nil
        }
    }
}

private extension DebugSidebar {
    var commentaryContent: some View {
        DirectorCommentarySidebarView(runtime: runtime)
    }

    var actorInspectorContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ActorListSectionView(
                actorSearchText: $actorSearchText,
                selectedActorID: $selectedActorID,
                entries: actorEntries
            )
            SelectedActorSectionView(
                actor: selectedActor,
                runtime: runtime,
                objectTableByID: objectTableByID
            )
        }
    }

    var sceneInfoContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection("Scene Selection") {
                if runtime.availableScenes.isEmpty {
                    Text("No extracted scenes were found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "Selected Scene",
                        selection: Binding(
                            get: { runtime.selectedSceneID ?? runtime.availableScenes[0].index },
                            set: onSelectScene
                        )
                    ) {
                        ForEach(runtime.availableScenes, id: \.index) { scene in
                            Text(sceneLabel(for: scene))
                                .tag(scene.index)
                        }
                    }
                    .labelsHidden()
                }
            }

            InspectorSection("Identity") {
                LabeledValueRow(label: "Scene", value: sceneTitle)
                LabeledValueRow(label: "Scene ID", value: runtime.playState?.currentSceneID.map(hex) ?? runtime.loadedScene.map { hex($0.manifest.id) } ?? "Unavailable")
                LabeledValueRow(label: "Room ID", value: runtime.playState?.currentRoomID.map(String.init) ?? "Unavailable")
                LabeledValueRow(label: "Entrance", value: runtime.playState?.currentEntranceIndex.map(String.init) ?? "Unavailable")
                LabeledValueRow(label: "Spawn", value: runtime.playState?.currentSpawnIndex.map(String.init) ?? "Unavailable")
            }

            InspectorSection("Rooms + Objects") {
                LabeledValueRow(label: "Active Rooms", value: joinedValues(runtime.playState?.activeRoomIDs.sorted().map(String.init) ?? []))
                LabeledValueRow(label: "Loaded Objects", value: "\(runtime.playState?.loadedObjectIDs.count ?? 0)")
                if let playState = runtime.playState, playState.loadedObjectIDs.isEmpty == false {
                    ForEach(playState.loadedObjectIDs, id: \.self) { objectID in
                        Text(objectSummary(for: objectID))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            InspectorSection("Environment") {
                LabeledValueRow(label: "Time of Day", value: timeOfDayLabel)
                LabeledValueRow(label: "Lighting Mode", value: runtime.loadedScene?.environment?.skybox.environmentLightingMode ?? "Default")
                LabeledValueRow(label: "Fog", value: fogSummary)
                LabeledValueRow(label: "Sky", value: colorSummary(environmentState.skyColor))
                LabeledValueRow(label: "Ambient", value: colorSummary(environmentState.ambientColor))
                LabeledValueRow(label: "Directional", value: colorSummary(environmentState.directionalLightColor))
            }

            InspectorSection("Actor Counts") {
                ForEach(ActorCategory.updatePriorityOrder, id: \.rawValue) { category in
                    LabeledValueRow(label: category.displayName, value: "\(actorCount(for: category))")
                }
            }

            InspectorSection("Frame Snapshot") {
                LabeledValueRow(label: "Draw Calls", value: "\(frameStats.drawCallCount)")
                LabeledValueRow(label: "Triangles", value: "\(frameStats.triangleCount)")
                LabeledValueRow(label: "Vertices", value: "\(frameStats.vertexCount)")
                LabeledValueRow(label: "FPS", value: numberLabel(framesPerSecond, digits: 1))
            }
        }
    }

    var inventoryContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection("Items") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(InventoryMenuItem.allCases, id: \.rawValue) { item in
                        inventoryItemTile(item)
                    }
                }
            }

            InspectorSection("Equipment") {
                LabeledValueRow(label: "Sword", value: runtime.inventoryContext.equipment.equippedSword?.title ?? "None")
                LabeledValueRow(label: "Shield", value: runtime.inventoryContext.equipment.equippedShield?.title ?? "None")
                LabeledValueRow(label: "Tunic", value: runtime.inventoryContext.equipment.equippedTunic.title)
                LabeledValueRow(label: "Boots", value: runtime.inventoryContext.equipment.equippedBoots.title)
            }

            InspectorSection("Songs") {
                if let activeSongPlan {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Now Playing: \(activeSongPlan.song.title)")
                            .font(.caption.weight(.semibold))
                        HStack(spacing: 6) {
                            ForEach(Array(activeSongPlan.notes.enumerated()), id: \.offset) { index, note in
                                Text(note)
                                    .font(.caption.monospaced())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(index == activeSongNoteIndex ? Color.accentColor.opacity(0.24) : Color.primary.opacity(0.06))
                                    )
                            }
                        }
                    }
                    .padding(.bottom, 4)
                }

                ForEach(QuestSong.allCases, id: \.rawValue) { song in
                    HStack {
                        Label(song.title, systemImage: runtime.inventoryContext.questStatus.songs.contains(song) ? "music.note" : "lock.fill")
                            .font(.caption)
                            .foregroundStyle(runtime.inventoryContext.questStatus.songs.contains(song) ? .primary : .secondary)
                        Spacer()
                        Button("Play") {
                            play(song: song)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(runtime.inventoryContext.questStatus.songs.contains(song) == false)
                    }
                }
            }

            InspectorSection("Quest Status") {
                LabeledValueRow(label: "Medallions", value: "\(runtime.inventoryContext.questStatus.medallions.count) / \(QuestMedallion.allCases.count)")
                LabeledValueRow(label: "Spiritual Stones", value: "\(runtime.inventoryContext.questStatus.stones.count) / \(SpiritualStone.allCases.count)")
                LabeledValueRow(label: "Songs", value: "\(runtime.inventoryContext.questStatus.songs.count) / \(QuestSong.allCases.count)")
                LabeledValueRow(label: "Heart Pieces", value: "\(runtime.inventoryContext.questStatus.heartPieceCount) / 4")
            }

            InspectorSection("Event Flags") {
                TextField("Search flags", text: $flagSearchText)
                    .textFieldStyle(.roundedBorder)

                if filteredEventFlags.isEmpty {
                    Text("No matching runtime flags.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredEventFlags) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.caption.weight(.semibold))
                            Text(entry.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    var renderStatsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection("Renderer") {
                LabeledValueRow(label: "Mode", value: renderSettings.presentationMode.title)
                LabeledValueRow(label: "FPS", value: numberLabel(framesPerSecond, digits: 1))
                LabeledValueRow(label: "CPU Update", value: millisecondsLabel(updateFrameTimeMilliseconds))
                LabeledValueRow(label: "CPU Render", value: millisecondsLabel(frameStats.cpuRenderTimeMilliseconds))
                LabeledValueRow(label: "Pipelines", value: "\(frameStats.pipelineStateCount)")
                LabeledValueRow(label: "Texture Memory", value: byteCountLabel(frameStats.textureMemoryBytes))
                LabeledValueRow(label: "Vertices", value: "\(frameStats.vertexCount)")
                LabeledValueRow(label: "Triangles", value: "\(frameStats.triangleCount)")
                LabeledValueRow(label: "Draw Calls", value: "\(frameStats.drawCallCount)")
                LabeledValueRow(label: "Visible Rooms", value: "\(frameStats.roomCount)")
            }

            InspectorSection("Render Settings") {
                RenderSettingsView(renderSettings: $renderSettings)
            }

            InspectorSection("Runtime") {
                LabeledValueRow(label: "Scene Viewer", value: sceneViewerStatusLabel)
                LabeledValueRow(label: "Game Frame", value: "\(runtime.gameTime.frameCount)")
                LabeledValueRow(label: "Actor Count", value: "\(runtime.actors.count)")
                LabeledValueRow(label: "Message", value: runtime.activeMessagePresentation == nil ? "Idle" : "Presenting")
            }

            InspectorSection("X-Ray") {
                Toggle(
                    "All Layers",
                    isOn: Binding(
                        get: { xrayOverlaySettings.allEnabled },
                        set: { xrayOverlaySettings.setAll($0) }
                    )
                )

                XRayOverlay(settings: $xrayOverlaySettings)
            }
        }
    }

    var mapContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSection("Map Controls") {
                Text("Use the detail pane for pan, zoom, and region selection. Click a selected region again to jump there during gameplay.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            InspectorSection("Current Focus") {
                LabeledValueRow(label: "Scene", value: sceneTitle)
                LabeledValueRow(label: "Discovered Scenes", value: "\(runtime.visitedSceneIDs.count)")
                LabeledValueRow(
                    label: "Interaction",
                    value: runtime.playState == nil ? "Inspect Only" : "Teleport Enabled"
                )
            }

            InspectorSection("Legend") {
                LegendValueRow(color: Color(red: 0.27, green: 0.63, blue: 0.43), label: "Overworld area")
                LegendValueRow(color: Color(red: 0.54, green: 0.34, blue: 0.21), label: "Town area")
                LegendValueRow(color: Color(red: 0.96, green: 0.44, blue: 0.34), label: "Dungeon entrance")
                LegendValueRow(color: Color(red: 1.0, green: 0.26, blue: 0.16), label: "Player marker")
            }
        }
    }

    func inventoryItemTile(_ item: InventoryMenuItem) -> some View {
        let isOwned = runtime.inventoryContext.owns(item)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: isOwned ? item.iconName : "lock.fill")
                    .font(.headline)
                Spacer()
                if let countLabel = runtime.inventoryContext.itemCountLabel(for: item), countLabel.isEmpty == false {
                    Text(countLabel)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOwned ? .primary : .secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isOwned ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05))
        )
    }

    var actorEntries: [ActorListEntry] {
        let query = actorSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return runtime.actors
            .map { actor in
                let typeName = String(describing: type(of: actor))
                let category = actorCategoryLabel(for: actor)
                let title = "\(typeName) • \(hex(actor.profile.id))"
                let subtitle = "\(category) • \(roomLabel(for: actor))"
                return ActorListEntry(
                    id: ObjectIdentifier(actor as AnyObject),
                    title: title,
                    subtitle: subtitle,
                    searchText: [title, subtitle, typeName, category, "\(actor.profile.id)"].joined(separator: " ").lowercased()
                )
            }
            .sorted {
                ($0.title, $0.subtitle) < ($1.title, $1.subtitle)
            }
            .filter { entry in
                query.isEmpty || entry.searchText.contains(query)
            }
    }

    var selectedActor: (any Actor)? {
        guard let selectedActorID else {
            return nil
        }

        return runtime.actors.first { actor in
            ObjectIdentifier(actor as AnyObject) == selectedActorID
        }
    }

    var filteredEventFlags: [EventFlagEntry] {
        let query = flagSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allEventFlags.filter { entry in
            query.isEmpty || entry.searchText.contains(query)
        }
    }

    var allEventFlags: [EventFlagEntry] {
        var entries: [EventFlagEntry] = runtime.inventoryState.openedTreasureFlags
            .sorted {
                ($0.scene.name, $0.flag) < ($1.scene.name, $1.flag)
            }
            .map { flag in
                let title = "Treasure • \(flag.scene.name) • Flag \(flag.flag)"
                let detail = flag.scene.id.map { "Scene \(hex($0))" } ?? "Scene ID unavailable"
                return EventFlagEntry(
                    id: "treasure-\(flag.scene.name)-\(flag.flag)",
                    title: title,
                    detail: detail,
                    searchText: [title, detail].joined(separator: " ").lowercased()
                )
            }

        entries.append(
            contentsOf: runtime.inventoryState.triggeredDungeonEventFlags
                .sorted {
                    ($0.scene.name, $0.roomID, $0.actorID, $0.kind.rawValue) < ($1.scene.name, $1.roomID, $1.actorID, $1.kind.rawValue)
                }
                .map { flag in
                    let title = "Event • \(flag.kind.rawValue) • \(flag.scene.name)"
                    let detail = "room \(flag.roomID) • actor \(hex(flag.actorID)) • params \(flag.params) • pos \(flag.positionX), \(flag.positionY), \(flag.positionZ)"
                    return EventFlagEntry(
                        id: "event-\(flag.scene.name)-\(flag.roomID)-\(flag.actorID)-\(flag.kind.rawValue)-\(flag.params)",
                        title: title,
                        detail: detail,
                        searchText: [title, detail].joined(separator: " ").lowercased()
                    )
                }
        )

        return entries
    }

    var sceneTitle: String {
        runtime.playState?.currentSceneName ??
            runtime.loadedScene?.manifest.title ??
            runtime.loadedScene?.manifest.name ??
            "Unavailable"
    }

    var environmentState: SceneEnvironmentState {
        EnvironmentRenderer(environment: runtime.loadedScene?.environment)
            .currentState(timeOfDay: runtime.gameTime.timeOfDay)
    }

    var timeOfDayLabel: String {
        let hour = Int(runtime.gameTime.timeOfDay.rounded(.down))
        let minute = Int(((runtime.gameTime.timeOfDay - Double(hour)) * 60).rounded(.down))
        return String(format: "%02d:%02d", hour, minute)
    }

    var fogSummary: String {
        "\(colorSummary(environmentState.fogColor)) • \(Int(environmentState.fogNear))-\(Int(environmentState.fogFar))"
    }

    var sceneViewerStatusLabel: String {
        switch runtime.sceneViewerState {
        case .idle:
            return "Idle"
        case .loadingContent:
            return "Loading"
        case .running:
            return "Running"
        }
    }

    func actorCount(for category: ActorCategory) -> Int {
        runtime.actors.filter { actorCategory(for: $0) == category }.count
    }

    func objectSummary(for objectID: Int) -> String {
        guard let entry = objectTableByID[objectID] else {
            return "\(hex(objectID)) • unresolved"
        }
        return "\(hex(objectID)) • \(entry.enumName)"
    }

    func objectDependencyLines(for actor: any Actor) -> [(String, String)] {
        let objectID = actor.profile.objectID
        guard objectID > 0 else {
            return [("Object", "None")]
        }

        let entry = objectTableByID[objectID]
        let loaded = runtime.playState?.loadedObjectIDs.contains(objectID) == true ? "Loaded" : "Not Loaded"
        return [
            ("Object ID", hex(objectID)),
            ("Object", entry?.enumName ?? "Unresolved"),
            ("Status", loaded),
        ]
    }

    func collisionShapeLines(for actor: any Actor) -> [String] {
        guard let combatActor = actor as? any CombatActor else {
            return []
        }

        var lines = [describe(cylinder: combatActor.hurtbox, label: "Hurtbox")]
        for (index, attack) in combatActor.activeAttacks.enumerated() {
            switch attack.collider.shape {
            case .cylinder(let cylinder):
                lines.append(describe(cylinder: cylinder, label: "Attack \(index + 1)"))
            case .tris(let tris):
                lines.append("Attack \(index + 1): tris • \(tris.triangles.count) triangle(s)")
            }
        }
        return lines
    }

    func actorStateLines(for actor: any Actor) -> [(String, String)] {
        var lines: [(String, String)] = []

        if let reflectedState = reflectedValue(named: "state", on: actor) {
            lines.append(("State", reflectedState))
        }
        if let reflectedMode = reflectedValue(named: "mode", on: actor) {
            lines.append(("Mode", reflectedMode))
        }
        if let talkActor = actor as? any TalkRequestingActor {
            lines.append(("Action", talkActor.talkPrompt))
            lines.append(("Talk Range", numberLabel(Double(talkActor.talkInteractionRange), digits: 0)))
        }
        if let skeletonActor = actor as? any SkeletonRenderableActor {
            lines.append(("Animation", skeletonActor.skeletonRenderState?.animationName ?? "None"))
            lines.append(("Object", skeletonActor.skeletonRenderState?.objectName ?? "None"))
        }
        if let combatActor = actor as? any CombatActor {
            lines.append(("Invincibility", "\(combatActor.combatState.invincibilityFramesRemaining)"))
            lines.append(("Last Hit", combatActor.combatState.lastReceivedElement?.rawValue ?? "None"))
            lines.append(("Last Block", combatActor.combatState.lastBlockedElement?.rawValue ?? "None"))
            lines.append(("Attacks", "\(combatActor.activeAttacks.count)"))
        }
        if let chest = actor as? TreasureChestActor {
            lines.append(("Opened", chest.isOpened ? "Yes" : "No"))
            lines.append(("Lid", numberLabel(Double(chest.lidOpenProgress * 100), digits: 0) + "%"))
        }

        return lines
    }

    func sourceURL(for actor: any Actor) -> URL? {
        guard
            let entry = runtime.playState?.actorTable[actor.profile.id],
            let overlayName = entry.overlayName
        else {
            return nil
        }

        return URL(string: "https://github.com/zeldaret/oot/blob/main/src/overlays/actors/ovl_\(overlayName)/z_\(overlayName.lowercased()).c")
    }

    func actorCategoryLabel(for actor: any Actor) -> String {
        if let category = actorCategory(for: actor) {
            return category.displayName
        }
        return "Unknown"
    }

    func actorCategory(for actor: any Actor) -> ActorCategory? {
        if let baseActor = actor as? BaseActor {
            return baseActor.category
        }
        return ActorCategory(rawValue: actor.profile.category)
    }

    func hitPointLabel(for actor: any Actor) -> String {
        guard let damageableActor = actor as? any DamageableActor else {
            return "Unavailable"
        }
        return "\(damageableActor.hitPoints)"
    }

    func roomLabel(for actor: any Actor) -> String {
        guard let baseActor = actor as? BaseActor else {
            return "Unavailable"
        }

        if baseActor.roomName.isEmpty == false {
            return "\(baseActor.roomName) (\(baseActor.roomID))"
        }
        return "\(baseActor.roomID)"
    }

    func floatBinding(
        for actor: any Actor,
        axis: WritableKeyPath<Vec3f, Float>
    ) -> Binding<Double> {
        Binding(
            get: {
                Double(actor.position[keyPath: axis])
            },
            set: { newValue in
                var position = actor.position
                position[keyPath: axis] = Float(newValue)
                actor.position = position
            }
        )
    }

    func rotationBinding(
        for actor: any Actor,
        axis: WritableKeyPath<Vector3s, Int16>
    ) -> Binding<Double> {
        Binding(
            get: {
                Double(actor.rotation[keyPath: axis])
            },
            set: { newValue in
                var rotation = actor.rotation
                let clamped = min(max(Int(newValue.rounded()), Int(Int16.min)), Int(Int16.max))
                rotation[keyPath: axis] = Int16(clamped)
                actor.rotation = rotation
            }
        )
    }

    func play(song: QuestSong) {
        let plan = SongPlaybackPlan(song: song, notes: song.ocarinaButtonLabels)
        songPlaybackTask?.cancel()
        activeSongPlan = plan
        activeSongNoteIndex = 0
        songPlaybackTask = Task {
            for index in plan.notes.indices {
                await MainActor.run {
                    activeSongNoteIndex = index
                }
                try? await Task.sleep(for: .milliseconds(220))
            }
        }
    }

    func reflectedValue(named name: String, on actor: any Actor) -> String? {
        var mirror: Mirror? = Mirror(reflecting: actor)

        while let currentMirror = mirror {
            for child in currentMirror.children {
                guard child.label == name else {
                    continue
                }

                let childMirror = Mirror(reflecting: child.value)
                if childMirror.displayStyle == .optional, childMirror.children.isEmpty {
                    return nil
                }

                return String(describing: child.value)
            }

            mirror = currentMirror.superclassMirror
        }

        return nil
    }

    func sceneLabel(for scene: SceneTableEntry) -> String {
        let shortName: String
        if scene.segmentName.hasSuffix("_scene") {
            shortName = String(scene.segmentName.dropLast("_scene".count))
        } else {
            shortName = scene.segmentName
        }
        return "\(shortName) • \(scene.enumName)"
    }

    func describe(cylinder: ColliderCylinder, label: String) -> String {
        "\(label): cylinder • center \(vectorSummary(cylinder.center)) • r \(numberLabel(Double(cylinder.radius), digits: 1)) • h \(numberLabel(Double(cylinder.height), digits: 1))"
    }

    func vectorSummary(_ vector: Vec3f) -> String {
        "\(numberLabel(Double(vector.x), digits: 1)), \(numberLabel(Double(vector.y), digits: 1)), \(numberLabel(Double(vector.z), digits: 1))"
    }

    func colorSummary(_ color: SIMD4<Float>) -> String {
        let r = Int((Double(color.x) * 255).rounded())
        let g = Int((Double(color.y) * 255).rounded())
        let b = Int((Double(color.z) * 255).rounded())
        return "\(r), \(g), \(b)"
    }

    func byteCountLabel(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .memory)
    }

    func millisecondsLabel(_ value: Double) -> String {
        numberLabel(value, digits: 2) + " ms"
    }

    func numberLabel(_ value: Double, digits: Int) -> String {
        value.formatted(
            .number.precision(.fractionLength(0...digits))
        )
    }

    func joinedValues(_ values: [String]) -> String {
        values.isEmpty ? "None" : values.joined(separator: ", ")
    }

    func hex(_ value: Int) -> String {
        String(format: "0x%X", value)
    }
}

private struct ActorListSectionView: View {
    @Binding var actorSearchText: String
    @Binding var selectedActorID: ObjectIdentifier?
    let entries: [ActorListEntry]

    var body: some View {
        InspectorSection("Actor List") {
            actorListContent
        }
    }

    @ViewBuilder
    var actorListContent: some View {
        TextField("Search actors", text: $actorSearchText)
            .textFieldStyle(.roundedBorder)

        if entries.isEmpty {
            Text("No active actors are available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entries) { entry in
                    ActorListEntryRow(
                        entry: entry,
                        isSelected: selectedActorID == entry.id
                    ) {
                        selectedActorID = entry.id
                    }
                }
            }
        }
    }
}

private struct ActorListEntryRow: View {
    let entry: ActorListEntry
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(entry.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct SelectedActorSectionView: View {
    let actor: (any Actor)?
    let runtime: GameRuntime
    let objectTableByID: [Int: ObjectTableEntry]

    var body: some View {
        InspectorSection("Selected Actor") {
            if let actor {
                SelectedActorDetailsView(
                    actor: actor,
                    runtime: runtime,
                    objectTableByID: objectTableByID
                )
            } else {
                Text("Choose an actor from the viewport marker or the list to inspect it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SelectedActorDetailsView: View {
    let actor: any Actor
    let runtime: GameRuntime
    let objectTableByID: [Int: ObjectTableEntry]

    var body: some View {
        let actorType = String(describing: type(of: actor))
        let stateLines = actorStateLines
        let dependencyLines = objectDependencyLines
        let collisionLines = collisionShapeLines

        return VStack(alignment: .leading, spacing: 10) {
            LabeledValueRow(label: "Type", value: actorType)
            LabeledValueRow(label: "Actor ID", value: hex(actor.profile.id))
            LabeledValueRow(label: "Category", value: actorCategoryLabel)
            LabeledValueRow(label: "HP", value: hitPointLabel)
            LabeledValueRow(label: "Room", value: roomLabel)

            if let sourceURL {
                Link(destination: sourceURL) {
                    LabeledValueRow(label: "Source", value: sourceURL.lastPathComponent, showsChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                LabeledValueRow(label: "Source", value: "Unavailable")
            }

            Divider()

            Text("Position")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VectorEditorRow(
                x: floatBinding(axis: \.x),
                y: floatBinding(axis: \.y),
                z: floatBinding(axis: \.z)
            )

            Text("Rotation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            RotationEditorRow(
                x: rotationBinding(axis: \.x),
                y: rotationBinding(axis: \.y),
                z: rotationBinding(axis: \.z)
            )

            Divider()

            Text("State")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if stateLines.isEmpty {
                Text("No additional state is exposed for this actor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(stateLines, id: \.0) { line in
                    LabeledValueRow(label: line.0, value: line.1)
                }
            }

            Divider()

            Text("Dependencies")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(dependencyLines, id: \.0) { line in
                LabeledValueRow(label: line.0, value: line.1)
            }

            Divider()

            Text("Collision")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if collisionLines.isEmpty {
                Text("No combat collision shapes are exposed for this actor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(collisionLines.indices, id: \.self) { index in
                    Text(collisionLines[index])
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                }
            }
        }
    }

    var sourceURL: URL? {
        guard
            let entry = runtime.playState?.actorTable[actor.profile.id],
            let overlayName = entry.overlayName
        else {
            return nil
        }

        return URL(string: "https://github.com/zeldaret/oot/blob/main/src/overlays/actors/ovl_\(overlayName)/z_\(overlayName.lowercased()).c")
    }

    var actorCategoryLabel: String {
        if let baseActor = actor as? BaseActor {
            return baseActor.category.displayName
        }
        return ActorCategory(rawValue: actor.profile.category)?.displayName ?? "Unknown"
    }

    var hitPointLabel: String {
        guard let damageableActor = actor as? any DamageableActor else {
            return "Unavailable"
        }
        return "\(damageableActor.hitPoints)"
    }

    var roomLabel: String {
        guard let baseActor = actor as? BaseActor else {
            return "Unavailable"
        }

        if baseActor.roomName.isEmpty == false {
            return "\(baseActor.roomName) (\(baseActor.roomID))"
        }
        return "\(baseActor.roomID)"
    }

    var objectDependencyLines: [(String, String)] {
        let objectID = actor.profile.objectID
        guard objectID > 0 else {
            return [("Object", "None")]
        }

        let entry = objectTableByID[objectID]
        let loaded = runtime.playState?.loadedObjectIDs.contains(objectID) == true ? "Loaded" : "Not Loaded"
        return [
            ("Object ID", hex(objectID)),
            ("Object", entry?.enumName ?? "Unresolved"),
            ("Status", loaded),
        ]
    }

    var collisionShapeLines: [String] {
        guard let combatActor = actor as? any CombatActor else {
            return []
        }

        var lines = [describe(cylinder: combatActor.hurtbox, label: "Hurtbox")]
        for (index, attack) in combatActor.activeAttacks.enumerated() {
            switch attack.collider.shape {
            case .cylinder(let cylinder):
                lines.append(describe(cylinder: cylinder, label: "Attack \(index + 1)"))
            case .tris(let tris):
                lines.append("Attack \(index + 1): tris • \(tris.triangles.count) triangle(s)")
            }
        }
        return lines
    }

    var actorStateLines: [(String, String)] {
        var lines: [(String, String)] = []

        if let reflectedState = reflectedValue(named: "state") {
            lines.append(("State", reflectedState))
        }
        if let reflectedMode = reflectedValue(named: "mode") {
            lines.append(("Mode", reflectedMode))
        }
        if let talkActor = actor as? any TalkRequestingActor {
            lines.append(("Action", talkActor.talkPrompt))
            lines.append(("Talk Range", numberLabel(Double(talkActor.talkInteractionRange), digits: 0)))
        }
        if let skeletonActor = actor as? any SkeletonRenderableActor {
            lines.append(("Animation", skeletonActor.skeletonRenderState?.animationName ?? "None"))
            lines.append(("Object", skeletonActor.skeletonRenderState?.objectName ?? "None"))
        }
        if let combatActor = actor as? any CombatActor {
            lines.append(("Invincibility", "\(combatActor.combatState.invincibilityFramesRemaining)"))
            lines.append(("Last Hit", combatActor.combatState.lastReceivedElement?.rawValue ?? "None"))
            lines.append(("Last Block", combatActor.combatState.lastBlockedElement?.rawValue ?? "None"))
            lines.append(("Attacks", "\(combatActor.activeAttacks.count)"))
        }
        if let chest = actor as? TreasureChestActor {
            lines.append(("Opened", chest.isOpened ? "Yes" : "No"))
            lines.append(("Lid", numberLabel(Double(chest.lidOpenProgress * 100), digits: 0) + "%"))
        }

        return lines
    }

    func floatBinding(axis: WritableKeyPath<Vec3f, Float>) -> Binding<Double> {
        Binding(
            get: {
                Double(actor.position[keyPath: axis])
            },
            set: { newValue in
                var position = actor.position
                position[keyPath: axis] = Float(newValue)
                actor.position = position
            }
        )
    }

    func rotationBinding(axis: WritableKeyPath<Vector3s, Int16>) -> Binding<Double> {
        Binding(
            get: {
                Double(actor.rotation[keyPath: axis])
            },
            set: { newValue in
                var rotation = actor.rotation
                let clamped = min(max(Int(newValue.rounded()), Int(Int16.min)), Int(Int16.max))
                rotation[keyPath: axis] = Int16(clamped)
                actor.rotation = rotation
            }
        )
    }

    func reflectedValue(named name: String) -> String? {
        var mirror: Mirror? = Mirror(reflecting: actor)

        while let currentMirror = mirror {
            for child in currentMirror.children {
                guard child.label == name else {
                    continue
                }

                let childMirror = Mirror(reflecting: child.value)
                if childMirror.displayStyle == .optional, childMirror.children.isEmpty {
                    return nil
                }

                return String(describing: child.value)
            }

            mirror = currentMirror.superclassMirror
        }

        return nil
    }

    func describe(cylinder: ColliderCylinder, label: String) -> String {
        "\(label): cylinder • center \(vectorSummary(cylinder.center)) • r \(numberLabel(Double(cylinder.radius), digits: 1)) • h \(numberLabel(Double(cylinder.height), digits: 1))"
    }

    func vectorSummary(_ vector: Vec3f) -> String {
        "\(numberLabel(Double(vector.x), digits: 1)), \(numberLabel(Double(vector.y), digits: 1)), \(numberLabel(Double(vector.z), digits: 1))"
    }

    func numberLabel(_ value: Double, digits: Int) -> String {
        value.formatted(
            .number.precision(.fractionLength(0...digits))
        )
    }

    func hex(_ value: Int) -> String {
        String(format: "0x%X", value)
    }
}

struct ActorViewportSelectionOverlay: View {
    let actors: [any Actor]
    let sceneBounds: SceneBounds
    let cameraConfiguration: GameplayCameraConfiguration?
    @Binding var selectedActorID: ObjectIdentifier?

    var body: some View {
        GeometryReader { geometry in
            if let cameraConfiguration {
                ZStack {
                    ForEach(projectedActors(in: geometry.size, configuration: cameraConfiguration), id: \.id) { projectedActor in
                        Button {
                            selectedActorID = projectedActor.id
                        } label: {
                            Circle()
                                .fill(selectedActorID == projectedActor.id ? Color.accentColor.opacity(0.95) : Color.white.opacity(0.8))
                                .frame(width: selectedActorID == projectedActor.id ? 14 : 10, height: selectedActorID == projectedActor.id ? 14 : 10)
                                .overlay(
                                    Circle()
                                        .stroke(Color.black.opacity(0.75), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .position(x: projectedActor.point.x, y: projectedActor.point.y)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(cameraConfiguration != nil)
    }

    func projectedActors(in viewportSize: CGSize, configuration: GameplayCameraConfiguration) -> [(id: ObjectIdentifier, point: CGPoint)] {
        actors.compactMap { actor in
            guard let projection = GameplayCameraProjector.project(
                worldPoint: actor.position.simd + SIMD3<Float>(0, 24, 0),
                sceneBounds: sceneBounds,
                configuration: configuration,
                viewportSize: viewportSize
            ) else {
                return nil
            }

            return (
                id: ObjectIdentifier(actor as AnyObject),
                point: CGPoint(
                    x: CGFloat(projection.viewportPoint.x),
                    y: CGFloat(projection.viewportPoint.y)
                )
            )
        }
    }
}

private struct LegendValueRow: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

private struct LabeledValueRow: View {
    let label: String
    let value: String
    var showsChevron = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
            if showsChevron {
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct VectorEditorRow: View {
    @Binding var x: Double
    @Binding var y: Double
    @Binding var z: Double

    var body: some View {
        HStack(spacing: 8) {
            numericField(title: "X", value: $x)
            numericField(title: "Y", value: $y)
            numericField(title: "Z", value: $z)
        }
    }

    func numericField(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct RotationEditorRow: View {
    @Binding var x: Double
    @Binding var y: Double
    @Binding var z: Double

    var body: some View {
        HStack(spacing: 8) {
            numericField(title: "Pitch", value: $x)
            numericField(title: "Yaw", value: $y)
            numericField(title: "Roll", value: $z)
        }
    }

    func numericField(title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
        }
    }
}

private extension ActorCategory {
    var displayName: String {
        switch self {
        case .switchActor:
            return "Switch"
        case .bg:
            return "Background"
        case .player:
            return "Player"
        case .bomb:
            return "Bomb"
        case .npc:
            return "NPC"
        case .enemy:
            return "Enemy"
        case .prop:
            return "Prop"
        case .item:
            return "Item"
        case .misc:
            return "Misc"
        case .boss:
            return "Boss"
        case .door:
            return "Door"
        case .chest:
            return "Chest"
        }
    }
}
