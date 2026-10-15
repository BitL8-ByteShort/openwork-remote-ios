import SwiftUI

/// The two unchanged visible paths of OpenCode's official 240×300 logo,
/// expressed as a native vector. Copyright (c) 2025 opencode, MIT.
/// Source: anomalyco/opencode v2.0.29, packages/console/app/src/asset/brand.
struct OpenCodeBrandMark:View {
  @Environment(\.colorScheme) private var scheme
  var body:some View {
    GeometryReader {g in
      let r=CGRect(origin:.zero,size:g.size)
      ZStack {
        Path {p in
          p.addRect(r)
          p.addRect(CGRect(x:r.width*0.25,y:r.height*0.2,width:r.width*0.5,height:r.height*0.6))
        }.fill(scheme == .dark ? Color(red:241/255,green:236/255,blue:236/255) : Color(red:33/255,green:30/255,blue:30/255),style:FillStyle(eoFill:true))
        Path {p in p.addRect(CGRect(x:r.width*0.25,y:r.height*0.4,width:r.width*0.5,height:r.height*0.4))}
          .fill(scheme == .dark ? Color(red:75/255,green:70/255,blue:70/255) : Color(red:207/255,green:206/255,blue:205/255))
      }
    }.aspectRatio(0.8,contentMode:.fit).accessibilityHidden(true)
  }
}
