import Foundation

extension OpenCodeProject {
  public var presentation:Workspace {
    let named=name?.trimmingCharacters(in:.whitespacesAndNewlines)
    let label=named?.isEmpty==false ? named! : canonical=="/" ? "Other folders" : URL(fileURLWithPath:canonical).lastPathComponent
    return Workspace(id:id,name:label.isEmpty ? "Project" : label)
  }
}
extension OpenCodeSession {
  public func presentation(active:Bool=false,modelLabel:String?=nil)->ChatSession {
    ChatSession(id:id,workspaceId:projectID,title:title?.isEmpty==false ? title! : "New chat",
      updatedAt:Date(timeIntervalSince1970:time.updated/1_000).ISO8601Format(),modelLabel:modelLabel,status:active ? "busy" : "idle")
  }
}
extension OpenCodeMessage {
  public func presentation(sessionID:String,active:Bool,
                           liveText:(Int)->String?={_ in nil})->ChatMessage? {
    let role:String
    var blocks:[MessageBlock]
    switch type {
    case "user","synthetic":
      role=type=="user" ? "user" : "system"
      var result:[MessageBlock]=[]
      if let text=displayText,!text.isEmpty{result.append(MessageBlock(kind:"text",text:text))}
      for name in fileLabels{result.append(MessageBlock(kind:"attachment",label:"File: "+name))}
      for name in skillLabels{result.append(MessageBlock(kind:"skill",label:"Skill: "+name))}
      if hasAttachments,fileLabels.isEmpty,skillLabels.isEmpty{result.append(MessageBlock(kind:"omitted",label:"Attachments are available on your computer."))}
      blocks=result
    case "assistant":
      role="assistant"
      var ordinal=0
      blocks=content.map{item in
        switch item.type {
        case "text":
          defer{ordinal+=1}
          return MessageBlock(kind:"text",text:liveText(ordinal) ?? item.text ?? "")
        case "tool":return MessageBlock(kind:"tool",name:item.toolName,status:item.toolState,summary:item.toolSummary)
        case "reasoning":return MessageBlock(kind:"tool",name:"Reasoning",status:time.completed==nil && active ? "running" : "completed",summary:"Reasoning on your computer.")
        default:return MessageBlock(kind:"unsupported",label:"Content available on your computer")
        }
      }
    default:
      guard let notice=displayNotice else{return nil}
      role="system";blocks=[MessageBlock(kind:"text",text:notice)]
    }
    if let failureNotice {blocks.append(MessageBlock(kind:"error",text:failureNotice))}
    return ChatMessage(id:id,sessionId:sessionID,role:role,
      createdAt:Date(timeIntervalSince1970:time.created/1_000).ISO8601Format(),blocks:blocks,
      state:hasError ? "error" : type=="assistant" && active && time.completed==nil ? "streaming" : "complete")
  }
}
