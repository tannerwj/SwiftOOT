import Foundation
import SwiftUI
import OOTContent
import OOTCore
import OOTDataModel

enum HyruleWorldMapAreaType: String, Equatable {
    case overworld
    case town
}

struct HyruleWorldMapModel: Equatable {
    struct Polygon: Equatable {
        let points: [CGPoint]
    }

    struct PointOfInterest: Identifiable, Equatable {
        let id: String
        let title: String
        let iconName: String
        let point: CGPoint
    }

    struct DungeonEntrance: Identifiable, Equatable {
        let id: String
        let title: String
        let iconName: String
        let point: CGPoint
    }

    struct Area: Identifiable, Equatable {
        let id: String
        let title: String
        let type: HyruleWorldMapAreaType
        let frame: CGRect
        let polygons: [Polygon]
        let pointOfInterests: [PointOfInterest]
        let dungeonEntrances: [DungeonEntrance]
        let connectedAreaTitles: [String]
        let targetSceneID: Int?
        let memberSceneIDs: [Int]
        let isDiscovered: Bool
        let isCurrent: Bool

        var center: CGPoint {
            CGPoint(x: frame.midX, y: frame.midY)
        }
    }

    struct Connection: Identifiable, Equatable {
        let id: String
        let sourceAreaID: String
        let destinationAreaID: String
        let sourcePoint: CGPoint
        let destinationPoint: CGPoint
    }

    let areas: [Area]
    let connections: [Connection]
    let currentPlayerPoint: CGPoint?
    let currentAreaID: String?
    let bounds: CGRect
}

