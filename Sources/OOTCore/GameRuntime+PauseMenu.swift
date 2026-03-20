import Foundation

extension GameRuntime {
    public var isPauseMenuPresented: Bool {
        pauseMenuState.isPresented
    }

    public var selectedPauseMenuItem: InventoryMenuItem? {
        InventoryMenuItem.at(
            row: pauseMenuState.itemCursor.row,
            column: pauseMenuState.itemCursor.column
        )
    }

    public func togglePauseMenu() {
        guard currentState == .gameplay, isOcarinaSessionActive == false else {
            return
        }

        var pauseState = pauseMenuState
        if pauseState.isPresented == false, isGameplayPresentationActive {
            return
        }

        pauseState.isPresented.toggle()
        pauseMenuState = pauseState
        if pauseState.isPresented {
            pauseMusicForPauseMenu()
        } else {
            resumeMusicForPauseMenu()
        }
    }

    public func cyclePauseMenuSubscreen(direction: Int) {
        guard isPauseMenuPresented else {
            return
        }

        let screens = PauseMenuSubscreen.allCases
        guard let currentIndex = screens.firstIndex(of: pauseMenuState.activeSubscreen) else {
            return
        }

        let nextIndex = (currentIndex + direction + screens.count) % screens.count
        pauseMenuState.activeSubscreen = screens[nextIndex]
        clampPauseMenuCursor()
    }

    public func movePauseMenuSelection(
        rowDelta: Int,
        columnDelta: Int
    ) {
        guard isPauseMenuPresented else {
            return
        }

        switch pauseMenuState.activeSubscreen {
        case .items:
            let rowCount = InventoryMenuItem.gridRowCount
            let columnCount = InventoryMenuItem.gridColumnCount
            pauseMenuState.itemCursor.row = wrappedIndex(
                pauseMenuState.itemCursor.row + rowDelta,
                count: rowCount
            )
            pauseMenuState.itemCursor.column = wrappedIndex(
                pauseMenuState.itemCursor.column + columnDelta,
                count: columnCount
            )
        case .equipment:
            let nextColumn = wrappedIndex(
                pauseMenuState.equipmentCursor.column + columnDelta,
                count: EquipmentMenuColumn.allCases.count
            )
            pauseMenuState.equipmentCursor.column = nextColumn
            let rowCount = equipmentOptionCount(for: nextColumn)
            pauseMenuState.equipmentCursor.row = wrappedIndex(
                pauseMenuState.equipmentCursor.row + rowDelta,
                count: rowCount
            )
        case .questStatus, .map:
            return
        }
    }

    public func activatePauseMenuSelection() {
        guard isPauseMenuPresented else {
            return
        }

        switch pauseMenuState.activeSubscreen {
        case .items:
            return
        case .equipment:
            equipSelectedPauseMenuEquipment()
        case .questStatus, .map:
            return
        }
    }

    public func assignSelectedPauseMenuItem(to button: GameplayCButton) {
        guard
            isPauseMenuPresented,
            pauseMenuState.activeSubscreen == .items,
            let selectedPauseMenuItem,
            inventoryContext.owns(selectedPauseMenuItem),
            let item = selectedPauseMenuItem.assignableItem
        else {
            return
        }

        assignItem(item, to: button)
        persistActiveSaveSlotState()
    }

    func handlePauseMenuInput(
        currentInput: ControllerInputState,
        previousInput: ControllerInputState
    ) -> Bool {
        guard isOcarinaSessionActive == false else {
            return false
        }

        let startTriggered = currentInput.startPressed && previousInput.startPressed == false

        if isPauseMenuPresented == false {
            guard startTriggered, isGameplayPresentationActive == false else {
                return false
            }

            togglePauseMenu()
            return true
        }

        if startTriggered || (currentInput.bPressed && previousInput.bPressed == false) {
            togglePauseMenu()
            return true
        }

        if currentInput.lPressed && previousInput.lPressed == false {
            cyclePauseMenuSubscreen(direction: -1)
        } else if currentInput.rPressed && previousInput.rPressed == false {
            cyclePauseMenuSubscreen(direction: 1)
        }

        let moveDelta = pauseMenuMoveDelta(
            previousStick: previousInput.stick,
            currentStick: currentInput.stick
        )
        if moveDelta.row != 0 || moveDelta.column != 0 {
            movePauseMenuSelection(
                rowDelta: moveDelta.row,
                columnDelta: moveDelta.column
            )
        }

        if currentInput.aPressed && previousInput.aPressed == false {
            activatePauseMenuSelection()
        }
        if currentInput.zPressed && previousInput.zPressed == false {
            saveCurrentGame()
        }
        if currentInput.cLeftPressed && previousInput.cLeftPressed == false {
            assignSelectedPauseMenuItem(to: .left)
        }
        if currentInput.cDownPressed && previousInput.cDownPressed == false {
            assignSelectedPauseMenuItem(to: .down)
        }
        if currentInput.cRightPressed && previousInput.cRightPressed == false {
            assignSelectedPauseMenuItem(to: .right)
        }

        return true
    }
}

