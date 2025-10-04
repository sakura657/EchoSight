import Foundation

enum Config {
    private static func loadSecretsPlist() -> [String: Any]? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else {
            return nil
        }
        return dict
    }

    static func string(forKey key: String) -> String? {
        if let value = loadSecretsPlist()?[key] as? String, !value.isEmpty {
            return value
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty {
            return value
        }
        let env = ProcessInfo.processInfo.environment[key]
        if let value = env, !value.isEmpty {
            return value
        }
        return nil
    }

    static var openRouterAPIKey: String? {
        return string(forKey: "OPENROUTER_API_KEY")
    }
}


