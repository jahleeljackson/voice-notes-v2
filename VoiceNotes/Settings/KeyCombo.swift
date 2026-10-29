import Foundation

struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var control: Bool = false
    var option: Bool = false
    var shift: Bool = false
    var command: Bool = false
    var function: Bool = false

    static let fn = KeyCombo(keyCode: 63, function: true)
    static let rightOption = KeyCombo(keyCode: 61, option: true)
    static let escape = KeyCombo(keyCode: 53)
    static let deleteLast = KeyCombo(keyCode: 51, control: true, option: true)

    var isFunctionAlone: Bool {
        keyCode == 63 && !control && !option && !shift && !command
    }

    var display: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        if function && keyCode != 63 { parts.append("Fn") }
        if option && keyCode != 58 && keyCode != 61 { parts.append("⌥") }
        parts.append(Self.name(for: keyCode))
        return parts.joined()
    }

    func matches(_ event: PhysicalKeyEvent) -> Bool {
        guard event.keyCode == keyCode else { return false }
        guard event.control == control,
              event.option == option,
              event.shift == shift,
              event.command == command else { return false }
        if isFunctionAlone {
            return event.function
        }
        return true
    }

    static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }

    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
        51: "⌫", 53: "Esc", 58: "Left ⌥", 61: "Right ⌥", 63: "Fn", 76: "Enter", 117: "⌦",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

struct ShortcutMap: Codable, Equatable {
    var push: KeyCombo
    var press: KeyCombo?
    var cancel: KeyCombo
    var delete: KeyCombo

    static let `default` = ShortcutMap(
        push: .rightOption,
        press: nil,
        cancel: .escape,
        delete: .deleteLast
    )

    var pressIsDoubleTap: Bool { press == nil }

    var pushLegend: String { "Hold \(push.display) to record" }
    var pressLegend: String {
        if let press {
            return "Press \(press.display) to start and stop"
        }
        return "Double-tap \(push.display) to start, tap again to stop"
    }
    var cancelLegend: String { "\(cancel.display) cancels" }
    var deleteLegend: String { "\(delete.display) deletes the last note" }
}

enum ShortcutAction: String, Codable, Equatable {
    case push
    case press
    case cancel
    case delete
}

struct PhysicalKeyEvent: Equatable {
    enum Kind: Equatable {
        case keyDown
        case keyUp
        case flagsChanged
    }

    var kind: Kind
    var keyCode: UInt16
    var control: Bool
    var option: Bool
    var shift: Bool
    var command: Bool
    var function: Bool
    /// Right Option, from the device-dependent flag (NX_DEVICERALTKEYMASK).
    /// The shared Option flag is also set for Left Option, so it cannot identify this key.
    var rightOption: Bool = false
    var isRepeat: Bool

    var combo: KeyCombo {
        KeyCombo(
            keyCode: keyCode,
            control: control,
            option: option,
            shift: shift,
            command: command,
            function: function || keyCode == 63
        )
    }
}
