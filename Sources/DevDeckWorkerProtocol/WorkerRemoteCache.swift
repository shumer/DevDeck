import DevDeckCore

/// Retains validators/bodies, never account clients, token stores or authorization headers.
/// The native host supplies a memory-only SHA256 credential namespace. Unscoped clients do not cache.
actor WorkerRemoteCache {
    private struct Key: Hashable {
        let provider: String
        let id: String
        let endpoint: String
        let scope: String
    }
    private var transports: [Key: APITransport] = [:]
    private var order: [Key] = []
    func transport(account: WorkerRemoteAccount, provider: String, http: any HTTPClient) -> APITransport {
        guard let scope = account.cacheScope, account.token != nil else { return APITransport(client: http) }
        let key = Key(provider: provider, id: account.id, endpoint: account.endpoint, scope: scope)
        if let existing = transports[key] { return existing }
        if order.count >= 64 { transports.removeValue(forKey: order.removeFirst()) }
        let value = APITransport(client: http)
        transports[key] = value; order.append(key)
        return value
    }
    func invalidate(account: WorkerRemoteAccount, provider: String) {
        for key in order where key.provider == provider && key.id == account.id && key.endpoint == account.endpoint {
            transports.removeValue(forKey: key)
        }
        order.removeAll { $0.provider == provider && $0.id == account.id && $0.endpoint == account.endpoint }
    }
}
