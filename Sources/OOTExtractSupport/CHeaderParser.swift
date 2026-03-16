import Foundation

struct CMacroInvocation: Sendable, Equatable {
    let name: String
    let arguments: [String]
    let lineNumber: Int
    let tableIndex: Int?
}

struct CIntegerDefine: Sendable, Equatable {
    let name: String
    let value: Int
    let lineNumber: Int
}

struct CHeaderParser: Sendable {
    var definedSymbols: Set<String>

    init(definedSymbols: Set<String> = []) {
        self.definedSymbols = definedSymbols
    }

    func parseMacros(at url: URL, matching macroNames: Set<String>) throws -> [CMacroInvocation] {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CHeaderParserError.unreadableFile(url.path, error)
        }

        return try parseMacros(in: text, matching: macroNames)
    }

    func parseMacros(in text: String, matching macroNames: Set<String>) throws -> [CMacroInvocation] {
        var invocations: [CMacroInvocation] = []
        var conditionalStack: [ConditionalFrame] = []

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("#") {
                try handleDirective(trimmed, lineNumber: lineNumber, stack: &conditionalStack)
                continue
            }

            guard isActive(conditionalStack) else {
                continue
            }

            let sanitized = stripTrailingLineComment(from: rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sanitized.isEmpty else {
                continue
            }

            guard let match = firstMatch(of: invocationRegex, in: sanitized) else {
                continue
            }

            let name = nsSubstring(in: sanitized, at: match.range(at: 2))
            guard macroNames.contains(name) else {
                continue
            }

            let tableIndex = parseTableIndex(nsSubstring(in: sanitized, at: match.range(at: 1)))
            let argumentText = nsSubstring(in: sanitized, at: match.range(at: 3))
            let arguments = splitArguments(argumentText)

            invocations.append(
                CMacroInvocation(
                    name: name,
                    arguments: arguments,
                    lineNumber: lineNumber,
                    tableIndex: tableIndex
                )
            )
        }

        guard conditionalStack.isEmpty else {
            throw CHeaderParserError.unterminatedConditional
        }

        return invocations
    }

    func parseIntegerDefines(at url: URL, matching predicate: (String) -> Bool) throws -> [CIntegerDefine] {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CHeaderParserError.unreadableFile(url.path, error)
        }

        return try parseIntegerDefines(in: text, matching: predicate)
    }

    func parseIntegerDefines(in text: String, matching predicate: (String) -> Bool) throws -> [CIntegerDefine] {
        var defines: [CIntegerDefine] = []
        var conditionalStack: [ConditionalFrame] = []

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.hasPrefix("#") {
                if let define = try parseIntegerDefineDirective(
                    from: trimmed,
                    lineNumber: lineNumber,
                    isActive: isActive(conditionalStack),
                    matching: predicate
                ) {
                    defines.append(define)
                    continue
                }

                try handleDirective(trimmed, lineNumber: lineNumber, stack: &conditionalStack)
            }
        }

        guard conditionalStack.isEmpty else {
            throw CHeaderParserError.unterminatedConditional
        }

        return defines
    }

    private func handleDirective(
        _ directiveLine: String,
        lineNumber: Int,
        stack: inout [ConditionalFrame]
    ) throws {
        guard let match = firstMatch(of: directiveRegex, in: directiveLine) else {
            return
        }

        let keyword = nsSubstring(in: directiveLine, at: match.range(at: 1))
        let expression = nsSubstring(in: directiveLine, at: match.range(at: 2))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch keyword {
        case "if", "ifdef", "ifndef":
            let parentActive = isActive(stack)
            let condition = evaluateCondition(keyword: keyword, expression: expression)
            let branchActive = parentActive && condition
            stack.append(
                ConditionalFrame(
                    parentActive: parentActive,
                    conditionSatisfied: condition,
                    branchActive: branchActive
                )
            )
        case "elif":
            guard var frame = stack.popLast() else {
                throw CHeaderParserError.unexpectedDirective(keyword, lineNumber)
            }
            let condition = !frame.conditionSatisfied && evaluateCondition(keyword: "if", expression: expression)
            frame.branchActive = frame.parentActive && condition
            frame.conditionSatisfied = frame.conditionSatisfied || condition
            stack.append(frame)
        case "else":
            guard var frame = stack.popLast() else {
                throw CHeaderParserError.unexpectedDirective(keyword, lineNumber)
            }
            let condition = !frame.conditionSatisfied
            frame.branchActive = frame.parentActive && condition
            frame.conditionSatisfied = true
            stack.append(frame)
        case "endif":
            guard stack.popLast() != nil else {
                throw CHeaderParserError.unexpectedDirective(keyword, lineNumber)
            }
        default:
            break
        }
    }

    private func evaluateCondition(keyword: String, expression: String) -> Bool {
        switch keyword {
        case "ifdef":
            return definedSymbols.contains(expression)
        case "ifndef":
            return !definedSymbols.contains(expression)
        default:
            let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "1" {
                return true
            }
            if trimmed == "0" || trimmed.isEmpty {
                return false
            }
            if let definedMatch = firstMatch(of: definedRegex, in: trimmed) {
                let symbol = nsSubstring(in: trimmed, at: definedMatch.range(at: 1))
                return definedSymbols.contains(symbol)
            }
            if trimmed.hasPrefix("!") {
                return !evaluateCondition(keyword: "if", expression: String(trimmed.dropFirst()))
            }
            return definedSymbols.contains(trimmed)
        }
    }

    private func splitArguments(_ text: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var nestingDepth = 0
        var inString = false
        var isEscaping = false

        for character in text {
            if inString {
                current.append(character)
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
                current.append(character)
            case "(":
                nestingDepth += 1
                current.append(character)
            case ")":
                nestingDepth = max(0, nestingDepth - 1)
                current.append(character)
            case "," where nestingDepth == 0:
                arguments.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current.removeAll(keepingCapacity: true)
            default:
                current.append(character)
            }
        }

        let finalArgument = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalArgument.isEmpty {
            arguments.append(finalArgument)
        }

        return arguments
    }

    private func stripTrailingLineComment(from line: String) -> String {
        var result = ""
        var iterator = line.makeIterator()
        var inString = false
        var isEscaping = false
        var previous: Character?

        while let character = iterator.next() {
            if inString {
                result.append(character)
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    inString = false
                }
                previous = character
                continue
            }

            if character == "\"" {
                inString = true
                result.append(character)
                previous = character
                continue
            }

            if previous == "/" && character == "/" {
                result.removeLast()
                break
            }

            result.append(character)
            previous = character
        }

        return result
    }

    private func parseTableIndex(_ rawValue: String) -> Int? {
        guard !rawValue.isEmpty else {
            return nil
        }

        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "0x", with: "", options: [.caseInsensitive])
        return Int(normalized, radix: 16)
    }

    private func parseIntegerDefineDirective(
        from line: String,
        lineNumber: Int,
        isActive: Bool,
        matching predicate: (String) -> Bool
    ) throws -> CIntegerDefine? {
        guard isActive else {
            return nil
        }

        guard let match = firstMatch(of: defineRegex, in: line) else {
            return nil
        }

        let name = nsSubstring(in: line, at: match.range(at: 1))
        guard predicate(name) else {
            return nil
        }

        let rawValue = nsSubstring(in: line, at: match.range(at: 2))
        let value = try parseIntegerLiteral(rawValue)
        return CIntegerDefine(name: name, value: value, lineNumber: lineNumber)
    }

    private func parseIntegerLiteral(_ rawValue: String) throws -> Int {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") {
            guard let value = Int(trimmed.dropFirst(2), radix: 16) else {
                throw CHeaderParserError.invalidIntegerLiteral(trimmed)
            }
            return value
        }

        guard let value = Int(trimmed) else {
            throw CHeaderParserError.invalidIntegerLiteral(trimmed)
        }
        return value
    }

    private func isActive(_ stack: [ConditionalFrame]) -> Bool {
        stack.allSatisfy(\.branchActive)
    }

    private func firstMatch(of regex: NSRegularExpression, in text: String) -> NSTextCheckingResult? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range)
    }

    private func nsSubstring(in text: String, at range: NSRange) -> String {
        guard
            range.location != NSNotFound,
            let swiftRange = Range(range, in: text)
        else {
            return ""
        }
        return String(text[swiftRange])
    }
}