enum HyruleWorldMapModelBuilder {
    static func build(
        sceneLoader: any SceneLoading,
        availableScenes: [SceneTableEntry],
        currentScene: LoadedScene?,
        currentSceneID: Int?,
        playerState: PlayerState?,
        visitedSceneIDs: Set<Int>
    ) throws -> HyruleWorldMapModel {
        let sceneEntryByName = Dictionary(
            uniqueKeysWithValues: availableScenes.map { (sceneName(for: $0), $0) }
        )
        let entranceTable = try? sceneLoader.loadEntranceTable()
        let entranceTableByIndex = Dictionary(uniqueKeysWithValues: (entranceTable ?? []).map { ($0.index, $0) })

        var sceneCache: [Int: LoadedScene] = [:]
        var manifestCache: [Int: SceneManifest] = [:]
        if let currentScene {
            sceneCache[currentScene.manifest.id] = currentScene
            manifestCache[currentScene.manifest.id] = currentScene.manifest
        }

        func loadScene(id: Int) -> LoadedScene? {
            if let cached = sceneCache[id] {
                return cached
            }
            guard let scene = try? sceneLoader.loadScene(id: id) else {
                return nil
            }
            sceneCache[id] = scene
            manifestCache[id] = scene.manifest
            return scene
        }

        func loadManifest(id: Int) -> SceneManifest? {
            if let cached = manifestCache[id] {
                return cached
            }
            guard let manifest = try? sceneLoader.loadSceneManifest(id: id) else {
                return nil
            }
            manifestCache[id] = manifest
            return manifest
        }

        struct ResolvedArea {
            let area: HyruleWorldMapModel.Area
            let localBoundsBySceneID: [Int: CGRect]
        }

        var resolvedAreas: [ResolvedArea] = []
        for definition in HyruleWorldMapDefinition.areas {
            guard
                let primaryEntry = sceneEntryByName[definition.primarySceneName],
                let primaryScene = loadScene(id: primaryEntry.index)
            else {
                continue
            }

            let memberSceneIDs = definition.sceneNames.compactMap { sceneEntryByName[$0]?.index }
            let projection = CollisionProjectionGeometry.make(from: primaryScene.collision)
            let size = definition.worldSize(for: projection.bounds)
            let frame = CGRect(
                x: definition.center.x - (size.width / 2),
                y: definition.center.y - (size.height / 2),
                width: size.width,
                height: size.height
            )

            let polygons = projection.polygons.map { polygon in
                HyruleWorldMapModel.Polygon(
                    points: polygon.points.map { point in
                        CGPoint(
                            x: frame.minX + (point.x * frame.width),
                            y: frame.minY + (point.y * frame.height)
                        )
                    }
                )
            }

            var localBoundsBySceneID: [Int: CGRect] = [:]
            for sceneID in memberSceneIDs {
                if let scene = loadScene(id: sceneID) {
                    localBoundsBySceneID[sceneID] = CollisionProjectionGeometry.make(from: scene.collision).bounds
                }
            }

            let pointOfInterests = definition.pointOfInterests.map { pointOfInterest in
                HyruleWorldMapModel.PointOfInterest(
                    id: "\(definition.id)-poi-\(pointOfInterest.title)",
                    title: pointOfInterest.title,
                    iconName: pointOfInterest.iconName,
                    point: CGPoint(
                        x: frame.minX + (pointOfInterest.point.x * frame.width),
                        y: frame.minY + (pointOfInterest.point.y * frame.height)
                    )
                )
            }

            let isCurrent = memberSceneIDs.contains { $0 == currentSceneID }
            let isDiscovered = memberSceneIDs.contains(where: visitedSceneIDs.contains) || isCurrent
            resolvedAreas.append(
                ResolvedArea(
                    area: HyruleWorldMapModel.Area(
                        id: definition.id,
                        title: definition.title,
                        type: definition.type,
                        frame: frame,
                        polygons: polygons.isEmpty ? [rectanglePolygon(in: frame)] : polygons,
                        pointOfInterests: pointOfInterests,
                        dungeonEntrances: [],
                        connectedAreaTitles: [],
                        targetSceneID: primaryEntry.index,
                        memberSceneIDs: memberSceneIDs.sorted(),
                        isDiscovered: isDiscovered,
                        isCurrent: isCurrent
                    ),
                    localBoundsBySceneID: localBoundsBySceneID
                )
            )
        }

        // Some shared interiors (for example `shop1`) are intentionally grouped under
        // multiple overworld regions. Keep the first stable owning area instead of
        // trapping on duplicate scene IDs when building the atlas.
        let areaBySceneID = resolvedAreas.reduce(into: [Int: String]()) { partialResult, resolved in
            for sceneID in resolved.area.memberSceneIDs where partialResult[sceneID] == nil {
                partialResult[sceneID] = resolved.area.id
            }
        }
        var connectionPairs: Set<String> = []
        var connections: [HyruleWorldMapModel.Connection] = []
        var connectedAreaTitlesByAreaID: [String: Set<String>] = [:]
        var dungeonEntrancesByAreaID: [String: [HyruleWorldMapModel.DungeonEntrance]] = [:]

        for resolved in resolvedAreas {
            for sceneID in resolved.area.memberSceneIDs {
                guard let scene = loadScene(id: sceneID) else {
                    continue
                }

                for exit in scene.exits?.exits ?? [] {
                    guard
                        let entrance = entranceTableByIndex[exit.entranceIndex],
                        entrance.sceneID != sceneID
                    else {
                        continue
                    }

                    if let destinationAreaID = areaBySceneID[entrance.sceneID],
                       destinationAreaID != resolved.area.id,
                       let destinationArea = resolvedAreas.first(where: { $0.area.id == destinationAreaID })?.area {
                        let pairID = orderedPairID(resolved.area.id, destinationAreaID)
                        guard connectionPairs.insert(pairID).inserted else {
                            continue
                        }

                        connections.append(
                            HyruleWorldMapModel.Connection(
                                id: pairID,
                                sourceAreaID: resolved.area.id,
                                destinationAreaID: destinationAreaID,
                                sourcePoint: connectionAnchor(from: resolved.area.frame, toward: destinationArea.center),
                                destinationPoint: connectionAnchor(from: destinationArea.frame, toward: resolved.area.center)
                            )
                        )
                        connectedAreaTitlesByAreaID[resolved.area.id, default: []].insert(destinationArea.title)
                        connectedAreaTitlesByAreaID[destinationAreaID, default: []].insert(resolved.area.title)
                        continue
                    }

                    guard
                        let destinationManifest = loadManifest(id: entrance.sceneID),
                        dungeonSceneNameSet.contains(destinationManifest.name)
                    else {
                        continue
                    }

                    let dungeonTitle = dungeonTitleOverrides[destinationManifest.name] ??
                        destinationManifest.title ??
                        prettify(destinationManifest.name)
                    let existingLabels = Set(
                        (dungeonEntrancesByAreaID[resolved.area.id] ?? []).map(\.title)
                    )
                    guard existingLabels.contains(dungeonTitle) == false else {
                        continue
                    }

                    let index = dungeonEntrancesByAreaID[resolved.area.id, default: []].count
                    dungeonEntrancesByAreaID[resolved.area.id, default: []].append(
                        HyruleWorldMapModel.DungeonEntrance(
                            id: "\(resolved.area.id)-dungeon-\(entrance.sceneID)",
                            title: dungeonTitle,
                            iconName: "door.left.hand.open",
                            point: dungeonEntrancePoint(
                                in: resolved.area.frame,
                                index: index
                            )
                        )
                    )
                }
            }
        }

        let areas = resolvedAreas.map { resolved -> HyruleWorldMapModel.Area in
            var area = resolved.area
            area = HyruleWorldMapModel.Area(
                id: area.id,
                title: area.title,
                type: area.type,
                frame: area.frame,
                polygons: area.polygons,
                pointOfInterests: area.pointOfInterests,
                dungeonEntrances: dungeonEntrancesByAreaID[area.id, default: []],
                connectedAreaTitles: Array(connectedAreaTitlesByAreaID[area.id, default: []]).sorted(),
                targetSceneID: area.targetSceneID,
                memberSceneIDs: area.memberSceneIDs,
                isDiscovered: area.isDiscovered,
                isCurrent: area.isCurrent
            )
            return area
        }

        let currentPlayerPoint: CGPoint? = {
            guard
                let currentSceneID,
                let playerState,
                let resolved = resolvedAreas.first(where: { $0.area.memberSceneIDs.contains(currentSceneID) }),
                let localBounds = resolved.localBoundsBySceneID[currentSceneID]
            else {
                return nil
            }

            let normalized = normalize(
                CGPoint(x: CGFloat(playerState.position.x), y: CGFloat(playerState.position.z)),
                in: localBounds
            )
            return CGPoint(
                x: resolved.area.frame.minX + (normalized.x * resolved.area.frame.width),
                y: resolved.area.frame.minY + (normalized.y * resolved.area.frame.height)
            )
        }()

        let bounds = areas.map(\.frame).reduce(into: CGRect.null) { partialResult, frame in
            partialResult = partialResult.union(frame)
        }.insetBy(dx: -90, dy: -90)

        return HyruleWorldMapModel(
            areas: areas.sorted { $0.frame.midY == $1.frame.midY ? $0.frame.midX < $1.frame.midX : $0.frame.midY < $1.frame.midY },
            connections: connections,
            currentPlayerPoint: currentPlayerPoint,
            currentAreaID: areas.first(where: \.isCurrent)?.id,
            bounds: bounds.isNull ? CGRect(x: 0, y: 0, width: 1_000, height: 700) : bounds
        )
    }
}

