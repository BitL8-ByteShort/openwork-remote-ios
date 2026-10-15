import SwiftUI
import OpenWorkRemoteCore

struct NativeFormSheet:View {
  let store:NativeFormStore
  let context:NativeFormContext
  let formID:String
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @State private var index=0
  @State private var confirmDismiss=false
  @State private var external:URL?
  private var matches:Bool{store.context==context && store.form?.id==formID}
  private var fields:[OpenCodeFormField]{matches ? store.form?.activeFields(answer:store.answers) ?? [] : []}
  private var editable:Bool{matches && store.ready && !store.loading && !store.submitting && !store.storageIssue && !store.hasUncertainOperation && store.form?.isPending==true && store.issue != .authenticationRequired && store.issue != .changed}
  var body:some View {
    NavigationStack {
      ScrollView {
        VStack(alignment:.leading,spacing:24){
          if store.loading{ProgressView("Loading question…")}
          if matches,let form=store.form {
            if !form.isPending{
              Text("This question is resolved").font(.title2.bold())
              Text("It may have been answered or dismissed on your computer.").foregroundStyle(Theme.muted)
            }else if !form.supported{
              Text("Continue on your computer").font(.title2.bold())
              Text("This form uses an external step, authentication or a field PocketWork cannot safely answer. Open the chat in OpenCode to finish it.").foregroundStyle(Theme.muted)
              ForEach(Array(form.fields.enumerated()),id:\.offset){_,field in
                if field.type=="external",let url=field.externalURL{
                  Button("Review external link"){external=url}
                }
              }
            }else if fields.indices.contains(index){
              let field=fields[index]
              Text("Question \(index+1) of \(fields.count)").font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
              NativeFormFieldView(field:field,fallbackTitle:form.title,value:store.answers[field.key],enabled:editable){store.setAnswer($0,for:field.key)}
                .id(field.key)
              if let validation=store.validation{Text(validation.message).font(.callout).foregroundStyle(.red).accessibilityIdentifier("native-form-validation")}
              if index<fields.count-1{
                Button("Next question"){index+=1}.buttonStyle(PrimaryButtonStyle()).disabled(!editable).accessibilityIdentifier("native-form-next")
              }else{
                Button{Task{if await store.submit(context:context){dismiss()}}}label:{HStack{Text("Send answers");if store.submitting{ProgressView()}}}
                  .buttonStyle(PrimaryButtonStyle()).disabled(!editable).accessibilityIdentifier("native-form-submit")
              }
              Text("Your answers go to this chat on your computer.").font(.caption).foregroundStyle(Theme.muted)
            }
            if store.hasUncertainOperation{
              Text("Your previous action could not be confirmed. It will not be sent again automatically. Check its status or finish on your computer.").font(.callout).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("native-form-uncertain")
              Button("Check question status"){Task{await store.checkStatus(context:context)}}.frame(minHeight:44).disabled(store.loading || store.submitting)
            }
            if form.isPending{
              Button("Dismiss question",role:.destructive){confirmDismiss=true}.frame(maxWidth:.infinity,minHeight:44)
                .disabled(!editable).accessibilityIdentifier("native-form-dismiss")
            }
          }else if !store.loading{Text("This question is no longer selected. Close this sheet and review the current chat.").foregroundStyle(Theme.muted)}
          if let issue=store.issue,!(store.hasUncertainOperation && issue == .replyUnconfirmed){
            Text(issueText(issue)).font(.callout).foregroundStyle(Theme.muted).accessibilityIdentifier("native-form-notice")
            if matches,[.unavailable,.changed].contains(issue){Button("Review latest question"){Task{await store.open(id:formID,context:context)}}}
          }
        }.frame(maxWidth:600,alignment:.leading).padding(24).frame(maxWidth:.infinity)
      }.background(Theme.background).navigationTitle("Answer OpenCode").navigationBarTitleDisplayMode(.inline)
        .toolbar{
          ToolbarItem(placement:.cancellationAction){Button("Cancel"){if matches{store.close()};dismiss()}.accessibilityIdentifier("native-form-close")}
          if index>0{ToolbarItem(placement:.topBarTrailing){Button("Previous"){index-=1}}}
        }
    }.task(id:context){await store.open(id:formID,context:context)}
      .onChange(of:fields.count){_,count in index=min(index,max(0,count-1))}
      .onChange(of:store.validation?.field){_,key in if let key,let found=fields.firstIndex(where:{$0.key==key}){index=found}}
      .confirmationDialog("Dismiss this question in OpenCode?",isPresented:$confirmDismiss,titleVisibility:.visible){
        Button("Dismiss question",role:.destructive){Task{if await store.dismissQuestion(context:context){dismiss()}}}
      }message:{Text("This cancels the pending question in this chat on your computer. Closing the sheet with Cancel keeps your answer draft instead.")}
      .sheet(isPresented:Binding(get:{external != nil},set:{if !$0{external=nil}})){
        NavigationStack{
          ScrollView{VStack(alignment:.leading,spacing:24){
            Text("Review the destination").font(.title2.bold())
            Text(external?.absoluteString ?? "").font(.body.monospaced()).textSelection(.enabled)
            Text("This opens your browser without PocketWork’s OpenCode credential. PocketWork will not acknowledge or submit the external step. Finish this form on your computer.").foregroundStyle(Theme.muted)
            Button("Open in browser"){if let external{openURL(external)};external=nil}.buttonStyle(PrimaryButtonStyle())
          }.padding(24).frame(maxWidth:620)}.frame(maxWidth:.infinity).background(Theme.background)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){external=nil}.accessibilityIdentifier("native-external-review-cancel")}}
        }
      }
  }
  private func issueText(_ issue:NativeFormIssue)->String{
    switch issue{
    case .unavailable:return "This question could not be loaded. Check the connection."
    case .storage:return "Your answer could not be saved on this device. Keep it open until you copy it, then unlock the device and try again."
    case .changed:return "The question changed on the computer. Review the latest fields before sending."
    case .replyUnconfirmed:return "The computer has not confirmed your answer. Check status before taking another action."
    case .authenticationRequired:return "Pair again with a fresh code from OpenCode on your computer."
    case .invalidAnswer:return "Check your answers before sending."
    }
  }
}
private struct NativeFormFieldView:View {
  let field:OpenCodeFormField
  let fallbackTitle:String
  let value:OpenCodeFormValue?
  let enabled:Bool
  let change:(OpenCodeFormValue?)->Void
  @FocusState private var editing:Bool
  @State private var numericText=""
  @State private var custom=""
  private var selected:[String]{switch value{case .string(let x):[x];case .strings(let x):x;default:[]}}
  private var string:String{if case .string(let x)=value{return x};return ""}
  var body:some View {
    VStack(alignment:.leading,spacing:16){
      Text(field.title ?? fallbackTitle).font(.title.weight(.semibold)).fixedSize(horizontal:false,vertical:true)
      if field.required==true{Text("Required").font(.caption).foregroundStyle(Theme.muted)}
      if let description=field.description{Text(description).foregroundStyle(Theme.muted)}
      if field.type=="string" || field.type=="multiselect"{
        if let options=field.options{
          Text(field.type=="multiselect" ? "Choose one or more." : "Choose one.").font(.callout).foregroundStyle(Theme.muted)
          ForEach(Array(options.enumerated()),id:\.offset){_,option in
            Button{
              if field.type=="multiselect"{var choices=selected;if let index=choices.firstIndex(where:{OpenCodeIdentity.matches($0,option.value)}){choices.remove(at:index)}else{choices.append(option.value)};change(.strings(choices))}
              else{change(.string(option.value))}
            }label:{HStack(alignment:.top){
              VStack(alignment:.leading,spacing:4){Text(option.label).font(.body.weight(.medium));if let description=option.description{Text(description).font(.callout).foregroundStyle(Theme.muted)}}
              Spacer();if selected.contains(where:{OpenCodeIdentity.matches($0,option.value)}){Image(systemName:"checkmark").accessibilityHidden(true)}
            }.foregroundStyle(selected.contains(option.value) ? Theme.accent : Theme.ink).padding(16).frame(maxWidth:.infinity,alignment:.leading)
              .background(selected.contains(option.value) ? Theme.accent.opacity(0.08) : Theme.raised,in:RoundedRectangle(cornerRadius:16))
              .overlay(RoundedRectangle(cornerRadius:16).stroke(selected.contains(option.value) ? Theme.accent : Theme.line))}
              .disabled(!enabled).accessibilityIdentifier("native-form-option-"+option.value).accessibilityAddTraits(selected.contains(option.value) ? .isSelected : [])
          }
        }
        if field.type=="string",field.options==nil || field.custom==true{
          TextField(field.placeholder ?? "Your answer",text:Binding(get:{string},set:{change(.string($0))}),axis:.vertical)
            .textFieldStyle(.roundedBorder).focused($editing).disabled(!enabled).accessibilityIdentifier("native-form-text")
        }
        if field.type=="multiselect",field.custom==true{
          ForEach(Array(selected.filter{value in !(field.options ?? []).contains{$0.value==value}}.enumerated()),id:\.offset){_,value in
            Button{change(.strings(selected.filter{!OpenCodeIdentity.matches($0,value)}))}label:{Label(value,systemImage:"minus.circle")}.disabled(!enabled)
          }
          HStack{TextField("Another option",text:$custom).textFieldStyle(.roundedBorder);Button("Add"){
            if !custom.isEmpty,!selected.contains(custom){change(.strings(selected+[custom]));custom=""}
          }.disabled(!enabled || custom.isEmpty)}
        }
      }else if field.type=="boolean"{
        Picker("Answer",selection:Binding<Int>(get:{if case .bool(let x)=value{return x ? 1 : 2};return 0},set:{change($0==0 ? nil : .bool($0==1))})){
          Text("Choose").tag(0);Text("Yes").tag(1);Text("No").tag(2)
        }.pickerStyle(.segmented).disabled(!enabled).accessibilityIdentifier("native-form-boolean")
      }else{
        TextField(field.type=="integer" ? "Whole number" : "Number",text:$numericText)
          .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).focused($editing).disabled(!enabled).accessibilityIdentifier("native-form-number")
          .onAppear{if case .number(let number)=value{numericText=String(number)}else if case .string(let text)=value{numericText=text}}
          .onChange(of:numericText){_,text in
            if text.isEmpty{change(nil)}else if text.range(of:#"^-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?$"#,options:.regularExpression) != nil,let number=Double(text),number.isFinite{change(.number(number))}else{change(.string(text))}
          }
        if let minimum=field.minimum{Text("Minimum: \(minimum.formatted())").font(.caption).foregroundStyle(Theme.muted)}
        if let maximum=field.maximum{Text("Maximum: \(maximum.formatted())").font(.caption).foregroundStyle(Theme.muted)}
      }
    }.toolbar{ToolbarItemGroup(placement:.keyboard){Spacer();Button("Done"){editing=false}.accessibilityIdentifier("native-form-keyboard-done")}}
  }
}
