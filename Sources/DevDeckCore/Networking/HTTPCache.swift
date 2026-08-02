import Foundation

/// Validator + body storage for conditional requests.
///
/// A 304 answer does not count against GitHub's hourly budget, so polling every minute is
/// only affordable if every GET carries the previous `ETag`.
public actor HTTPCache {
    public struct Entry: Sendable, Equatable {
        public var etag: String?
        public var lastModified: String?
        public var body: Data

        public init(etag: String?, lastModified: String?, body: Data) {
            self.etag = etag
            self.lastModified = lastModified
            self.body = body
        }
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    public func entry(for key: String) -> Entry? {
        entries[key]
    }

    /// Stores the response body when the server gave a validator to send back later.
    /// Responses without `ETag` or `Last-Modified` are not cached: there would be no way
    /// to revalidate them, and a stale body would then be served forever.
    public func store(_ response: HTTPResponse, for key: String) {
        let etag = response.header("etag")
        let lastModified = response.header("last-modified")
        guard etag != nil || lastModified != nil else {
            entries.removeValue(forKey: key)
            return
        }
        entries[key] = Entry(etag: etag, lastModified: lastModified, body: response.body)
    }

    public func remove(_ key: String) {
        entries.removeValue(forKey: key)
    }

    public func removeAll() {
        entries.removeAll()
    }

    /// Adds the validators for `request.cacheKey`, if any are known.
    public func conditionalRequest(from request: HTTPRequest) -> HTTPRequest {
        guard let key = request.cacheKey, let entry = entries[key] else { return request }
        var result = request
        if let etag = entry.etag { result.setHeader(etag, for: "If-None-Match") }
        if let lastModified = entry.lastModified {
            result.setHeader(lastModified, for: "If-Modified-Since")
        }
        return result
    }
}