struct HyruleWorldMapScreen: View {
    let runtime: GameRuntime
    let onSelectScene: @Sendable (Int) -> Void

    @State
    private var model: HyruleWorldMapModel?

    @State
    private var loadErrorMessage: String?

    @State
    private var selectedAreaID: String?

    @State
    private var zoom: CGFloat = 1

    @State
    private var panOffset: CGSize = .zero

    @State
    private var dragOrigin: CGSize = .zero

    @State
    private var zoomOrigin: CGFloat = 1

    var body: some View {
        VStack(spacing: 18) {
            header
            mapStage
            infoPanel
        }
        .padding(22)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.12, blue: 0.11),
                    Color(red: 0.15, green: 0.11, blue: 0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .task(id: refreshKey) {
            await loadModel()
        }
    }
}

private extension HyruleWorldMapScreen {
    var refreshKey: String {
        let visited = runtime.visitedSceneIDs.sorted().map(String.init).joined(separator: ",")
        let sceneID = runtime.playState?.currentSceneID ?? runtime.loadedScene?.manifest.id ?? runtime.selectedSceneID ?? -1
        return "\(sceneID)|\(visited)|\(runtime.availableScenes.count)"
    }

    var selectedArea: HyruleWorldMapModel.Area? {
        guard let model else {
            return nil
        }

        if let selectedAreaID, let area = model.areas.first(where: { $0.id == selectedAreaID }) {
            return area
        }

        if let currentAreaID = model.currentAreaID {
            return model.areas.first(where: { $0.id == currentAreaID })
        }

        return model.areas.first
    }