private extension CHeaderParser {
    struct ConditionalFrame {
        let parentActive: Bool
        var conditionSatisfied: Bool
        var branchActive: Bool
    }

    var invocationRegex: NSRegularExpression {
        try! NSRegularExpression(
            pattern: #"^\s*(?:/\*\s*([0-9A-Fa-fx]+)\s*\*/\s*)?([A-Z0-9_]+)\((.*)\)\s*$"#,
            options: []
        )
    }

    var directiveRegex: NSRegularExpression {
        try! NSRegularExpression(
            pattern: #"^#\s*(if|ifdef|ifndef|elif|else|endif)\b(.*)$"#,
            options: []
        )
    }

    var definedRegex: NSRegularExpression {
        try! NSRegularExpression(
            pattern: #"defined\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"#,
            options: []
        )
    }

    var defineRegex: NSRegularExpression {
        try! NSRegularExpression(
            pattern: #"^#\s*define\s+([A-Za-z_][A-Za-z0-9_]*)\s+(0[xX][0-9A-Fa-f]+|\d+)\s*$"#,
            options: []
        )
    }
}

private enum CHeaderParserError: LocalizedError {
    case unreadableFile(String, Error)
    case unexpectedDirective(String, Int)
    case unterminatedConditional
    case invalidIntegerLiteral(String)

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let path, let error):
            return "Failed to read \(path): \(error.localizedDescription)"
        case .unexpectedDirective(let directive, let line):
            return "Unexpected #\(directive) at line \(line)"
        case .unterminatedConditional:
            return "Encountered unterminated preprocessor conditional"
        case .invalidIntegerLiteral(let literal):
            return "Unable to parse integer literal \(literal)"
        }
    }
}
