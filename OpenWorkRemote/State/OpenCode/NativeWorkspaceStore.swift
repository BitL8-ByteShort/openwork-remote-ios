import Foundation
import Observation
import OpenWorkRemoteCore

struct NativeWorkspaceContext:Hashable,Sendable,Identifiable {
  let target:OpenCodeTarget
  fileprivate let generation:UUID
  var id:UUID{generation}
}
@MainActor @Observable final class NativeWorkspaceStore {
  private(set) var context:NativeWorkspaceContext?
  private(set) var info:OpenCodeWorkspaceInfo?
  private(set) var changes:[OpenCodeChange]=[]
  private(set) var diff:OpenCodeWorkingDiff?
  private(set) var diffLines:[DiffLine]=[]
  private(set) var diffOmitted=false
  private(set) var changesLoading=false
  private(set) var diffLoading=false
  private(set) var changesNotice:String?
  private(set) var skills:[OpenCodeSkill]=[]
  private(set) var skillsLoading=false
  private(set) var skillsAvailable=false
  private(set) var skillsNotice:String?
  @ObservationIgnored private let journal:NativeConversationJournal
  @ObservationIgnored private var client:(any OpenCodeWorkspaceServing)?
  @ObservationIgnored private var changesRead=UUID()
  @ObservationIgnored private var diffRead=UUID()
  @ObservationIgnored private var skillsRead=UUID()
  init(journal:NativeConversationJournal){self.journal=journal}
  var selectedSkills:[NativeSelectedSkill]{context.map{journal.skills(for:$0.target)} ?? []}
  @discardableResult func activate(target:OpenCodeTarget,client:any OpenCodeWorkspaceServing)->NativeWorkspaceContext{
    deactivate();let value=NativeWorkspaceContext(target:target,generation:UUID());context=value;self.client=client;return value
  }
  func deactivate(){
    context=nil;client=nil;changesRead=UUID();diffRead=UUID();skillsRead=UUID()
    info=nil;changes=[];diff=nil;diffLines=[];diffOmitted=false;skills=[];changesLoading=false;diffLoading=false;skillsLoading=false;skillsAvailable=false;changesNotice=nil;skillsNotice=nil
  }
  func loadChanges(_ context:NativeWorkspaceContext)async{
    guard self.context==context,let client else{return}
    let id=UUID();changesRead=id;changesLoading=true;changesNotice=nil;closeDiff()
    defer{if self.context==context,changesRead==id{changesLoading=false}}
    do{
      let location=OpenCodeLocation(directory:context.target.directory),info=try await client.workspaceInfo(location:OpenCodeLocation(directory:context.target.directory))
      let rows=info.provider==nil ? []:try await client.workspaceChanges(location:location)
      guard self.context==context,changesRead==id,!Task.isCancelled else{return}
      self.info=info;changes=rows
    }catch{if self.context==context,changesRead==id{changesNotice="Working-copy changes could not be loaded. Refresh or review them on your computer."}}
  }
  func openDiff(_ file:OpenCodeChange,context:NativeWorkspaceContext)async{
    guard self.context==context,let client else{return}
    let id=UUID();diffRead=id;diffLoading=true;diff=nil;changesNotice=nil
    defer{if self.context==context,diffRead==id{diffLoading=false}}
    do{
      let rows=try await client.workspaceDiff(location:OpenCodeLocation(directory:context.target.directory))
      guard self.context==context,diffRead==id,!Task.isCancelled else{return}
      guard let selected=rows.first(where:{OpenCodeIdentity.matches($0.file,file.file)}) else{
        changesNotice="OpenCode returned no current text diff for this path. Refresh the list or review the file on your computer.";return
      }
      let parsed=await Task.detached(priority:.userInitiated){
        (DiffLine.parse(selected.patch),selected.patch.split(separator:"\n",omittingEmptySubsequences:false).count>10_000)
      }.value
      guard self.context==context,diffRead==id,!Task.isCancelled else{return}
      diff=selected;diffLines=parsed.0;diffOmitted=parsed.1
    }catch{if self.context==context,diffRead==id{
      changesNotice=error as? RemoteError == .oversized ? "The native diff is too large to preview here. Review it on your computer.":"The native diff could not be loaded. Refresh or review it on your computer."
    }}
  }
  func closeDiff(){diffRead=UUID();diff=nil;diffLines=[];diffOmitted=false;diffLoading=false}
  @discardableResult func loadSkills(_ context:NativeWorkspaceContext)async->Bool{
    guard self.context==context,let client else{return false}
    let id=UUID();skillsRead=id;skillsLoading=true;skillsAvailable=false;skillsNotice=nil
    defer{if self.context==context,skillsRead==id{skillsLoading=false}}
    do{
      let rows=try await client.skills(location:OpenCodeLocation(directory:context.target.directory))
      guard self.context==context,skillsRead==id,!Task.isCancelled else{return false};skills=rows;skillsAvailable=true;return true
    }catch{if self.context==context,skillsRead==id{skillsNotice="Registered skills could not be loaded. Reconnect or review them on your computer."};return false}
  }
  func canChooseSkills(_ context:NativeWorkspaceContext)->Bool{self.context==context && journal.ready && !journal.storageIssue && journal.pending(for:context.target)==nil}
  func choose(_ skill:OpenCodeSkill,selected:Bool,context:NativeWorkspaceContext)async throws{
    guard canChooseSkills(context),!skillsLoading,skillsAvailable,
      skills.contains(where:{OpenCodeIdentity.matches($0.id,skill.id) && $0.fingerprint==skill.fingerprint}) else{throw RemoteError.conflict}
    var rows=selectedSkills.filter{!OpenCodeIdentity.matches($0.id,skill.id)}
    if selected{rows.append(NativeSelectedSkill(skill))}
    try await journal.setSkills(rows,for:context.target)
    if self.context==context{skillsNotice=nil}
  }
  func removeSkill(_ id:String,context:NativeWorkspaceContext)async throws{
    guard self.context==context else{throw RemoteError.conflict}
    try await journal.setSkills(selectedSkills.filter{!OpenCodeIdentity.matches($0.id,id)},for:context.target)
  }
  func validatedSkills(_ context:NativeWorkspaceContext)async->[String]?{
    guard self.context==context else{return nil}
    let chosen=selectedSkills
    if chosen.isEmpty{return []}
    guard await loadSkills(context) else{return nil}
    guard self.context==context,skillsNotice==nil,chosen==selectedSkills else{return nil}
    guard chosen.allSatisfy({item in skills.contains{OpenCodeIdentity.matches($0.id,item.id) && $0.fingerprint==item.fingerprint}}) else{
      skillsNotice="A selected skill changed or was removed. Review its current instructions, then select that version or remove it before sending.";return nil
    }
    return chosen.map(\.id)
  }
}