    var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hyrule Atlas")
                    .font(.system(size: 32, weight: .black, design: .serif))
                    .foregroundStyle(.white)
                Text("Scene exits, collision footprints, dungeon links, and runtime discovery stitched into one debug map.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                if let model {
                    Label("\(model.areas.count) mapped regions", systemImage: "map")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.82))
                    Label("\(runtime.visitedSceneIDs.count) discovered scenes", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
    }

    var mapStage: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.52),
                                Color(red: 0.06, green: 0.17, blue: 0.14).opacity(0.94),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let loadErrorMessage {
                    ContentUnavailableView("Map unavailable", systemImage: "exclamationmark.triangle", description: Text(loadErrorMessage))
                        .foregroundStyle(.white.opacity(0.84))
                } else if let model {
                    let transform = worldToScreenTransform(
                        worldBounds: model.bounds,
                        viewportSize: geometry.size
                    )

                    Canvas { context, _ in
                        for connection in model.connections {
                            guard
                                let sourceArea = model.areas.first(where: { $0.id == connection.sourceAreaID }),
                                let destinationArea = model.areas.first(where: { $0.id == connection.destinationAreaID })
                            else {
                                continue
                            }

                            let source = transform(connection.sourcePoint)
                            let destination = transform(connection.destinationPoint)
                            let midPoint = CGPoint(
                                x: (source.x + destination.x) / 2,
                                y: min(source.y, destination.y) - 34
                            )

                            var path = Path()
                            path.move(to: source)
                            path.addQuadCurve(to: destination, control: midPoint)
                            let lineColor = (sourceArea.isDiscovered && destinationArea.isDiscovered)
                                ? Color.white.opacity(0.48)
                                : Color.white.opacity(0.18)
                            context.stroke(path, with: .color(lineColor), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        }

                        for area in model.areas {
                            let fillColor = areaFillColor(for: area)
                            let strokeColor = area.isCurrent ? Color.white : fillColor.opacity(0.8)
                            for polygon in area.polygons {
                                var path = Path()
                                guard let first = polygon.points.first else {
                                    continue
                                }

                                path.move(to: transform(first))
                                for point in polygon.points.dropFirst() {
                                    path.addLine(to: transform(point))
                                }
                                path.closeSubpath()

                                context.fill(path, with: .color(fillColor))
                                context.stroke(
                                    path,
                                    with: .color(strokeColor.opacity(area.isDiscovered ? 0.86 : 0.34)),
                                    style: StrokeStyle(lineWidth: area.id == selectedAreaID ? 3 : 1.25, lineJoin: .round)
                                )
                            }
                        }
                    }

                    ForEach(model.areas) { area in
                        VStack(spacing: 6) {
                            Text(area.title)
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(.white.opacity(area.isDiscovered ? 0.9 : 0.45))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(area.id == selectedAreaID ? 0.44 : 0.24), in: Capsule())

                            if area.isCurrent {
                                Text("CURRENT")
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .foregroundStyle(Color(red: 0.99, green: 0.84, blue: 0.34))
                                    .tracking(0.7)
                            }
                        }
                        .position(transform(area.center))
                    }

                    ForEach(model.areas.flatMap(\.pointOfInterests)) { pointOfInterest in
                        Label(pointOfInterest.title, systemImage: pointOfInterest.iconName)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.black.opacity(0.28), in: Capsule())
                            .position(transform(pointOfInterest.point))
                    }

                    ForEach(model.areas.flatMap(\.dungeonEntrances)) { entrance in
                        VStack(spacing: 4) {
                            Image(systemName: entrance.iconName)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color(red: 0.96, green: 0.44, blue: 0.34))
                            Text(entrance.title)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        .position(transform(entrance.point))
                    }

                    if let currentPlayerPoint = model.currentPlayerPoint {
                        Circle()
                            .fill(Color(red: 1.0, green: 0.26, blue: 0.16))
                            .frame(width: 16, height: 16)
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.92), lineWidth: 2)
                            }
                            .position(transform(currentPlayerPoint))
                            .shadow(color: .white.opacity(0.24), radius: 10)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        legendRow(color: areaFillColor(for: .overworld), label: "Overworld")
                        legendRow(color: areaFillColor(for: .town), label: "Town")
                        legendRow(color: Color(red: 0.96, green: 0.44, blue: 0.34), label: "Dungeon entrance")
                        legendRow(color: Color(red: 1.0, green: 0.26, blue: 0.16), label: "Player")
                    }
                    .padding(14)
                    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        panOffset = CGSize(
                            width: dragOrigin.width + value.translation.width,
                            height: dragOrigin.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        dragOrigin = panOffset
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        zoom = (zoomOrigin * value).clamped(to: 0.75...2.6)
                    }
                    .onEnded { _ in
                        zoomOrigin = zoom
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        handleTap(at: value.location, viewportSize: geometry.size)
                    }
            )
        }
        .frame(minHeight: 520)
    }

    var infoPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectedArea?.title ?? "No area selected")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                if let selectedArea {
                    Text(selectedArea.isDiscovered ? "Discovered" : "Undiscovered")
                        .font(.caption.weight(.black))
                        .foregroundStyle(selectedArea.isDiscovered ? Color(red: 0.97, green: 0.84, blue: 0.34) : .white.opacity(0.58))
                }
            }

            if let selectedArea {
                Text(areaSummary(for: selectedArea))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.74))

                infoFlowRow(title: "Connections", values: selectedArea.connectedAreaTitles)
                infoFlowRow(title: "Points of Interest", values: selectedArea.pointOfInterests.map(\.title))
                infoFlowRow(title: "Dungeon Entrances", values: selectedArea.dungeonEntrances.map(\.title))

                if let targetSceneID = selectedArea.targetSceneID {
                    HStack(spacing: 12) {
                        Button(runtime.playState == nil ? "Focus Area" : "Teleport to \(selectedArea.title)") {
                            onSelectScene(targetSceneID)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(runtime.playState == nil)

                        Text(runtime.playState == nil ? "Scene viewer mode shows info only." : "Tip: click the selected area again to teleport instantly.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
            } else {
                Text("Select a region to inspect its connectivity and debug jump target.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.74))
            }
        }
        .padding(18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }

    func loadModel() async {
        let availableScenes = runtime.availableScenes
        let sceneLoader = runtime.sceneLoader
        let currentScene = runtime.loadedScene
        let currentSceneID = runtime.playState?.currentSceneID ?? runtime.loadedScene?.manifest.id ?? runtime.selectedSceneID
        let playerState = runtime.playerState
        let visitedSceneIDs = runtime.visitedSceneIDs

        do {
            let model = try await Task.detached(priority: .userInitiated) {
                try HyruleWorldMapModelBuilder.build(
                    sceneLoader: sceneLoader,
                    availableScenes: availableScenes,
                    currentScene: currentScene,
                    currentSceneID: currentSceneID,
                    playerState: playerState,
                    visitedSceneIDs: visitedSceneIDs
                )
            }.value

            await MainActor.run {
                self.model = model
                self.loadErrorMessage = model.areas.isEmpty ? "No matching overworld scenes were available under the current content root." : nil
                if let selectedAreaID, model.areas.contains(where: { $0.id == selectedAreaID }) == false {
                    self.selectedAreaID = model.currentAreaID
                } else if self.selectedAreaID == nil {
                    self.selectedAreaID = model.currentAreaID ?? model.areas.first?.id
                }
            }
        } catch {
            await MainActor.run {
                self.model = nil
                self.loadErrorMessage = error.localizedDescription
            }
        }
    }

    func handleTap(
        at location: CGPoint,
        viewportSize: CGSize
    ) {
        guard let model else {
            return
        }

        let worldPoint = screenToWorldPoint(location, worldBounds: model.bounds, viewportSize: viewportSize)
        guard let tappedArea = hitTest(point: worldPoint, in: model) else {
            selectedAreaID = nil
            return
        }

        if runtime.playState != nil,
           tappedArea.id == selectedAreaID,
           let targetSceneID = tappedArea.targetSceneID,
           targetSceneID != runtime.playState?.currentSceneID {
            onSelectScene(targetSceneID)
        }

        selectedAreaID = tappedArea.id
    }

    func hitTest(
        point: CGPoint,
        in model: HyruleWorldMapModel
    ) -> HyruleWorldMapModel.Area? {
        for area in model.areas.reversed() {
            for polygon in area.polygons {
                var path = Path()
                guard let first = polygon.points.first else {
                    continue
                }
                path.move(to: first)
                for vertex in polygon.points.dropFirst() {
                    path.addLine(to: vertex)
                }
                path.closeSubpath()
                if path.contains(point) {
                    return area
                }
            }
        }

        return model.areas.min(by: {
            hypot($0.center.x - point.x, $0.center.y - point.y) <
                hypot($1.center.x - point.x, $1.center.y - point.y)
        })
    }

    func worldToScreenTransform(
        worldBounds: CGRect,
        viewportSize: CGSize
    ) -> (CGPoint) -> CGPoint {
        let scale = baseScale(worldBounds: worldBounds, viewportSize: viewportSize) * zoom
        let worldCenter = CGPoint(x: worldBounds.midX, y: worldBounds.midY)
        let viewCenter = CGPoint(
            x: (viewportSize.width / 2) + panOffset.width,
            y: (viewportSize.height / 2) + panOffset.height
        )

        return { point in
            CGPoint(
                x: viewCenter.x + ((point.x - worldCenter.x) * scale),
                y: viewCenter.y + ((point.y - worldCenter.y) * scale)
            )
        }
    }

    func screenToWorldPoint(
        _ point: CGPoint,
        worldBounds: CGRect,
        viewportSize: CGSize
    ) -> CGPoint {
        let scale = max(baseScale(worldBounds: worldBounds, viewportSize: viewportSize) * zoom, 0.000_1)
        let worldCenter = CGPoint(x: worldBounds.midX, y: worldBounds.midY)
        let viewCenter = CGPoint(
            x: (viewportSize.width / 2) + panOffset.width,
            y: (viewportSize.height / 2) + panOffset.height
        )

        return CGPoint(
            x: worldCenter.x + ((point.x - viewCenter.x) / scale),
            y: worldCenter.y + ((point.y - viewCenter.y) / scale)
        )
    }

    func baseScale(
        worldBounds: CGRect,
        viewportSize: CGSize
    ) -> CGFloat {
        let width = max(worldBounds.width, 1)
        let height = max(worldBounds.height, 1)
        return min(viewportSize.width / width, viewportSize.height / height) * 0.88
    }

    func infoFlowRow(
        title: String,
        values: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .tracking(0.9)

            if values.isEmpty {
                Text("None mapped")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.42))
            } else {
                HStack(spacing: 8) {
                    ForEach(values, id: \.self) { value in
                        Text(value)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.86))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.2), in: Capsule())
                    }
                }
            }
        }
    }

    func legendRow(
        color: Color,
        label: String
    ) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.82))
        }
    }

    func areaSummary(for area: HyruleWorldMapModel.Area) -> String {
        let sceneCount = area.memberSceneIDs.count
        let sceneLabel = sceneCount == 1 ? "scene" : "scenes"
        return "\(sceneCount) extracted \(sceneLabel), \(area.connectedAreaTitles.count) linked regions, \(area.dungeonEntrances.count) dungeon markers."
    }

    func areaFillColor(for area: HyruleWorldMapModel.Area) -> Color {
        let base = areaFillColor(for: area.type)
        if area.isDiscovered {
            return base.opacity(area.id == selectedAreaID ? 0.82 : 0.68)
        }
        return Color.black.opacity(0.42)
    }

    func areaFillColor(for type: HyruleWorldMapAreaType) -> Color {
        switch type {
        case .overworld:
            return Color(red: 0.27, green: 0.63, blue: 0.43)
        case .town:
            return Color(red: 0.54, green: 0.34, blue: 0.21)
        }
    }
}