private extension GameRuntime {
    enum EquipmentMenuColumn: Int, CaseIterable {
        case swords
        case shields
        case tunics
        case boots
    }

    enum EquipmentSelection {
        case sword(PlayerSword?)
        case shield(PlayerShield?)
        case tunic(PlayerTunic)
        case boots(PlayerBoots)
    }

    func clampPauseMenuCursor() {
        pauseMenuState.itemCursor.row = min(max(0, pauseMenuState.itemCursor.row), InventoryMenuItem.gridRowCount - 1)
        pauseMenuState.itemCursor.column = min(max(0, pauseMenuState.itemCursor.column), InventoryMenuItem.gridColumnCount - 1)

        let column = min(max(0, pauseMenuState.equipmentCursor.column), EquipmentMenuColumn.allCases.count - 1)
        pauseMenuState.equipmentCursor.column = column
        pauseMenuState.equipmentCursor.row = min(
            max(0, pauseMenuState.equipmentCursor.row),
            equipmentOptionCount(for: column) - 1
        )
    }

    func pauseMenuMoveDelta(
        previousStick: StickInput,
        currentStick: StickInput
    ) -> (row: Int, column: Int) {
        let threshold: Float = 0.65
        let wasNeutral = previousStick.magnitude < threshold
        let isNeutral = currentStick.magnitude < threshold

        guard wasNeutral, isNeutral == false else {
            return (0, 0)
        }

        if abs(currentStick.x) > abs(currentStick.y) {
            return (0, currentStick.x < 0 ? -1 : 1)
        }

        return (currentStick.y > 0 ? -1 : 1, 0)
    }

    func wrappedIndex(
        _ value: Int,
        count: Int
    ) -> Int {
        guard count > 0 else {
            return 0
        }

        let remainder = value % count
        return remainder >= 0 ? remainder : remainder + count
    }

    func equipmentOptionCount(for column: Int) -> Int {
        guard let menuColumn = EquipmentMenuColumn(rawValue: column) else {
            return 1
        }

        switch menuColumn {
        case .swords:
            return PlayerSword.allCases.count + 1
        case .shields:
            return PlayerShield.allCases.count + 1
        case .tunics:
            return PlayerTunic.allCases.count
        case .boots:
            return PlayerBoots.allCases.count
        }
    }

    func resolvedEquipmentSelection() -> EquipmentSelection? {
        guard let column = EquipmentMenuColumn(rawValue: pauseMenuState.equipmentCursor.column) else {
            return nil
        }

        let row = pauseMenuState.equipmentCursor.row
        switch column {
        case .swords:
            if row == 0 {
                return .sword(nil)
            }
            return PlayerSword.allCases.indices.contains(row - 1) ? .sword(PlayerSword.allCases[row - 1]) : nil
        case .shields:
            if row == 0 {
                return .shield(nil)
            }
            return PlayerShield.allCases.indices.contains(row - 1) ? .shield(PlayerShield.allCases[row - 1]) : nil
        case .tunics:
            return PlayerTunic.allCases.indices.contains(row) ? .tunic(PlayerTunic.allCases[row]) : nil
        case .boots:
            return PlayerBoots.allCases.indices.contains(row) ? .boots(PlayerBoots.allCases[row]) : nil
        }
    }

    func equipSelectedPauseMenuEquipment() {
        guard let selection = resolvedEquipmentSelection() else {
            return
        }

        switch selection {
        case .sword(let sword):
            guard sword == nil || inventoryContext.equipment.ownedSwords.contains(sword!) else {
                return
            }
            inventoryContext.equipment.equip(sword)
        case .shield(let shield):
            guard shield == nil || inventoryContext.equipment.ownedShields.contains(shield!) else {
                return
            }
            inventoryContext.equipment.equip(shield)
        case .tunic(let tunic):
            guard inventoryContext.equipment.ownedTunics.contains(tunic) else {
                return
            }
            inventoryContext.equipment.equip(tunic)
        case .boots(let boots):
            guard inventoryContext.equipment.ownedBoots.contains(boots) else {
                return
            }
            inventoryContext.equipment.equip(boots)
        }

        synchronizeHUDStateWithInventory()
        persistActiveSaveSlotState()
    }
}
