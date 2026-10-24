import Foundation

/// Uma mensagem da conversa, como o bot mostra.
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public enum Author: Sendable { case user, assistant }

    public let id: String
    public let author: Author
    public let text: String

    public init(id: String = UUID().uuidString, author: Author, text: String) {
        self.id = id
        self.author = author
        self.text = text
    }
}