private enum HyruleWorldMapDefinition {
    struct PointOfInterestSeed {
        let title: String
        let iconName: String
        let point: CGPoint
    }

    struct AreaSeed {
        let id: String
        let title: String
        let type: HyruleWorldMapAreaType
        let center: CGPoint
        let worldScale: CGFloat
        let primarySceneName: String
        let sceneNames: [String]
        let pointOfInterests: [PointOfInterestSeed]

        func worldSize(for localBounds: CGRect) -> CGSize {
            let aspectRatio = max(localBounds.width, 1) / max(localBounds.height, 1)
            let width = max(110, min(220, (sqrt(max(localBounds.width * localBounds.height, 1)) * worldScale) / 5.4))
            let height = width / max(aspectRatio, 0.58)
            return CGSize(width: width, height: max(78, min(180, height)))
        }
    }

    static let areas: [AreaSeed] = [
        AreaSeed(
            id: "kokiri",
            title: "Kokiri Forest",
            type: .overworld,
            center: CGPoint(x: 180, y: 360),
            worldScale: 1.25,
            primarySceneName: "spot04",
            sceneNames: ["spot04", "kokiri_shop", "link_home", "kokiri_home", "kokiri_home3", "kokiri_home4", "kokiri_home5"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Kokiri Shop", iconName: "bag.fill", point: CGPoint(x: 0.72, y: 0.48)),
                PointOfInterestSeed(title: "Link's House", iconName: "house.fill", point: CGPoint(x: 0.33, y: 0.66)),
            ]
        ),
        AreaSeed(
            id: "lost-woods",
            title: "Lost Woods",
            type: .overworld,
            center: CGPoint(x: 110, y: 250),
            worldScale: 1.02,
            primarySceneName: "spot10",
            sceneNames: ["spot10"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Target Range", iconName: "target", point: CGPoint(x: 0.46, y: 0.34)),
            ]
        ),
        AreaSeed(
            id: "hyrule-field",
            title: "Hyrule Field",
            type: .overworld,
            center: CGPoint(x: 405, y: 400),
            worldScale: 1.56,
            primarySceneName: "spot00",
            sceneNames: ["spot00"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Owl Landing", iconName: "bird.fill", point: CGPoint(x: 0.52, y: 0.24)),
            ]
        ),
        AreaSeed(
            id: "lon-lon",
            title: "Lon Lon Ranch",
            type: .town,
            center: CGPoint(x: 290, y: 270),
            worldScale: 0.88,
            primarySceneName: "spot20",
            sceneNames: ["spot20", "malon_stable", "tent"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Stables", iconName: "horse.fill", point: CGPoint(x: 0.56, y: 0.48)),
            ]
        ),
        AreaSeed(
            id: "market",
            title: "Castle Town",
            type: .town,
            center: CGPoint(x: 485, y: 180),
            worldScale: 0.9,
            primarySceneName: "market_day",
            sceneNames: ["market_day", "market_night", "market_alley", "market_alley_n", "night_shop", "face_shop", "shop1", "alley_shop", "mahouya"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Potion Shop", iconName: "cross.case.fill", point: CGPoint(x: 0.62, y: 0.58)),
                PointOfInterestSeed(title: "Treasure Box Shop", iconName: "shippingbox.fill", point: CGPoint(x: 0.42, y: 0.38)),
            ]
        ),
        AreaSeed(
            id: "castle-grounds",
            title: "Hyrule Castle",
            type: .overworld,
            center: CGPoint(x: 430, y: 110),
            worldScale: 0.92,
            primarySceneName: "spot15",
            sceneNames: ["spot15", "hairal_niwa", "hairal_niwa_n", "nakaniwa", "shrine", "shrine_n"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Great Fairy", iconName: "sparkles", point: CGPoint(x: 0.32, y: 0.3)),
            ]
        ),
        AreaSeed(
            id: "kakariko",
            title: "Kakariko Village",
            type: .town,
            center: CGPoint(x: 645, y: 250),
            worldScale: 1.05,
            primarySceneName: "spot01",
            sceneNames: ["spot01", "kakariko", "kakariko3", "impa", "labo", "souko", "hut", "shop1"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Potion Shop", iconName: "cross.case.fill", point: CGPoint(x: 0.58, y: 0.4)),
                PointOfInterestSeed(title: "Windmill", iconName: "fanblades.fill", point: CGPoint(x: 0.36, y: 0.72)),
            ]
        ),
        AreaSeed(
            id: "graveyard",
            title: "Graveyard",
            type: .overworld,
            center: CGPoint(x: 735, y: 170),
            worldScale: 0.84,
            primarySceneName: "spot02",
            sceneNames: ["spot02"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Dampe's Hut", iconName: "house.fill", point: CGPoint(x: 0.72, y: 0.4)),
            ]
        ),
        AreaSeed(
            id: "death-mountain-trail",
            title: "Death Mountain Trail",
            type: .overworld,
            center: CGPoint(x: 760, y: 330),
            worldScale: 1.02,
            primarySceneName: "spot16",
            sceneNames: ["spot16", "miharigoya"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Great Fairy", iconName: "sparkles", point: CGPoint(x: 0.42, y: 0.24)),
            ]
        ),
        AreaSeed(
            id: "goron-city",
            title: "Goron City",
            type: .town,
            center: CGPoint(x: 845, y: 410),
            worldScale: 0.84,
            primarySceneName: "spot18",
            sceneNames: ["spot18", "golon"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Shop", iconName: "bag.fill", point: CGPoint(x: 0.56, y: 0.62)),
            ]
        ),
        AreaSeed(
            id: "zora-river",
            title: "Zora River",
            type: .overworld,
            center: CGPoint(x: 660, y: 470),
            worldScale: 0.96,
            primarySceneName: "spot03",
            sceneNames: ["spot03"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Bean Seller", iconName: "leaf.fill", point: CGPoint(x: 0.58, y: 0.54)),
            ]
        ),
        AreaSeed(
            id: "zoras-domain",
            title: "Zora's Domain",
            type: .town,
            center: CGPoint(x: 805, y: 560),
            worldScale: 0.92,
            primarySceneName: "spot17",
            sceneNames: ["spot17", "zoora", "shop1"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Shop", iconName: "bag.fill", point: CGPoint(x: 0.6, y: 0.54)),
            ]
        ),
        AreaSeed(
            id: "zoras-fountain",
            title: "Zora's Fountain",
            type: .overworld,
            center: CGPoint(x: 900, y: 660),
            worldScale: 0.92,
            primarySceneName: "spot08",
            sceneNames: ["spot08"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Great Fairy", iconName: "sparkles", point: CGPoint(x: 0.32, y: 0.42)),
            ]
        ),
        AreaSeed(
            id: "lake-hylia",
            title: "Lake Hylia",
            type: .overworld,
            center: CGPoint(x: 480, y: 680),
            worldScale: 1.08,
            primarySceneName: "spot06",
            sceneNames: ["spot06", "hylia_labo"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Lakeside Lab", iconName: "flask.fill", point: CGPoint(x: 0.72, y: 0.34)),
                PointOfInterestSeed(title: "Fishing Pond", iconName: "fish.fill", point: CGPoint(x: 0.46, y: 0.64)),
            ]
        ),
        AreaSeed(
            id: "gerudo-valley",
            title: "Gerudo Valley",
            type: .overworld,
            center: CGPoint(x: 190, y: 610),
            worldScale: 0.9,
            primarySceneName: "spot09",
            sceneNames: ["spot09"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Carpenter's Tent", iconName: "hammer.fill", point: CGPoint(x: 0.34, y: 0.64)),
            ]
        ),
        AreaSeed(
            id: "gerudo-fortress",
            title: "Gerudo Fortress",
            type: .town,
            center: CGPoint(x: 100, y: 710),
            worldScale: 0.88,
            primarySceneName: "spot12",
            sceneNames: ["spot12"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Horseback Archery", iconName: "scope", point: CGPoint(x: 0.44, y: 0.54)),
            ]
        ),
        AreaSeed(
            id: "haunted-wasteland",
            title: "Haunted Wasteland",
            type: .overworld,
            center: CGPoint(x: 55, y: 840),
            worldScale: 0.96,
            primarySceneName: "spot13",
            sceneNames: ["spot13"],
            pointOfInterests: []
        ),
        AreaSeed(
            id: "desert-colossus",
            title: "Desert Colossus",
            type: .overworld,
            center: CGPoint(x: 155, y: 930),
            worldScale: 1.0,
            primarySceneName: "spot11",
            sceneNames: ["spot11"],
            pointOfInterests: [
                PointOfInterestSeed(title: "Great Fairy", iconName: "sparkles", point: CGPoint(x: 0.34, y: 0.32)),
            ]
        ),
    ]
}

