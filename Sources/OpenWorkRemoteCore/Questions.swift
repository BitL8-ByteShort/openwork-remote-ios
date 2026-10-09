import Foundation

public enum QuestionAnswer: Codable, Sendable, Equatable {
  case string(String)
  case multiple([String])

  public init(from decoder: any Decoder) throws {
    let value = try decoder.singleValueContainer()
    if let string = try? value.decode(String.self) { self = .string(string) }
    else { self = .multiple(try value.decode([String].self)) }
  }
  public func encode(to encoder: any Encoder) throws {
    var value = encoder.singleValueContainer()
    switch self {
    case .string(let string): try value.encode(string)
    case .multiple(let strings): try value.encode(strings)
    }
  }
}
public typealias QuestionAnswers = [String: QuestionAnswer]

public struct QuestionOption: Codable, Sendable, Identifiable, Equatable {
  public let value: String
  public let label: String
  public let description: String
  public var id: String { value }
}
public struct QuestionField: Codable, Sendable, Identifiable, Equatable {
  public enum Kind: String, Codable, Sendable { case text, singleChoice, multipleChoice }
  public let key: String
  public let kind: Kind
  public let title: String
  public let prompt: String
  public let options: [QuestionOption]
  public let custom: Bool
  public var id: String { key }
}
public struct QuestionRequest: Codable, Sendable, Identifiable, Equatable {
  public let id: String
  public let sessionId: String
  public let revision: String
  public let supported: Bool
  public let reason: String?
  public let fields: [QuestionField]

  public func validateShape(sessionId: String) throws {
    guard self.sessionId == sessionId, id.range(of: "^[A-Za-z0-9_-]{1,200}$", options: .regularExpression) != nil,
      revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
      (reason?.utf8.count ?? 0) <= 8192, fields.count <= 32
    else { throw RemoteError.invalidResponse }
    guard supported else {
      guard fields.isEmpty else { throw RemoteError.invalidResponse }
      return
    }
    guard !fields.isEmpty, Set(fields.map(\.key)).count == fields.count else { throw RemoteError.invalidResponse }
    for field in fields {
      guard !field.key.isEmpty, field.key.utf8.count <= 200, field.title.utf8.count <= 4096,
        field.prompt.utf8.count <= 8192, field.options.count <= 100,
        Set(field.options.map(\.value)).count == field.options.count,
        field.custom || !field.options.isEmpty,
        field.kind != .text || (field.custom && field.options.isEmpty)
      else { throw RemoteError.invalidResponse }
      for option in field.options {
        guard !option.value.isEmpty, option.value.utf8.count <= 4096,
          option.label.utf8.count <= 4096, option.description.utf8.count <= 8192
        else { throw RemoteError.invalidResponse }
      }
    }
  }

  public func validate(answers: QuestionAnswers) throws {
    guard supported else { throw RemoteError.incompatible }
    try validateShape(sessionId: sessionId)
    guard try JSONEncoder().encode(answers).count <= 32768 else { throw RemoteError.oversized }
    guard Set(answers.keys) == Set(fields.map(\.key)) else { throw RemoteError.invalidResponse }
    for field in fields {
      let allowed = Set(field.options.map(\.value))
      func valid(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (field.custom || allowed.contains(value))
      }
      switch (field.kind, answers[field.key]) {
      case (.multipleChoice, .multiple(let values)):
        guard !values.isEmpty, values.count <= 101, Set(values).count == values.count,
          values.allSatisfy(valid) else { throw RemoteError.invalidResponse }
      case (.text, .string(let value)), (.singleChoice, .string(let value)):
        guard valid(value) else { throw RemoteError.invalidResponse }
      default: throw RemoteError.invalidResponse
      }
    }
  }
}

public struct QuestionSubmission: Codable, Sendable {
  public let requestId: String
  public let revision: String
  public let answers: QuestionAnswers?
  public init(requestId: UUID, revision: String, answers: QuestionAnswers?) {
    self.requestId = requestId.uuidString.lowercased()
    self.revision = revision
    self.answers = answers
  }
}
