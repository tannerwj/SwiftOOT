import AppKit
import GameController
import OOTCore
import OOTRender

@MainActor
final class InputManager: NSObject, GameplayInputHandling {
    private enum BoundKey: UInt16, Hashable {
        case a = 0
        case s = 1
        case d = 2
        case w = 13
        case tab = 48
        case space = 49
        case leftShift = 56
        case rightShift = 60
        case returnKey = 36
    }

    private weak var runtime: GameRuntime?
    private var pressedKeys: Set<BoundKey> = []
    private weak var activeController: GCController?

    init(runtime: GameRuntime) {
        self.runtime = runtime
        super.init()
        installControllerObservers()
        refreshController()
        publishState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func sync(frame: Int) {
        publishState()
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let key = BoundKey(rawValue: event.keyCode) else {
            return false
        }

        pressedKeys.insert(key)
        publishState()
        return true
    }

    func handleKeyUp(_ event: NSEvent) -> Bool {
        guard let key = BoundKey(rawValue: event.keyCode) else {
            return false
        }

        pressedKeys.remove(key)
        publishState()
        return true
    }

    func updateMovementReferenceYaw(_ yaw: Float?) {
        runtime?.setMovementReferenceYaw(yaw)
    }

    private func installControllerObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleControllerDidConnect),
            name: .GCControllerDidConnect,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleControllerDidDisconnect),
            name: .GCControllerDidDisconnect,
            object: nil
        )
    }

    @objc
    private func handleControllerDidConnect(_ notification: Notification) {
        refreshController()
    }

    @objc
    private func handleControllerDidDisconnect(_ notification: Notification) {
        refreshController()
    }

    private func refreshController() {
        activeController?.extendedGamepad?.valueChangedHandler = nil
        activeController = GCController.controllers().first(where: { $0.extendedGamepad != nil })
        activeController?.extendedGamepad?.valueChangedHandler = { [weak self] _, _ in
            Task { @MainActor in
                self?.publishState()
            }
        }
        publishState()
    }

    private func publishState() {
        runtime?.setControllerInput(resolveControllerState())
    }

    private func resolveControllerState() -> ControllerInputState {
        let keyboardStick = resolveKeyboardStick()
        let gamepadState = resolveGamepadState()

        let stick = keyboardStick.magnitude >= gamepadState.stick.magnitude
            ? keyboardStick
            : gamepadState.stick

        return ControllerInputState(
            stick: stick,
            aPressed: pressedKeys.contains(.space) || gamepadState.aPressed,
            bPressed: pressedKeys.contains(.leftShift) || pressedKeys.contains(.rightShift) || gamepadState.bPressed,
            zPressed: pressedKeys.contains(.tab) || gamepadState.zPressed,
            startPressed: pressedKeys.contains(.returnKey) || gamepadState.startPressed
        )
    }

    private func resolveKeyboardStick() -> StickInput {
        var x: Float = 0
        var y: Float = 0

        if pressedKeys.contains(.a) {
            x -= 1
        }
        if pressedKeys.contains(.d) {
            x += 1
        }
        if pressedKeys.contains(.s) {
            y -= 1
        }
        if pressedKeys.contains(.w) {
            y += 1
        }

        return StickInput(x: x, y: y).normalized
    }

    private func resolveGamepadState() -> ControllerInputState {
        guard let gamepad = activeController?.extendedGamepad else {
            return ControllerInputState()
        }

        var stick = StickInput(
            x: gamepad.leftThumbstick.xAxis.value,
            y: gamepad.leftThumbstick.yAxis.value
        )
        if stick.magnitude < 0.1 {
            stick = StickInput(
                x: gamepad.dpad.xAxis.value,
                y: gamepad.dpad.yAxis.value
            )
        }
        if stick.magnitude < 0.15 {
            stick = .zero
        } else {
            stick = stick.normalized
        }

        return ControllerInputState(
            stick: stick,
            aPressed: gamepad.buttonA.isPressed,
            bPressed: gamepad.buttonB.isPressed,
            zPressed: gamepad.leftTrigger.isPressed || gamepad.leftShoulder.isPressed,
            startPressed: false
        )
    }
}