private struct CollisionProjectionGeometry {
    let bounds: CGRect
    let polygons: [HyruleWorldMapModel.Polygon]

    static func make(from collision: CollisionMesh?) -> CollisionProjectionGeometry {
        guard let collision else {
            return CollisionProjectionGeometry(
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                polygons: []
            )
        }

        let projectedPolygons = collision.polygons.compactMap { polygon -> HyruleWorldMapModel.Polygon? in
            let indices = [Int(polygon.vertexA), Int(polygon.vertexB), Int(polygon.vertexC)]
            guard indices.allSatisfy(collision.vertices.indices.contains) else {
                return nil
            }

            let points = indices.map { index in
                CGPoint(
                    x: CGFloat(collision.vertices[index].x),
                    y: CGFloat(collision.vertices[index].z)
                )
            }

            guard projectedArea(points) > 1 else {
                return nil
            }

            let normal = polygon.normal
            let isFloorLike: Bool = {
                let absX = abs(Int(normal.x))
                let absY = abs(Int(normal.y))
                let absZ = abs(Int(normal.z))
                return (absX == 0 && absY == 0 && absZ == 0) || absY >= max(absX, absZ)
            }()

            return isFloorLike ? HyruleWorldMapModel.Polygon(points: points) : nil
        }

        let usablePolygons = projectedPolygons.isEmpty
            ? collision.polygons.compactMap { polygon -> HyruleWorldMapModel.Polygon? in
                let indices = [Int(polygon.vertexA), Int(polygon.vertexB), Int(polygon.vertexC)]
                guard indices.allSatisfy(collision.vertices.indices.contains) else {
                    return nil
                }
                return HyruleWorldMapModel.Polygon(
                    points: indices.map { index in
                        CGPoint(
                            x: CGFloat(collision.vertices[index].x),
                            y: CGFloat(collision.vertices[index].z)
                        )
                    }
                )
            }
            : projectedPolygons

        let normalizedBounds = projectedBounds(
            for: usablePolygons.flatMap(\.points),
            fallback: CGRect(
                x: CGFloat(collision.minimumBounds.x),
                y: CGFloat(collision.minimumBounds.z),
                width: max(CGFloat(collision.maximumBounds.x - collision.minimumBounds.x), 1),
                height: max(CGFloat(collision.maximumBounds.z - collision.minimumBounds.z), 1)
            )
        )

        let normalizedPolygons = usablePolygons.map { polygon in
            HyruleWorldMapModel.Polygon(
                points: polygon.points.map { normalize($0, in: normalizedBounds) }
            )
        }

        return CollisionProjectionGeometry(bounds: normalizedBounds, polygons: normalizedPolygons)
    }

