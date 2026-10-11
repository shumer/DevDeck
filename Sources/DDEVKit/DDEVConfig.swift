import Foundation

/// The bits of `.ddev/config.yaml` a card shows.
///
/// PHP and database versions are the usual answer to "it works on mine", and `ddev list`
/// does not carry them - only `ddev describe`, one process per project. The file is right
/// there in the checkout, so it is read directly, the same way the git branch and Arc's
/// `PORT` are.
public struct DDEVConfig: Sendable, Equatable {
    public var name: String?
    public var type: String?
    public var phpVersion: String?
    public var databaseType: String?
    public var databaseVersion: String?
    /// `bind_all_interfaces`: the web container's host ports listen on every interface, not
    /// only on localhost.
    public var bindAllInterfaces: Bool
    /// `host_webserver_port`: a fixed HTTP port on the host, straight to the web container.
    public var hostWebserverPort: String?
    /// `additional_fqdns`: names the router answers to as they are, `.ddev.site` not appended.
    public var additionalFQDNs: [String]

    public init(
        name: String? = nil,
        type: String? = nil,
        phpVersion: String? = nil,
        databaseType: String? = nil,
        databaseVersion: String? = nil,
        bindAllInterfaces: Bool = false,
        hostWebserverPort: String? = nil,
        additionalFQDNs: [String] = []
    ) {
        self.name = name
        self.type = type
        self.phpVersion = phpVersion
        self.databaseType = databaseType
        self.databaseVersion = databaseVersion
        self.bindAllInterfaces = bindAllInterfaces
        self.hostWebserverPort = hostWebserverPort
        self.additionalFQDNs = additionalFQDNs
    }

    /// Where a phone on the same network reaches this project, when the checkout was set up
    /// for that. Nil otherwise, and the card then has no phone button.
    ///
    /// `ddev list` cannot say: the named URL resolves to 127.0.0.1 on every device, and the
    /// router picks the project by name, so this machine's address alone reaches nothing. DDEV
    /// documents two ways out, both written in the project's own file. A fixed host port bound
    /// to every interface goes straight to the web container, past the router
    /// (`ddev config --host-webserver-port=8080 --bind-all-interfaces`). Or a name that carries
    /// this machine's address, `shop.192.168.1.20.nip.io`, which the router answers to once it
    /// listens on every interface. Plain http either way, as DDEV says: no phone trusts the
    /// development certificate. A name carrying some other address is not offered, because the
    /// machine has moved networks since and the code would point at a stranger.
    public func phoneURL(address: String?) -> URL? {
        guard let address, !address.isEmpty else { return nil }
        if bindAllInterfaces, let port = hostWebserverPort {
            return URL(string: "http://\(address):\(port)")
        }
        let dashed = address.replacingOccurrences(of: ".", with: "-")
        let carrying = additionalFQDNs.first { name in
            let parts = name.split(separator: ".").map(String.init)
            return name.contains(".\(address).") || name.hasPrefix("\(address).") || parts.contains(dashed)
        }
        return carrying.flatMap { URL(string: "http://\($0)") }
    }

    /// `mysql 8.0`, or nil when the file says nothing about a database.
    public var databaseLabel: String? {
        switch (databaseType, databaseVersion) {
        case let (type?, version?): return "\(type) \(version)"
        case let (type?, nil): return type
        default: return nil
        }
    }

    /// Parses just enough YAML for those values.
    ///
    /// A real YAML parser would be a dependency for a handful of keys, and DDEV writes this
    /// file itself in a predictable shape: top-level scalars, `database:` with two indented
    /// entries, and lists either as indented `- name` lines or inline in brackets. Anything
    /// unexpected yields nil rather than a guess.
    public static func parse(_ contents: String) -> DDEVConfig {
        var config = DDEVConfig()
        var inDatabaseBlock = false
        var inFQDNBlock = false

        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let isIndented = line.first == " " || line.first == "\t"
            if !isIndented {
                inDatabaseBlock = trimmed.hasPrefix("database:")
                inFQDNBlock = trimmed.hasPrefix("additional_fqdns:")
            }
            if inFQDNBlock, isIndented || trimmed.hasPrefix("-") {
                if trimmed.hasPrefix("-") {
                    let name = unquote(String(trimmed.dropFirst()))
                    if !name.isEmpty { config.additionalFQDNs.append(name) }
                }
                continue
            }

            guard let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[trimmed.startIndex..<separator])
            let value = unquote(String(trimmed[trimmed.index(after: separator)...]))
            guard !value.isEmpty else { continue }

            if inDatabaseBlock, isIndented {
                switch key {
                case "type": config.databaseType = value
                case "version": config.databaseVersion = value
                default: break
                }
                continue
            }

            guard !isIndented else { continue }
            switch key {
            case "name": config.name = value
            case "type": config.type = value
            case "php_version": config.phpVersion = value
            case "bind_all_interfaces": config.bindAllInterfaces = value.lowercased() == "true"
            case "host_webserver_port": config.hostWebserverPort = value
            case "additional_fqdns": config.additionalFQDNs = inlineList(value)
            default: break
            }
        }

        return config
    }

    public static func load(in folder: URL?) -> DDEVConfig {
        guard
            let folder,
            let contents = try? String(
                contentsOf: folder.appendingPathComponent(".ddev/config.yaml"),
                encoding: .utf8
            )
        else { return DDEVConfig() }
        return parse(contents)
    }

    /// Whether a folder is a DDEV project at all.
    public static func isProject(_ folder: URL?) -> Bool {
        guard let folder else { return false }
        return FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(".ddev/config.yaml").path
        )
    }

    /// `[a, "b"]` as its items; anything else is no list.
    private static func inlineList(_ value: String) -> [String] {
        guard value.hasPrefix("["), value.hasSuffix("]") else { return [] }
        return value.dropFirst().dropLast().split(separator: ",").map { unquote(String($0)) }.filter { !$0.isEmpty }
    }

    private static func unquote(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        // Strip a trailing comment only when the value is not quoted, so a URL with a hash
        // in it survives.
        if !value.hasPrefix("\""), !value.hasPrefix("'"), let hash = value.firstIndex(of: "#") {
            value = String(value[value.startIndex..<hash]).trimmingCharacters(in: .whitespaces)
        }
        if value.count >= 2,
           (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }
}
