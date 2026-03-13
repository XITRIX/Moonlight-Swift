//
//  ControllerBridge.swift
//  Moonlight-Swift
//
//  Created by Даниил Виноградов on 13.03.2026.
//


import GameController

final class ControllerBridge {
    private var observers: [NSObjectProtocol] = []
    private var controllers: [GCController] = []
    private var controllerSlots: [ObjectIdentifier: Int16] = [:]

    func start() {
        controllers = GCController.controllers()
        controllers.forEach(bind)

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .GCControllerDidConnect,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let controller = note.object as? GCController else { return }
                self?.controllers.append(controller)
                self?.bind(controller)
            }
        )

        observers.append(
            NotificationCenter.default.addObserver(
                forName: .GCControllerDidDisconnect,
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let controller = note.object as? GCController else { return }
                self?.controllers.removeAll { $0 === controller }
                self?.controllerSlots.removeValue(forKey: ObjectIdentifier(controller))
            }
        )
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        controllers.removeAll()
        controllerSlots.removeAll()
    }

    private func bind(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        let controllerNumber = slot(for: controller)

        gamepad.valueChangedHandler = { _, _ in
            let flags = self.buttonFlags(from: gamepad)
            let lt = UInt8(clamping: Int(gamepad.leftTrigger.value * 255))
            let rt = UInt8(clamping: Int(gamepad.rightTrigger.value * 255))
            let lx = Int16(max(-32767, min(32767, Int(gamepad.leftThumbstick.xAxis.value * 32767))))
            let ly = Int16(max(-32767, min(32767, Int(gamepad.leftThumbstick.yAxis.value * 32767))))
            let rx = Int16(max(-32767, min(32767, Int(gamepad.rightThumbstick.xAxis.value * 32767))))
            let ry = Int16(max(-32767, min(32767, Int(gamepad.rightThumbstick.yAxis.value * 32767))))

            LiSendMultiControllerEvent(
                controllerNumber,
                self.activeGamepadMask(),
                flags,
                lt,
                rt,
                lx,
                ly,
                rx,
                ry
            )
        }
    }

    private func slot(for controller: GCController) -> Int16 {
        let key = ObjectIdentifier(controller)
        if let existingSlot = controllerSlots[key] {
            return existingSlot
        }

        for slot in 0..<16 {
            let candidate = Int16(slot)
            if !controllerSlots.values.contains(candidate) {
                controllerSlots[key] = candidate
                return candidate
            }
        }

        controllerSlots[key] = 0
        return 0
    }

    private func activeGamepadMask() -> Int16 {
        controllerSlots.values.reduce(into: Int16(0)) { mask, slot in
            mask |= Int16(1 << slot)
        }
    }

    private func buttonFlags(from gamepad: GCExtendedGamepad) -> Int32 {
        var flags: Int32 = 0
        if gamepad.buttonA.isPressed { flags |= A_FLAG }
        if gamepad.buttonB.isPressed { flags |= B_FLAG }
        if gamepad.buttonX.isPressed { flags |= X_FLAG }
        if gamepad.buttonY.isPressed { flags |= Y_FLAG }
        if gamepad.dpad.up.isPressed { flags |= UP_FLAG }
        if gamepad.dpad.down.isPressed { flags |= DOWN_FLAG }
        if gamepad.dpad.left.isPressed { flags |= LEFT_FLAG }
        if gamepad.dpad.right.isPressed { flags |= RIGHT_FLAG }
        if gamepad.leftShoulder.isPressed { flags |= LB_FLAG }
        if gamepad.rightShoulder.isPressed { flags |= RB_FLAG }
        if gamepad.buttonMenu.isPressed { flags |= PLAY_FLAG }
        if gamepad.buttonOptions?.isPressed == true { flags |= BACK_FLAG }
        if gamepad.leftThumbstickButton?.isPressed == true { flags |= LS_CLK_FLAG }
        if gamepad.rightThumbstickButton?.isPressed == true { flags |= RS_CLK_FLAG }
        return flags
    }
}