    private static func projectedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else {
            return 0
        }

        var doubledArea: CGFloat = 0
        for index in points.indices {
            let nextIndex = (index + 1) % points.count
            doubledArea += (points[index].x * points[nextIndex].y) - (points[nextIndex].x * points[index].y)
        }
        return abs(doubledArea) / 2
    }
}

private let dungeonSceneNameSet: Set<String> = [
    "ydan",
    "ddan",
    "bdan",
    "bmori1",
    "hidan",
    "mizusin",
    "jyasinzou",
    "hakadan",
    "ganon",
    "ganontika",
    "men",
    "ice_doukutu",
]

private let dungeonTitleOverrides: [String: String] = [
    "ydan": "Deku Tree",
    "ddan": "Dodongo's Cavern",
    "bdan": "Jabu-Jabu",
    "bmori1": "Forest Temple",
    "hidan": "Fire Temple",
    "mizusin": "Water Temple",
    "jyasinzou": "Spirit Temple",
    "hakadan": "Shadow Temple",
    "ice_doukutu": "Ice Cavern",
    "men": "Bottom of the Well",
    "ganon": "Ganon's Castle",
    "ganontika": "Ganon Tower",
]

private func orderedPairID(
    _ lhs: String,
    _ rhs: String
) -> String {
    lhs < rhs ? "\(lhs)|\(rhs)" : "\(rhs)|\(lhs)"
}

