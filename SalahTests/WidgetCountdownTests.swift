import Foundation
import Testing

/// The macOS desktop draws nothing at all for a widget entry whose live countdown has a fixed
/// width: `.fixedSize()`, or `.fixedSize(horizontal: true, …)`, on a `WidgetTimer` or a
/// `Text(timerInterval:)`. The whole face goes, background aside, and nothing logs an error.
/// SwiftUI renders the same face in a test or a preview, so the baselines can't catch it;
/// these tests read the widget's sources instead. A fixed height alone is fine, and so is a
/// fixed size on plain text.
///
/// The scan sees only a countdown's own modifiers. A fixed size on a view around one, such as
/// a stack that holds it or `WidgetTimer`'s own body, fixes its width too, and goes unseen.
@Suite("Widget countdowns")
struct WidgetCountdownTests {
  /// The repository root, from this file's place in the source tree.
  static let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()

  @Test func noCountdownFixesItsWidthWithItsOwnModifiers() throws {
    var scanned = 0
    var found: [String] = []
    for folder in ["Shared/WidgetUI", "SalahWidgetsExtension"] {
      let directory = Self.root.appending(path: folder)
      let names = try FileManager.default.contentsOfDirectory(
        atPath: directory.path(percentEncoded: false))
      for name in names where name.hasSuffix(".swift") {
        let source = try String(contentsOf: directory.appending(path: name), encoding: .utf8)
        scanned += 1
        found += CountdownScan.fixedWidthLines(in: source).map { "\(folder)/\(name):\($0)" }
      }
    }
    #expect(scanned >= 4)
    #expect(found.isEmpty, "A countdown with a fixed width blanks the whole widget: \(found)")
  }

  /// The scan itself, on code it should and shouldn't flag: the lines its countdowns start on.
  @Test(arguments: [
    ("WidgetTimer(hero: hero, size: 28)\n  .fixedSize()", [1]),
    ("x\nText(\n  timerInterval: a...max(a, b))\n  .lineLimit(1).fixedSize(horizontal: true)", [2]),
    ("WidgetTimer(hero: hero)\n  .overlay { Text(\"(\") }\n  .fixedSize()", [1]),
    ("WidgetTimer(hero: hero)\n  .fixedSize(horizontal: false, vertical: true)", []),
    ("WidgetTimer(hero: hero)\n  .lineLimit(1)\nText(\"9:41\").fixedSize()", []),
    ("// WidgetTimer(hero: hero).fixedSize()\nMyWidgetTimer(a: 1).fixedSize()", []),
  ])
  func theScanFlagsOnlyFixedWidthCountdowns(source: String, lines: [Int]) {
    #expect(CountdownScan.fixedWidthLines(in: source) == lines)
  }
}

/// Finds the live countdowns in Swift source whose own modifiers fix their width.
private enum CountdownScan {
  /// The line each flagged countdown starts on: a `WidgetTimer(…)` or `Text(timerInterval: …)`
  /// whose modifier chain has `.fixedSize()` or `.fixedSize(horizontal: true, …)`.
  static func fixedWidthLines(in source: String) -> [Int] {
    let code = blankingCommentsAndStrings(source)
    var lines: [Int] = []
    for start in code.indices where startsCountdown(code, at: start) {
      guard let open = code[start...].firstIndex(of: "("), var end = closing(code, from: open)
      else { continue }
      // Each link of the chain: `.name`, its arguments, a trailing closure on the same line.
      while let dot = nextCode(code, after: end), code[dot] == "." {
        var cursor = dot + 1
        while cursor < code.count, code[cursor].isLetter || code[cursor].isNumber { cursor += 1 }
        let name = String(code[(dot + 1)..<cursor])
        var arguments = ""
        if cursor < code.count, code[cursor] == "(", let close = closing(code, from: cursor) {
          arguments = String(code[(cursor + 1)..<close])
          cursor = close + 1
        }
        if let brace = nextCode(code, after: cursor - 1, sameLine: true), code[brace] == "{",
          let close = closing(code, from: brace)
        {
          cursor = close + 1
        }
        let fixesWidth =
          arguments.allSatisfy(\.isWhitespace) || arguments.contains("horizontal: true")
        if name == "fixedSize", fixesWidth {
          lines.append(code[..<start].count { $0 == "\n" } + 1)
        }
        end = cursor - 1
      }
    }
    return lines
  }

  /// Whether a countdown's call starts at `index`, and not inside a longer name.
  private static func startsCountdown(_ code: [Character], at index: Int) -> Bool {
    if index > 0, code[index - 1].isLetter || code[index - 1].isNumber { return false }
    func word(_ word: String, at position: Int) -> Bool {
      code[position...].starts(with: word)
    }
    if word("WidgetTimer(", at: index) { return true }
    guard word("Text(", at: index), let label = nextCode(code, after: index + 4) else {
      return false
    }
    return word("timerInterval:", at: label)
  }

  /// The index of the bracket that closes the one at `open`.
  private static func closing(_ code: [Character], from open: Int) -> Int? {
    let closer: Character = code[open] == "(" ? ")" : "}"
    var depth = 0
    for index in open..<code.count {
      if code[index] == code[open] { depth += 1 }
      if code[index] == closer { depth -= 1 }
      if depth == 0 { return index }
    }
    return nil
  }

  /// The next character after `index` that isn't white space, or a newline when `sameLine`.
  private static func nextCode(_ code: [Character], after index: Int, sameLine: Bool = false)
    -> Int?
  {
    var position = index + 1
    while position < code.count, code[position].isWhitespace {
      if sameLine, code[position].isNewline { return nil }
      position += 1
    }
    return position < code.count ? position : nil
  }

  /// The source with comments and string literals turned into spaces, newlines kept, so
  /// their text neither matches nor unbalances the brackets.
  private static func blankingCommentsAndStrings(_ source: String) -> [Character] {
    var code = Array(source)
    var index = 0
    func blank(until end: Int) {
      while index < min(end, code.count) {
        if !code[index].isNewline { code[index] = " " }
        index += 1
      }
    }
    while index < code.count {
      let rest = code[index...]
      if rest.starts(with: "//") {
        blank(until: code[index...].firstIndex(where: \.isNewline) ?? code.count)
      } else if rest.starts(with: "/*") {
        let close = code.indices.dropFirst(index + 2).first { code[$0...].starts(with: "*/") }
        blank(until: (close ?? code.count) + 2)
      } else if code[index] == "\"" {
        let quote = rest.starts(with: "\"\"\"") ? "\"\"\"" : "\""
        var end = index + quote.count
        while end < code.count, !code[end...].starts(with: quote) {
          end += code[end] == "\\" ? 2 : 1
        }
        blank(until: end + quote.count)
      } else {
        index += 1
      }
    }
    return code
  }
}
