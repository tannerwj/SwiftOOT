import SwiftUI
import OOTCore

struct PauseMenuView: View {
    let runtime: GameRuntime

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                header

                Group {
                    switch runtime.pauseMenuState.activeSubscreen {
                    case .items:
                        PauseItemsPanel(runtime: runtime)
                    case .equipment:
                        PauseEquipmentPanel(runtime: runtime)
                    case .questStatus:
                        PauseQuestStatusPanel(runtime: runtime)
                    case .map:
                        PauseMapPanel(runtime: runtime)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
            .padding(28)
            .frame(maxWidth: 980, maxHeight: 660)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.07, green: 0.08, blue: 0.12).opacity(0.96),
                        Color(red: 0.13, green: 0.17, blue: 0.16).opacity(0.98),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 34, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
            .padding(24)
        }
    }
}

private extension PauseMenuView {
    var header: some View {
        HStack(spacing: 12) {
            ForEach(PauseMenuSubscreen.allCases, id: \.self) { subscreen in
                VStack(spacing: 6) {
                    Text(subscreen.title.uppercased())
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(
                            subscreen == runtime.pauseMenuState.activeSubscreen
                                ? Color.white
                                : Color.white.opacity(0.6)
                        )
                        .tracking(0.8)

                    Capsule()
                        .fill(
                            subscreen == runtime.pauseMenuState.activeSubscreen
                                ? Color(red: 0.99, green: 0.82, blue: 0.26)
                                : Color.white.opacity(0.08)
                        )
                        .frame(height: 4)
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    var footer: some View {
        HStack(spacing: 20) {
            PauseHintChip(label: "Q / E or L / R", detail: "Change screen")
            PauseHintChip(label: "Stick / D-Pad", detail: "Move cursor")
            PauseHintChip(label: "A", detail: runtime.pauseMenuState.activeSubscreen == .equipment ? "Equip" : "Select")
            PauseHintChip(label: "1 / 2 / 3", detail: "Assign item")
            PauseHintChip(label: "Start / B", detail: "Close")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PauseItemsPanel: View {
    let runtime: GameRuntime

    private let columns = Array(repeating: GridItem(.flexible(minimum: 96), spacing: 14), count: InventoryMenuItem.gridColumnCount)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Collected Items")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Move the cursor, then press 1 / 2 / 3 to assign the selected item to a C-button slot.")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.72))
                }

                Spacer()

                PauseLoadoutSummary(runtime: runtime)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(Array(InventoryMenuItem.allCases.enumerated()), id: \.offset) { index, item in
                    let row = index / InventoryMenuItem.gridColumnCount
                    let column = index % InventoryMenuItem.gridColumnCount
                    PauseItemCell(
                        item: item,
                        isOwned: runtime.inventoryContext.owns(item),
                        isSelected: runtime.pauseMenuState.activeSubscreen == .items &&
                            runtime.pauseMenuState.itemCursor.row == row &&
                            runtime.pauseMenuState.itemCursor.column == column,
                        countLabel: runtime.inventoryContext.itemCountLabel(for: item),
                        assignedButtons: assignedButtons(for: item)
                    )
                }
            }

            if let selectedItem = runtime.selectedPauseMenuItem {
                HStack(spacing: 14) {
                    Image(systemName: selectedItem.iconName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.86, blue: 0.42))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedItem.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text(itemDetail(for: selectedItem))
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer()
                }
                .padding(16)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
    }

    private func assignedButtons(for item: InventoryMenuItem) -> [String] {
        guard let assignableItem = item.assignableItem else {
            return []
        }

        return GameplayCButton.allCases.compactMap { button in
            runtime.inventoryState.cButtonLoadout[button] == assignableItem ? button.label : nil
        }
    }

    private func itemDetail(for item: InventoryMenuItem) -> String {
        if let assignableItem = item.assignableItem {
            guard runtime.inventoryContext.owns(item) else {
                return "This slot is empty in the current save."
            }

            if let ammo = runtime.inventoryState.ammoCount(for: assignableItem) {
                return "Available now. Ammo: \(ammo)."
            }

            return "Available now."
        }

        return runtime.inventoryContext.owns(item)
            ? "Collected, but not yet assignable in gameplay."
            : "Not collected in the current save."
    }
}

private struct PauseEquipmentPanel: View {
    let runtime: GameRuntime