private func sceneName(for entry: SceneTableEntry) -> String {
    if entry.segmentName.hasSuffix("_scene") {
        return String(entry.segmentName.dropLast("_scene".count))
    }
    return entry.segmentName
}

private func prettify(_ sceneName: String) -> String {
    sceneName
        .replacingOccurrences(of: "_", with: " ")
        .split(separator: " ")
        .map { $0.capitalized }
        .joined(separator: " ")
}

private func rectanglePolygon(in frame: CGRect) -> HyruleWorldMapModel.Polygon {
    HyruleWorldMapModel.Polygon(
        points: [
            CGPoint(x: frame.minX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.minY),
            CGPoint(x: frame.maxX, y: frame.maxY),
            CGPoint(x: frame.minX, y: frame.maxY),
        ]
    )
}

private func connectionAnchor(
    from frame: CGRect,
    toward destination: CGPoint
) -> CGPoint {
    let center = CGPoint(x: frame.midX, y: frame.midY)
    let vector = CGVector(dx: destination.x - center.x, dy: destination.y - center.y)
    let length = max(sqrt((vector.dx * vector.dx) + (vector.dy * vector.dy)), 0.001)
    let inset = min(frame.width, frame.height) * 0.38
    return CGPoint(
        x: center.x + ((vector.dx / length) * inset),
        y: center.y + ((vector.dy / length) * inset)
    )
}

private func dungeonEntrancePoint(
    in frame: CGRect,
    index: Int
) -> CGPoint {
    let spacing: CGFloat = 28
    let count = CGFloat(index)
    return CGPoint(
        x: frame.midX + ((count - floor(count / 2)) * spacing) - (CGFloat(index.isMultiple(of: 2) ? 0 : 1) * spacing * 0.5),
        y: frame.minY - 18 - (CGFloat(index % 2) * 18)
    )
}

private func projectedBounds(
    for points: [CGPoint],
    fallback: CGRect
) -> CGRect {
    guard let firstPoint = points.first else {
        return fallback
    }

    var minX = firstPoint.x
    var maxX = firstPoint.x
    var minY = firstPoint.y
    var maxY = firstPoint.y

    for point in points.dropFirst() {
        minX = min(minX, point.x)
        maxX = max(maxX, point.x)
        minY = min(minY, point.y)
        maxY = max(maxY, point.y)
    }

    return CGRect(
        x: minX,
        y: minY,
        width: max(maxX - minX, 1),
        height: max(maxY - minY, 1)
    )
}

private func normalize(
    _ point: CGPoint,
    in bounds: CGRect
) -> CGPoint {
    CGPoint(
        x: ((point.x - bounds.minX) / max(bounds.width, 1)).clamped(to: 0...1),
        y: (1 - ((point.y - bounds.minY) / max(bounds.height, 1))).clamped(to: 0...1)
    )
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
