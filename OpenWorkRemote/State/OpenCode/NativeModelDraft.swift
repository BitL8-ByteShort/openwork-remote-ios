import Foundation
import OpenWorkRemoteCore

/// A display/edit draft. Missing catalog entries never select a replacement.
struct NativeModelDraft {
  let current:OpenCodeModelRef?
  var selectedKey:Data?
  var variant:String
  init(snapshot:NativeControlSnapshot) {
    let inherited=snapshot.agents.first{OpenCodeIdentity.matches($0.id,snapshot.session.agent ?? "")}?.model
    let resolved=snapshot.session.model ?? inherited ?? snapshot.serverDefault.flatMap{
      try? OpenCodeModelRef(providerID:$0.providerID,id:$0.id)
    }
    current=resolved
    selectedKey=snapshot.models.first{model in resolved.map{
      OpenCodeIdentity.matches(model.id,$0.id) && OpenCodeIdentity.matches(model.providerID,$0.providerID)
    } ?? false}?.selectionKey
    variant=resolved?.variant ?? ""
  }
  mutating func choose(_ model:OpenCodeModel){selectedKey=model.selectionKey;variant=""}
  func selection(in models:[OpenCodeModel])->OpenCodeModelRef? {
    guard let model=models.first(where:{$0.selectionKey==selectedKey}),model.selectable,
      variant.isEmpty || model.variants.contains(where:{OpenCodeIdentity.matches($0.id,variant)}) else{return nil}
    return try? OpenCodeModelRef(providerID:model.providerID,id:model.id,variant:variant.isEmpty ? nil : variant)
  }
}
