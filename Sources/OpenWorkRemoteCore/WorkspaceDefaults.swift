import Foundation
private struct DefaultKey:CodingKey {
 let stringValue:String;var intValue:Int?{nil}
 init?(stringValue:String){self.stringValue=stringValue};init?(intValue:Int){return nil}
}
private func defaultPart(_ v:String,max:Int)->Bool{!v.isEmpty && v.unicodeScalars.count<=max}
private func validDefaultRevision(_ v:String)->Bool{v.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil}
extension ModelSelection {
 func validateDefault() throws {
  guard defaultPart(providerId,max:200),defaultPart(modelId,max:200),variant.map({defaultPart($0,max:80)}) ?? true else{throw RemoteError.invalidResponse}
 }
}
public struct WorkspaceDefaults:Decodable,Sendable {
 public let current:ModelSelection?,models:[ModelOption],revision:String
 private enum CodingKeys:String,CodingKey,CaseIterable{case current,models,revision}
 public init(from decoder:any Decoder)throws {
  let keys=try decoder.container(keyedBy:DefaultKey.self)
  guard Set(keys.allKeys.map(\.stringValue))==Set(CodingKeys.allCases.map(\.rawValue)) else{throw RemoteError.invalidResponse}
  let c=try decoder.container(keyedBy:CodingKeys.self)
  current=try c.decodeIfPresent(ModelSelection.self,forKey:.current);models=try c.decode([ModelOption].self,forKey:.models);revision=try c.decode(String.self,forKey:.revision)
  try current?.validateDefault()
  guard validDefaultRevision(revision),models.count<=2000,Set(models.map(\.id)).count==models.count else{throw RemoteError.invalidResponse}
  for m in models {
   try ModelSelection(providerId:m.providerId,modelId:m.modelId,variant:nil).validateDefault()
   guard defaultPart(m.name,max:256),m.variants.count<=2000,Set(m.variants).count==m.variants.count,m.variants.allSatisfy({defaultPart($0,max:80)}) else{throw RemoteError.invalidResponse}
  }
 }
 public func supports(_ selection:ModelSelection)->Bool {
  models.contains{$0.providerId==selection.providerId && $0.modelId==selection.modelId && (selection.variant==nil || $0.variants.contains(selection.variant!))}
 }
}
extension BridgeClient {
 private func defaultsPath(_ wid:String)throws->String {
  guard wid.range(of:"^[A-Za-z0-9_-]{1,200}$",options:.regularExpression) != nil else{throw RemoteError.invalidResponse}
  return "/v1/workspaces/"+wid+"/default-model"
 }
 public func workspaceDefaults(_ wid:String) async throws->WorkspaceDefaults {
  try await decode(Envelope<WorkspaceDefaults>.self,path:try defaultsPath(wid)).data
 }
 public func setWorkspaceDefaults(_ wid:String,selection:ModelSelection,revision:String,requestId:UUID) async throws->MutationReceipt {
  try selection.validateDefault();guard validDefaultRevision(revision) else{throw RemoteError.invalidResponse};try Task.checkCancellation()
  struct Body:Encodable{let requestId:String,revision:String,selection:ModelSelection}
  let receipt=try await decode(Envelope<MutationReceipt>.self,path:try defaultsPath(wid),method:"POST",body:JSONEncoder().encode(Body(requestId:requestId.uuidString.lowercased(),revision:revision,selection:selection))).data
  guard receipt.requestId==requestId.uuidString.lowercased(),["accepted","confirmed","rejected","pending","outcome_unknown"].contains(receipt.state),(["accepted","confirmed"].contains(receipt.state) ? receipt.resourceId==wid:receipt.resourceId==nil || receipt.resourceId==wid) else{throw RemoteError.invalidResponse}
  return receipt
 }
}
