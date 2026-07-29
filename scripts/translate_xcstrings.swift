import Foundation
import Translation

private let protectedTerms = [
    "VaultBox", "iCloud", "Face ID", "Touch ID", "Wi-Fi", "PIN", "iOS"
]

private let placeholderPattern = try! NSRegularExpression(
    pattern: #"%(?:\d+\$)?[-+0 #']*\d*(?:\.\d+)?(?:hh|h|ll|l|z|t|j)?[diuoxXfFeEgGaAcCsSp@]"#
)

private func protected(_ source: String) -> (text: String, replacements: [String: String]) {
    var result = source
    var replacements: [String: String] = [:]
    var index = 0

    let range = NSRange(source.startIndex..., in: source)
    let placeholders = placeholderPattern.matches(in: source, range: range).reversed()
    for match in placeholders {
        guard let swiftRange = Range(match.range, in: result) else { continue }
        let token = "ZXQPH\(index)QXZ"
        replacements[token] = String(result[swiftRange])
        result.replaceSubrange(swiftRange, with: token)
        index += 1
    }

    for term in protectedTerms {
        guard result.contains(term) else { continue }
        let token = "ZXQTERM\(index)QXZ"
        replacements[token] = term
        result = result.replacingOccurrences(of: term, with: token)
        index += 1
    }
    return (result, replacements)
}

private func restored(_ translated: String, replacements: [String: String]) -> String {
    replacements.reduce(translated) { value, replacement in
        value.replacingOccurrences(of: replacement.key, with: replacement.value)
    }
}

@main
struct TranslateXCStrings {
    static func main() async throws {
        setbuf(stdout, nil)
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "TranslateXCStrings", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Usage: translate-xcstrings <catalog> <locale>"
            ])
        }

        let catalogURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let locale = CommandLine.arguments[2]
        let data = try Data(contentsOf: catalogURL)
        guard var catalog = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var strings = catalog["strings"] as? [String: Any] else {
            throw NSError(domain: "TranslateXCStrings", code: 2)
        }

        let keys = strings.keys.sorted().filter { key in
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let pendingKeys = keys.filter { key in
            guard let entry = strings[key] as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any],
                  let localization = localizations[locale] as? [String: Any],
                  let stringUnit = localization["stringUnit"] as? [String: Any],
                  stringUnit["state"] as? String == "translated",
                  stringUnit["value"] as? String != nil else {
                return true
            }
            return false
        }
        let protectedValues = Dictionary(uniqueKeysWithValues: pendingKeys.map { ($0, protected($0)) })
        let passthroughKeys = pendingKeys.filter { key in
            let withoutPlaceholders = placeholderPattern.stringByReplacingMatches(
                in: key,
                range: NSRange(key.startIndex..., in: key),
                withTemplate: ""
            )
            return withoutPlaceholders.range(of: "[A-Za-z]", options: .regularExpression) == nil
        }
        let translatedKeys = pendingKeys.filter { !passthroughKeys.contains($0) }
        let source = Locale.Language(identifier: "en")
        let target = Locale.Language(identifier: locale)
        for key in passthroughKeys {
            var entry = strings[key] as? [String: Any] ?? [:]
            var localizations = entry["localizations"] as? [String: Any] ?? [:]
            localizations[locale] = [
                "stringUnit": ["state": "translated", "value": key]
            ]
            entry["localizations"] = localizations
            strings[key] = entry
        }
        var translatedCount = 0
        let session = TranslationSession(installedSource: source, target: target)
        for key in translatedKeys {
            guard let protectedValue = protectedValues[key] else { continue }
            let response = try await session.translate(protectedValue.text)
            let value = restored(response.targetText, replacements: protectedValue.replacements)
            var entry = strings[key] as? [String: Any] ?? [:]
            var localizations = entry["localizations"] as? [String: Any] ?? [:]
            localizations[locale] = [
                "stringUnit": ["state": "translated", "value": value]
            ]
            entry["localizations"] = localizations
            strings[key] = entry
            translatedCount += 1
            if translatedCount.isMultiple(of: 25) {
                print("\(locale): \(translatedCount)/\(translatedKeys.count)")
            }
        }

        catalog["strings"] = strings
        let output = try JSONSerialization.data(
            withJSONObject: catalog,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try output.write(to: catalogURL, options: .atomic)
        print("Translated \(translatedCount) keys into \(locale)")
    }
}
