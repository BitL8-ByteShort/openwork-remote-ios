import Foundation

public struct ModelSelection: Codable, Sendable, Equatable {
  public let providerId: String
  public let modelId: String
  public let variant: String?
  public init(providerId: String, modelId: String, variant: String?) {
    self.providerId = providerId; self.modelId = modelId; self.variant = variant
  }
  enum CodingKeys: String, CodingKey { case providerId, modelId, variant }
  public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(providerId, forKey: .providerId)
    try c.encode(modelId, forKey: .modelId)
    try c.encode(variant, forKey: .variant)
  }
}
public struct ModelOption: Codable, Sendable, Identifiable {
  public let providerId: String
  public let modelId: String
  public let name: String
  public let variants: [String]
  public var id: String { "\(providerId.utf8.count):\(providerId)\(modelId)" }
}
public struct ModelSettings: Codable, Sendable {
  public let current: ModelSelection
  public let models: [ModelOption]
  public let revision: String
}
public struct SavedPermission: Codable, Sendable, Identifiable {
  public let id: String
  public let action: String
  public let resource: String
  public let revision: String
}
public struct SavedPermissions: Codable, Sendable {
  public let grants: [SavedPermission]
  public let modeSupported: Bool
  public let modeReason: String
}
public struct DeviceAccess: Codable, Sendable {
  public let allWorkspaces: Bool
  public let workspaceIds: [String]
}
public struct ConversationItem: Identifiable, Sendable {
  public let messages: [ChatMessage]
  public let isActivity: Bool
  public var id: String { (isActivity ? "activity:" : "") + (messages.first?.id ?? "") }
  public var toolCount: Int { messages.flatMap(\.blocks).filter { $0.kind == "tool" }.count }
}
public enum ConversationPresentation {
  public static func items(_ messages: [ChatMessage], compact: Bool) -> [ConversationItem] {
    var result: [ConversationItem] = []
    for message in messages {
      let activity = compact && message.role == "assistant" && message.blocks.contains { $0.kind == "tool" }
      var activityMessage = message
      var answer: ChatMessage?
      // Providers may put their answer after tool blocks in the same message.
      // Keep that text visible even when the preceding activity is collapsed.
      if activity, let lastTool = message.blocks.lastIndex(where: { $0.kind == "tool" }), lastTool + 1 < message.blocks.count {
        activityMessage = ChatMessage(id: message.id, sessionId: message.sessionId, role: message.role, createdAt: message.createdAt, blocks: Array(message.blocks[...lastTool]), state: message.state)
        answer = ChatMessage(id: message.id, sessionId: message.sessionId, role: message.role, createdAt: message.createdAt, blocks: Array(message.blocks[(lastTool + 1)...]), state: message.state)
      }
      if activity, result.last?.isActivity == true {
        let previous = result.removeLast()
        result.append(ConversationItem(messages: previous.messages + [activityMessage], isActivity: true))
      } else { result.append(ConversationItem(messages: [activityMessage], isActivity: activity)) }
      if let answer { result.append(ConversationItem(messages: [answer], isActivity: false)) }
    }
    return result
  }
}
