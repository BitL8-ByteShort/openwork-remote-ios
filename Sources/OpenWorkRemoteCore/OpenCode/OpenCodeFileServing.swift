import Foundation
public protocol OpenCodeFileServing:AnyObject,Sendable {
  func attachmentModel(target:OpenCodeTarget) async throws -> OpenCodeModel
  func prepareAttachment(bytes:Data,name:String,mime:String,target:OpenCodeTarget,model:OpenCodeModel) async throws -> OpenCodePromptFile
}
extension OpenCodeClient:OpenCodeFileServing {}