    var body: some View {
        HStack(spacing: 18) {
            equipmentColumn(
                title: "Swords",
                column: 0,
                entries: [.unequipSword] + PlayerSword.allCases.map { .sword($0) }
            )
            equipmentColumn(
                title: "Shields",
                column: 1,
                entries: [.unequipShield] + PlayerShield.allCases.map { .shield($0) }
            )
            equipmentColumn(
                title: "Tunics",
                column: 2,
                entries: PlayerTunic.allCases.map { .tunic($0) }
            )
            equipmentColumn(
                title: "Boots",
                column: 3,
                entries: PlayerBoots.allCases.map { .boots($0) }
            )
        }
    }

    private func equipmentColumn(
        title: String,
        column: Int,
        entries: [PauseEquipmentEntry]
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .tracking(0.8)

            ForEach(Array(entries.enumerated()), id: \.offset) { row, entry in
                let isSelected = runtime.pauseMenuState.activeSubscreen == .equipment &&
                    runtime.pauseMenuState.equipmentCursor.column == column &&
                    runtime.pauseMenuState.equipmentCursor.row == row
                PauseEquipmentCell(
                    title: entry.title,
                    subtitle: entry.subtitle,
                    isOwned: entry.isOwned(in: runtime.inventoryContext.equipment),
                    isEquipped: entry.isEquipped(in: runtime.inventoryContext.equipment),
                    isSelected: isSelected
                )
            }

            Spacer()
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct PauseQuestStatusPanel: View {
    let runtime: GameRuntime

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                PauseQuestGridCard(
                    title: "Medallions",
                    entries: QuestMedallion.allCases.map {
                        PauseQuestEntry(title: $0.title, isCollected: runtime.inventoryContext.questStatus.medallions.contains($0))
                    }
                )
                PauseQuestGridCard(
                    title: "Spiritual Stones",
                    entries: SpiritualStone.allCases.map {
                        PauseQuestEntry(title: $0.title, isCollected: runtime.inventoryContext.questStatus.stones.contains($0))
                    }
                )
            }

            HStack(alignment: .top, spacing: 18) {
                PauseQuestGridCard(
                    title: "Songs",
                    entries: QuestSong.allCases.map {
                        PauseQuestEntry(title: $0.title, isCollected: runtime.inventoryContext.questStatus.songs.contains($0))
                    }
                )

                VStack(spacing: 18) {
                    PauseCounterCard(
                        title: "Heart Pieces",
                        value: "\(runtime.inventoryContext.questStatus.heartPieceCount) / 4"
                    )
                    PauseCounterCard(
                        title: "Gold Skulltulas",
                        value: "\(runtime.inventoryState.goldSkulltulaTokenCount)"
                    )
                    PauseCounterCard(
                        title: "Heart Containers",
                        value: "\(max(1, runtime.inventoryState.maximumHealthUnits / 2))"
                    )
                }
                .frame(width: 250)
            }
        }
    }
}

private struct PauseMapPanel: View {
    let runtime: GameRuntime

    private var minimapModel: SceneMinimapModel {
        SceneMinimapModel(
            scene: runtime.loadedScene,
            currentRoomID: runtime.playState?.currentRoomID,
            playerState: runtime.playerState
        )
    }

    private var currentSceneIdentity: SceneIdentity {
        runtime.playState?.currentSceneIdentity ??
            SceneIdentity(id: runtime.selectedSceneID, name: runtime.loadedScene?.manifest.name ?? "Unknown")
    }

    private var dungeonState: DungeonInventoryState {
        runtime.inventoryState.dungeonState(for: currentSceneIdentity)
    }

    private var isDungeonContext: Bool {
        let sceneName = currentSceneIdentity.name.lowercased()
        if dungeonState.hasMap || dungeonState.hasCompass || dungeonState.hasBossKey || dungeonState.smallKeyCount > 0 {
            return true
        }

        let dungeonTokens = [
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
            "ice_doukutu",
            "men",
            "ganon_sonogo",
        ]
        return dungeonTokens.contains { sceneName.contains($0) }
    }

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text(isDungeonContext ? "Dungeon Map" : "World Map")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                if isDungeonContext {
                    PauseMinimapCard(model: minimapModel)
                } else {
                    PauseWorldMapCard(currentSceneName: currentSceneIdentity.name)
                }

