import Foundation

struct GraphQLRequestBody<Variables: Encodable & Sendable>: Encodable, Sendable {
    let query: String
    let variables: Variables
}

struct GraphQLEnvelope<Payload: Decodable & Sendable>: Decodable, Sendable {
    let data: Payload?
    let errors: [GraphQLErrorEntry]?
}

struct GraphQLErrorEntry: Decodable, Sendable {
    let message: String
    let type: String?
}
