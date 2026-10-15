import Foundation

public struct OpenCodeMessageContent: Decodable, Sendable, Equatable {
  public let type:String
  public let text:String?
  public let toolName:String?
  public let toolState:String?
  public let toolSummary:String?
  public let toolFiles:[OpenCodeToolFileReference]
  public let unsupportedToolFiles:Int
  private enum CodingKeys:String,CodingKey { case type,text,name,state }
  private struct State:Decodable {
    struct Output:Decodable {
      let type:String;let text:String?;let uri:String?;let mime:String?
      private enum CodingKeys:String,CodingKey{case type,text,uri,mime}
      init(from decoder:any Decoder)throws{
        let c=try decoder.container(keyedBy:CodingKeys.self)
        type=(try? c.decode(String.self,forKey:.type)) ?? "unknown"
        text=type=="text" ? try? c.decode(String.self,forKey:.text):nil
        uri=type=="file" ? try? c.decode(String.self,forKey:.uri):nil
        mime=type=="file" ? try? c.decode(String.self,forKey:.mime):nil
      }
    }
    let status:String;let content:[Output]?
  }
  public init(from decoder:any Decoder) throws {
    let c = try decoder.container(keyedBy:CodingKeys.self)
    type = try c.decode(String.self,forKey:.type)
    text = ["text","reasoning"].contains(type) ? try c.decode(String.self,forKey:.text) : nil
    toolName = type == "tool" ? try c.decode(String.self,forKey:.name) : nil
    let state = type == "tool" ? try c.decode(State.self,forKey:.state) : nil
    toolState = state?.status
    toolSummary = state?.content?.filter{$0.type == "text"}.compactMap(\.text).joined(separator:"\n")
    let references=state?.content?.filter{$0.type=="file"} ?? []
    toolFiles=references.prefix(128).compactMap{value in
      guard let uri=value.uri,let mime=value.mime,uri.utf8.count<=16_384,!mime.isEmpty,mime.utf8.count<=256 else{return nil}
      return OpenCodeToolFileReference(uri:uri,mime:mime)
    }
    unsupportedToolFiles=references.count-toolFiles.count
  }
}
public struct OpenCodeMessage: Decodable, Sendable, Identifiable, Equatable {
  public struct Time: Decodable, Sendable, Equatable { public let created:Double; public let completed:Double? }
  public let id:String
  public let type:String
  public let text:String?
  public let content:[OpenCodeMessageContent]
  public let time:Time
  public let hasError:Bool
  public let outcome:String?
  public let hasAttachments:Bool
  private let promptPayload:OpenCodePromptAdmission.Payload?
  private let metadata:OpenCodeMessagePresentation?
  public var files:[OpenCodeMaterializedFile]{promptPayload?.files ?? []}
  public var displayText:String?{
    guard let text else{return nil}
    return metadata?.displayText(ifMatching:text) ?? text
  }
  public func matches(_ prompt:OpenCodePrompt)->Bool{type=="user" && promptPayload?.matches(prompt)==true}
  public var displayNotice:String? {
    switch type {
    case "user","synthetic","assistant":nil
    case "compaction":"Earlier conversation summarized."
    case "model-switched":"Model updated."
    case "agent-switched":"Agent updated."
    case "location-switched":"Chat location updated."
    case "system":"Session updated."
    case "skill":"Skill added."
    case "shell":"Command activity on your computer."
    case "idle":nil
    default:"This item is available on your computer."
    }
  }
  private enum CodingKeys:String,CodingKey { case id,type,text,content,time,error,outcome,files,agents,skills,metadata }
  private struct AttachmentPresence:Decodable {}
  public init(from decoder:any Decoder) throws {
    let c = try decoder.container(keyedBy:CodingKeys.self)
    id = try c.decode(String.self,forKey:.id); type = try c.decode(String.self,forKey:.type)
    time = try c.decode(Time.self,forKey:.time)
    guard !id.isEmpty, id.utf8.count <= 2_048, time.created.isFinite else { throw RemoteError.invalidResponse }
    promptPayload = ["user","synthetic"].contains(type) ? try OpenCodePromptAdmission.Payload(from:decoder) : nil
    text = promptPayload?.text
    metadata = promptPayload == nil ? nil : try? c.decode(OpenCodeMessagePresentation.self,forKey:.metadata)
    content = type == "assistant" ? try c.decode([OpenCodeMessageContent].self,forKey:.content) : []
    hasError = try c.contains(.error) && !c.decodeNil(forKey:.error)
    outcome = type == "idle" ? try c.decodeIfPresent(String.self,forKey:.outcome) : nil
    hasAttachments = promptPayload?.hasAttachments==true || (metadata?.displayText(ifMatching:text ?? "") != nil && metadata?.attachments.isEmpty==false)
    guard content.count <= 4_096 else { throw RemoteError.invalidResponse }
  }
  public var storedTextBytes:Int {
    (text?.utf8.count ?? 0) + content.reduce(0){$0 + ($1.text?.utf8.count ?? 0) + ($1.toolSummary?.utf8.count ?? 0) + $1.toolFiles.reduce(0){$0+$1.uri.utf8.count+$1.mime.utf8.count}} +
      files.reduce(0){$0 + ($1.name?.utf8.count ?? 0) + ($1.mime?.utf8.count ?? 0) + ($1.sourceURI?.utf8.count ?? 0) + 128} + (metadata?.storedBytes ?? 0)
  }
}
public struct OpenCodeMessagePage: Decodable, Sendable { public let data:[OpenCodeMessage]; public let cursor:OpenCodeCursor }
extension OpenCodeClient {
  public func messages(sessionID:String,cursor:String?) async throws -> OpenCodeMessagePage {
    func read(limit:Int) async throws -> OpenCodeMessagePage {
      var query=[URLQueryItem(name:"limit",value:String(limit))]
      query.append(URLQueryItem(name:cursor==nil ? "order" : "cursor",value:cursor ?? "desc"))
      return try await decode(OpenCodeMessagePage.self,segments:["api","session",sessionID,"message"],query:query,responseBudget:.materializedPrompt)
    }
    let page:OpenCodeMessagePage
    do{page=try await read(limit:100)}catch{
      guard cursor==nil,error as? RemoteError == .oversized else{throw error}
      // Start a fresh bounded chain. Never edit an opaque continuation cursor,
      // drop file bytes from a message or fabricate a continuation position.
      page=try await read(limit:1)
    }
    try page.cursor.validate()
    guard page.data.count <= 200, Set(page.data.map(\.id)).count == page.data.count else { throw RemoteError.invalidResponse }
    return page
  }
}
