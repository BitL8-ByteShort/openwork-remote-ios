import SwiftUI
import OpenWorkRemoteCore

struct NativePermissionsView:View {
  let store:NativeControlStore
  let context:NativeControlContext
  @State private var removing:OpenCodeSavedPermission?
  private var snapshot:NativeControlSnapshot?{store.context==context ? store.snapshot : nil}
  var body:some View {
    Form {
      if store.loading{ProgressView("Loading permissions…")}
      NativeControlIssueView(store:store){Task{await store.load(context)}}
      Section {
        if let review=store.review(context){
          NavigationLink{NativeRuleEditor(store:store,review:review)}label:{
            VStack(alignment:.leading,spacing:8){Text("Review action and resource");Text("Ask, allow or deny for this chat.").font(.caption).foregroundStyle(Theme.muted)}
          }.accessibilityIdentifier("native-session-rules")
        }
        if let rules=snapshot?.session.permissions,!rules.isEmpty {
          ForEach(Array(rules.enumerated()),id:\.offset){index,rule in NativePermissionRuleRow(rule:rule,position:index+1)}
        } else {Text("No explicit rules for this chat.").foregroundStyle(Theme.muted)}
      } header:{Text("Session tool rules")} footer:{Text("Rule order matters: later matching rules take precedence. Agent rules and computer-side policies also apply.")}
      if let snapshot,let agent=snapshot.agents.first(where:{$0.id==snapshot.session.agent}),!agent.permissions.isEmpty {
        Section {
          DisclosureGroup("Agent: "+agent.name){
            ForEach(Array(agent.permissions.enumerated()),id:\.offset){index,rule in NativePermissionRuleRow(rule:rule,position:index+1)}
          }
        } header:{Text("Inherited agent rules")} footer:{Text("Read-only here. Changing this chat’s rules does not edit the agent on your computer.")}
      }
      Section {
        if let saved=snapshot?.saved {
          if saved.isEmpty{Text("No saved tool permissions for this project.").foregroundStyle(Theme.muted)}
          ForEach(saved){grant in
            VStack(alignment:.leading,spacing:10){
              Text(grant.action).font(.headline)
              Text(grant.resource).font(.callout.monospaced()).textSelection(.enabled)
              Button("Revoke saved permission",role:.destructive){removing=grant}.disabled(!store.canEdit(context))
            }.padding(.vertical,8)
          }
        }
      } header:{Text("Saved tool permissions")} footer:{Text("These remembered allowances apply to this project, including its other chats. Revoking one does not change connection access or explicit rules.")}
      Section {
        Text("Native pairing grants server access. Project visibility is a local preference on this device.")
        Text("Forgetting the computer removes this device’s saved credential. OpenCode v2 does not provide individual device revocation; rotating the server password on the computer invalidates all paired devices.")
          .font(.callout).foregroundStyle(Theme.muted)
      } header:{Text("Connection access")}
    }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Permissions")
      .task(id:context){if snapshot==nil{await store.load(context)}}
      .confirmationDialog("Revoke this saved permission?",isPresented:Binding(get:{removing != nil},set:{if !$0{removing=nil}}),titleVisibility:.visible){
        Button("Revoke permission",role:.destructive){
          guard let grant=removing else{return};removing=nil
          Task{_ = await store.removeSaved(grant.id,context:context)}
        }
        Button("Cancel",role:.cancel){removing=nil}
      }message:{Text(removing.map{$0.action+"\n"+$0.resource+"\nApplies to this project’s chats."} ?? "")}
  }
}
private struct NativeEditableRule:Identifiable {
  let id=UUID()
  var action:String
  var resource:String
  var effect:OpenCodePermissionEffect
  init(_ rule:OpenCodePermissionRule){action=rule.action;resource=rule.resource;effect=rule.effect}
  var value:OpenCodePermissionRule?{try? OpenCodePermissionRule(action:action,resource:resource,effect:effect)}
}
private struct NativeRuleEditor:View {
  let store:NativeControlStore
  @State private var review:NativeControlReview
  @Environment(\.dismiss) private var dismiss
  @State private var rows:[NativeEditableRule]
  @State private var proposed:[OpenCodePermissionRule]?
  init(store:NativeControlStore,review:NativeControlReview){
    self.store=store;_review=State(initialValue:review);_rows=State(initialValue:(review.session.permissions ?? []).map(NativeEditableRule.init))
  }
  private var rules:[OpenCodePermissionRule]?{
    let values=rows.compactMap(\.value);return values.count==rows.count && values.count<=2_000 ? values : nil
  }
  var body:some View {
    List {
      Section {
        Text("Edit this chat’s rules in order. The last matching rule wins. OpenCode rechecks the chat before saving, but does not provide an atomic edit lock; another client can still change it during a save.")
          .font(.callout).foregroundStyle(Theme.muted)
      }
      NativeControlIssueView(store:store,displaysActualValues:false){Task{
        if await store.load(review.context),let fresh=store.review(review.context){review=fresh;rows=(fresh.session.permissions ?? []).map(NativeEditableRule.init)}
      }}
      Section {
        ForEach($rows){$row in
          VStack(alignment:.leading,spacing:12){
            TextField("Action",text:$row.action).textInputAutocapitalization(.never).autocorrectionDisabled()
              .font(.body.monospaced()).accessibilityLabel("Rule action")
            TextField("Resource pattern",text:$row.resource,axis:.vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
              .font(.body.monospaced()).accessibilityLabel("Rule resource")
            Picker("Effect",selection:$row.effect){
              Text("Ask").tag(OpenCodePermissionEffect.ask)
              Text("Allow").tag(OpenCodePermissionEffect.allow)
              Text("Deny").tag(OpenCodePermissionEffect.deny)
            }.accessibilityIdentifier("native-rule-effect")
          }.padding(.vertical,8)
        }.onDelete{rows.remove(atOffsets:$0)}.onMove{rows.move(fromOffsets:$0,toOffset:$1)}
        Button("Add rule"){
          if let rule=try? OpenCodePermissionRule(action:"read",resource:"*",effect:.ask){rows.append(NativeEditableRule(rule))}
        }.disabled(rows.count>=2_000 || store.busy)
      } header:{Text("Session tool rules")} footer:{Text("Use Edit to reorder or remove rules. Custom action and resource patterns are preserved.")}
    }.scrollContentBackground(.hidden).background(Theme.background).navigationTitle("Session rules")
      .toolbar{
        ToolbarItem(placement:.topBarTrailing){EditButton()}
        ToolbarItem(placement:.confirmationAction){
          Button("Save"){
            guard let rules else{return}
            if rules.contains(where:{$0.effect == .allow}){proposed=rules}
            else{Task{if await store.setRules(rules,review:review,allowReviewed:false){dismiss()}}}
          }.disabled(!store.canEdit(review.context) || rules==nil || rules==review.session.permissions)
            .accessibilityIdentifier("native-rules-save")
        }
      }.sheet(isPresented:Binding(get:{proposed != nil},set:{if !$0{proposed=nil}})){
        NativeAllowReview(title:"Allow these tool rules?",details:(proposed ?? []).filter{$0.effect == .allow}.map{$0.action+"\n"+$0.resource},explanation:"Matching tool actions can run without asking in this chat. Later rules and computer-side policies still apply."){
          guard let proposed else{return};self.proposed=nil
          Task{if await store.setRules(proposed,review:review,allowReviewed:true){dismiss()}}
        }
      }
  }
}
struct NativePermissionRuleRow:View {
  let rule:OpenCodePermissionRule
  let position:Int
  var body:some View {
    VStack(alignment:.leading,spacing:6){
      HStack{Text("\(position). "+rule.action).font(.headline);Spacer();Text(rule.effect.rawValue.capitalized).font(.caption.bold())}
      Text(rule.resource).font(.callout.monospaced()).textSelection(.enabled)
    }.padding(.vertical,6).accessibilityElement(children:.combine)
  }
}
struct NativeAllowReview:View {
  let title:String
  let details:[String]
  let explanation:String
  let confirm:()->Void
  @Environment(\.dismiss) private var dismiss
  var body:some View {
    NavigationStack{
      ScrollView{
        VStack(alignment:.leading,spacing:20){
          Text(explanation).font(.body)
          ForEach(Array(details.enumerated()),id:\.offset){_,detail in Text(detail).font(.body.monospaced()).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).padding().background(Theme.raised,in:RoundedRectangle(cornerRadius:16))}
          Button("Allow these actions",action:confirm).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("native-allow-confirm")
        }.padding(24).frame(maxWidth:620)
      }.frame(maxWidth:.infinity).background(Theme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}}
    }
  }
}