                Spacer()
            }

            VStack(spacing: 16) {
                PauseCounterCard(title: "Area", value: currentSceneIdentity.name)
                PauseCounterCard(title: "Map", value: dungeonState.hasMap ? "Collected" : "Not Found")
                PauseCounterCard(title: "Compass", value: dungeonState.hasCompass ? "Collected" : "Not Found")
                PauseCounterCard(title: "Boss Key", value: dungeonState.hasBossKey ? "Collected" : "Not Found")
                PauseCounterCard(title: "Small Keys", value: "\(dungeonState.smallKeyCount)")
            }
            .frame(width: 260)
        }
    }
}

private struct PauseHintChip: View {
    let label: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.99, green: 0.84, blue: 0.34))
            Text(detail)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.06), in: Capsule())
    }
}

private struct PauseLoadoutSummary: View {
    let runtime: GameRuntime

    var body: some View {
        HStack(spacing: 10) {
            ForEach(GameplayCButton.allCases, id: \.self) { button in
                VStack(spacing: 6) {
                    Text(button.label)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                    Text(runtime.inventoryState.cButtonLoadout[button]?.rawValue.uppercased() ?? "--")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

private struct PauseItemCell: View {
    let item: InventoryMenuItem
    let isOwned: Bool
    let isSelected: Bool
    let countLabel: String?
    let assignedButtons: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: item.iconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isOwned ? Color(red: 1.0, green: 0.84, blue: 0.34) : .white.opacity(0.32))
                Spacer()
                if let countLabel {
                    Text(countLabel)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            Text(item.title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(isOwned ? .white : .white.opacity(0.4))

            if assignedButtons.isEmpty {
                Text(isOwned ? "Ready" : "Empty")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isOwned ? .white.opacity(0.62) : .white.opacity(0.28))
            } else {
                Text(assignedButtons.joined(separator: " · "))
                    .font(.caption2.weight(.black))
                    .foregroundStyle(Color(red: 0.99, green: 0.84, blue: 0.34))
            }
        }
        .padding(14)
        .frame(minHeight: 108, alignment: .topLeading)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(borderColor, lineWidth: isSelected ? 2 : 1)
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color(red: 0.19, green: 0.29, blue: 0.39)
        }
        if isOwned {
            return .white.opacity(0.06)
        }
        return .black.opacity(0.18)
    }

    private var borderColor: Color {
        isSelected ? Color(red: 1.0, green: 0.82, blue: 0.24) : .white.opacity(0.12)
    }
}

private enum PauseEquipmentEntry {
    case unequipSword
    case unequipShield
    case sword(PlayerSword)
    case shield(PlayerShield)
    case tunic(PlayerTunic)
    case boots(PlayerBoots)

    var title: String {
        switch self {
        case .unequipSword, .unequipShield:
            return "Unequip"
        case .sword(let sword):
            return sword.title
        case .shield(let shield):
            return shield.title
        case .tunic(let tunic):
            return tunic.title
        case .boots(let boots):
            return boots.title
        }
    }

    var subtitle: String {
        switch self {
        case .unequipSword, .unequipShield:
            return "Remove equipped gear"
        case .sword:
            return "B-button melee weapon"
        case .shield:
            return "Guard and defense"
        case .tunic:
            return "Current clothing"
        case .boots:
            return "Movement modifier"
        }
    }

    func isOwned(in equipment: EquipmentCollection) -> Bool {
        switch self {
        case .unequipSword, .unequipShield:
            return true
        case .sword(let sword):
            return equipment.ownedSwords.contains(sword)
        case .shield(let shield):
            return equipment.ownedShields.contains(shield)
        case .tunic(let tunic):
            return equipment.ownedTunics.contains(tunic)
        case .boots(let boots):
            return equipment.ownedBoots.contains(boots)
        }
    }

    func isEquipped(in equipment: EquipmentCollection) -> Bool {
        switch self {
        case .unequipSword:
            return equipment.equippedSword == nil
        case .unequipShield:
            return equipment.equippedShield == nil
        case .sword(let sword):
            return equipment.equippedSword == sword
        case .shield(let shield):
            return equipment.equippedShield == shield
        case .tunic(let tunic):
            return equipment.equippedTunic == tunic
        case .boots(let boots):
            return equipment.equippedBoots == boots
        }
    }
}

private struct PauseEquipmentCell: View {
    let title: String
    let subtitle: String
    let isOwned: Bool
    let isEquipped: Bool
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isOwned ? .white : .white.opacity(0.4))
                Spacer()
                if isEquipped {
                    Text("EQUIPPED")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(Color(red: 0.99, green: 0.84, blue: 0.34))
                }
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(isOwned ? 0.62 : 0.32))
        }
        .padding(14)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? Color(red: 1.0, green: 0.82, blue: 0.24) : .white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color(red: 0.19, green: 0.29, blue: 0.39)
        }
        if isEquipped {
            return Color(red: 0.17, green: 0.23, blue: 0.17)
        }
        return .white.opacity(0.05)
    }
}

