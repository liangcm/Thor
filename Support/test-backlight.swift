import Foundation

// Exercise the production event transformer without posting any events to macOS.
let source = try String(contentsOfFile: "Thor/ShortcutMonitor.swift", encoding: .utf8)
let start = source.range(of: "enum KeyboardBacklightShortcut {")!.lowerBound
let end = source.range(of: "enum AccessibilityPermission {")!.lowerBound
let tests = #"""
func checkKey(_ key: UInt16, _ flags: CGEventFlags, _ down: Bool, _ expected: Int?) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)!
    event.flags = flags
    let output = KeyboardBacklightShortcut.replacement(for: event, type: down ? .keyDown : .keyUp)
    if let expected = expected {
        let converted = NSEvent(cgEvent: output!)!
        assert((converted.data1 >> 16) == expected)
        assert(((converted.data1 >> 8) & 0xFF) == (down ? 0xA : 0xB))
        assert(!converted.modifierFlags.contains(.shift))
    } else { assert(output == nil) }
}
checkKey(122, .maskShift, true, 22)
checkKey(120, .maskShift, true, 21)
checkKey(120, .maskShift, false, 21)
checkKey(122, [], true, nil)
checkKey(122, [.maskControl, .maskShift], true, nil)
checkKey(122, [.maskSecondaryFn, .maskShift], true, nil)
checkKey(0, .maskShift, true, nil)
for (key, expected) in [(2, 21), (3, 22)] {
    let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: .shift,
        timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
        data1: (key << 16) | 0xA00, data2: -1)!.cgEvent!
    let output = KeyboardBacklightShortcut.replacement(for: event, type: event.type)!
    assert(NSEvent(cgEvent: output)!.data1 >> 16 == expected)
}
print("PASS: 9 backlight event transformation cases; no events posted")
"""#
let input = "import Cocoa\nimport ApplicationServices\n" + String(source[start..<end]) + tests
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
process.arguments = ["swift", "-"]
let pipe = Pipe()
process.standardInput = pipe
try process.run()
pipe.fileHandleForWriting.write(input.data(using: .utf8)!)
try pipe.fileHandleForWriting.close()
process.waitUntilExit()
exit(process.terminationStatus)