private struct PauseQuestEntry {
    let title: String
    let isCollected: Bool
}

private struct PauseQuestGridCard: View {
    let title: String
    let entries: [PauseQuestEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .tracking(0.8)

            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack {
                    Circle()
                        .fill(entry.isCollected ? Color(red: 0.99, green: 0.84, blue: 0.34) : .white.opacity(0.16))
                        .frame(width: 12, height: 12)
                    Text(entry.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(entry.isCollected ? .white : .white.opacity(0.45))
                    Spacer()
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct PauseCounterCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
                .tracking(0.8)
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct PauseMinimapCard: View {
    let model: SceneMinimapModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.sceneTitle)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            if let roomLabel = model.roomLabel {
                Text(roomLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.62))
            }

            GeometryReader { geometry in
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.78), Color(red: 0.08, green: 0.18, blue: 0.17)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if model.overviewPolygons.isEmpty {
                        ContentUnavailableView("No map geometry", systemImage: "map")
                            .foregroundStyle(.white.opacity(0.48))
                    } else {
                        let mapBounds = geometry.frame(in: .local).insetBy(dx: 18, dy: 18)
                        ForEach(Array(model.overviewPolygons.enumerated()), id: \.offset) { index, polygon in
                            pauseMapPolygonPath(polygon, in: mapBounds)
                                .fill(
                                    index.isMultiple(of: 2)
                                        ? Color(red: 0.29, green: 0.71, blue: 0.58).opacity(0.34)
                                        : Color(red: 0.18, green: 0.52, blue: 0.42).opacity(0.24)
                                )
                            pauseMapPolygonPath(polygon, in: mapBounds)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        }

                        if let playerPoint = model.playerPoint {
                            Circle()
                                .fill(Color(red: 1.0, green: 0.26, blue: 0.16))
                                .frame(width: 12, height: 12)
                                .overlay {
                                    Circle()
                                        .strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                                }
                                .position(
                                    x: 18 + (playerPoint.x * (geometry.size.width - 36)),
                                    y: 18 + (playerPoint.y * (geometry.size.height - 36))
                                )
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct PauseWorldMapCard: View {
    let currentSceneName: String

    private let regions = [
        "Kokiri Forest",
        "Hyrule Field",
        "Death Mountain",
        "Zora's Domain",
        "Lake Hylia",
        "Gerudo Valley",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.22, blue: 0.16),
                            Color(red: 0.18, green: 0.14, blue: 0.08),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    VStack(spacing: 14) {
                        Text("HYRULE")
                            .font(.system(size: 44, weight: .black, design: .serif))
                            .foregroundStyle(.white.opacity(0.9))
                        Text("Current area: \(currentSceneName)")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }
                .frame(height: 240)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(regions, id: \.self) { region in
                    let isCurrent = currentSceneName.localizedCaseInsensitiveContains(region.replacingOccurrences(of: " ", with: "")) ||
                        currentSceneName.localizedCaseInsensitiveContains(region)
                    Text(region)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(isCurrent ? .white : .white.opacity(0.65))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            isCurrent ? Color(red: 0.21, green: 0.39, blue: 0.31) : .white.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

private func pauseMapPolygonPath(
    _ polygon: SceneMinimapModel.Polygon,
    in bounds: CGRect
) -> Path {
    Path { path in
        guard let firstPoint = polygon.points.first else {
            return
        }

        path.move(to: CGPoint(
            x: bounds.minX + (firstPoint.x * bounds.width),
            y: bounds.minY + (firstPoint.y * bounds.height)
        ))

        for point in polygon.points.dropFirst() {
            path.addLine(to: CGPoint(
                x: bounds.minX + (point.x * bounds.width),
                y: bounds.minY + (point.y * bounds.height)
            ))
        }

        path.closeSubpath()
    }
}
