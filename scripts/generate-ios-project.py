#!/usr/bin/env python3
"""Generate the checked-in native project using deterministic object IDs."""
import hashlib,pathlib,json
root=pathlib.Path(__file__).resolve().parents[1]
objects={}
def uid(key):return hashlib.sha256(key.encode()).hexdigest()[:24].upper()
def add(key,isa,**values):
 i=uid(key);objects[i]={'isa':isa,**values};return i
def ref(key):return uid(key)
def scalar(v):
 if isinstance(v,list):return '( '+', '.join(scalar(x) for x in v)+' )'
 if isinstance(v,dict):return '{ '+' '.join(str(k)+' = '+scalar(x)+';' for k,x in v.items())+' }'
 return json.dumps(str(v))
common={'PRODUCT_NAME':'$(TARGET_NAME)','IPHONEOS_DEPLOYMENT_TARGET':'18.0','SWIFT_VERSION':'6.0','CLANG_ENABLE_MODULES':'YES','SDKROOT':'iphoneos','TARGETED_DEVICE_FAMILY':'1,2','CODE_SIGN_STYLE':'Automatic','MARKETING_VERSION':'0.1.0','CURRENT_PROJECT_VERSION':'4','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}
def configs(key,extra):
 configs=[]
 for name in ['Debug','Release']:
  settings={**common,**extra,'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if name=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if name=='Debug' else 'dwarf-with-dsym'}
  if name=='Debug':
   settings['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
   settings['ONLY_ACTIVE_ARCH']='YES'
  configs.append(add(key+name,'XCBuildConfiguration',name=name,buildSettings=settings))
 return add(key+'configs','XCConfigurationList',buildConfigurations=configs,defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
product=add('appproduct','PBXFileReference',explicitFileType='wrapper.application',path='OpenWorkRemote.app',sourceTree='BUILT_PRODUCTS_DIR')
testproduct=add('testproduct','PBXFileReference',explicitFileType='wrapper.cfbundle',path='OpenWorkRemoteUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
appfiles=[];sourcebuild=[];resources=[]
for f in sorted((root/'OpenWorkRemote').rglob('*')):
 if not f.is_file() or f.suffix not in ['.swift','.xcprivacy']:continue
 p=str(f.relative_to(root));t='sourcecode.swift' if f.suffix=='.swift' else 'text.xml';fid=add(p,'PBXFileReference',lastKnownFileType=t,path=p,sourceTree='<group>');appfiles.append(fid);bid=add(p+'build','PBXBuildFile',fileRef=fid);(sourcebuild if f.suffix=='.swift' else resources).append(bid)
assets=root/'OpenWorkRemote/Assets.xcassets'
if assets.exists():
 fid=add('assets','PBXFileReference',lastKnownFileType='folder.assetcatalog',path='OpenWorkRemote/Assets.xcassets',sourceTree='<group>');appfiles.append(fid);resources.append(add('assetsbuild','PBXBuildFile',fileRef=fid))
testfiles=[];testbuild=[]
for f in sorted((root/'OpenWorkRemoteUITests').glob('*.swift')):
 p=str(f.relative_to(root));fid=add(p,'PBXFileReference',lastKnownFileType='sourcecode.swift',path=p,sourceTree='<group>');testfiles.append(fid);testbuild.append(add(p+'build','PBXBuildFile',fileRef=fid))
appgroup=add('appgroup','PBXGroup',children=appfiles,name='OpenWorkRemote',sourceTree='<group>');testgroup=add('testgroup','PBXGroup',children=testfiles,name='OpenWorkRemoteUITests',sourceTree='<group>');products=add('products','PBXGroup',children=[product,testproduct],name='Products',sourceTree='<group>');main=add('main','PBXGroup',children=[appgroup,testgroup,products],sourceTree='<group>')
package=add('localpackage','XCLocalSwiftPackageReference',relativePath='.')
packageproduct=add('coreproduct','XCSwiftPackageProductDependency',package=package,productName='OpenWorkRemoteCore')
framework=add('corebuild','PBXBuildFile',productRef=packageproduct)
sources=add('appsources','PBXSourcesBuildPhase',buildActionMask='2147483647',files=sourcebuild,runOnlyForDeploymentPostprocessing='0');res=add('appres','PBXResourcesBuildPhase',buildActionMask='2147483647',files=resources,runOnlyForDeploymentPostprocessing='0');frameworks=add('appframeworks','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[framework],runOnlyForDeploymentPostprocessing='0')
app=add('apptarget','PBXNativeTarget',name='OpenWorkRemote',productName='OpenWorkRemote',productReference=product,productType='com.apple.product-type.application',buildPhases=[sources,frameworks,res],buildRules=[],dependencies=[],packageProductDependencies=[packageproduct],buildConfigurationList=configs('app',{'PRODUCT_BUNDLE_IDENTIFIER':'com.saltypanda.openworkremote','INFOPLIST_FILE':'OpenWorkRemote/Info.plist','GENERATE_INFOPLIST_FILE':'NO','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon'}))
testsrc=add('testsources','PBXSourcesBuildPhase',buildActionMask='2147483647',files=testbuild,runOnlyForDeploymentPostprocessing='0');testres=add('testres','PBXResourcesBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0');testframework=add('testframeworks','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=[],runOnlyForDeploymentPostprocessing='0')
proxy=add('targetproxy','PBXContainerItemProxy',containerPortal=ref('project'),proxyType='1',remoteGlobalIDString=app,remoteInfo='OpenWorkRemote');dependency=add('dependency','PBXTargetDependency',target=app,targetProxy=proxy)
test=add('testtarget','PBXNativeTarget',name='OpenWorkRemoteUITests',productName='OpenWorkRemoteUITests',productReference=testproduct,productType='com.apple.product-type.bundle.ui-testing',buildPhases=[testsrc,testframework,testres],buildRules=[],dependencies=[dependency],buildConfigurationList=configs('test',{'PRODUCT_BUNDLE_IDENTIFIER':'com.saltypanda.openworkremote.uitests','GENERATE_INFOPLIST_FILE':'YES','TEST_TARGET_NAME':'OpenWorkRemote'}))
project=add('project','PBXProject',attributes={'BuildIndependentTargetsInParallel':'YES','LastUpgradeCheck':'2700','TargetAttributes':{app:{'CreatedOnToolsVersion':'27.0'},test:{'CreatedOnToolsVersion':'27.0','TestTargetID':app}}},buildConfigurationList=configs('project',{}),compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings='0',knownRegions=['en','Base'],mainGroup=main,productRefGroup=products,projectDirPath='',projectRoot='',packageReferences=[package],targets=[app,test])
folder=root/'OpenWorkRemote.xcodeproj';folder.mkdir(exist_ok=True);(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(i+' = '+scalar(v)+';\n' for i,v in objects.items())+'}; rootObject = '+project+'; }\n')
scheme=folder/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
def buildref(i,name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{i}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:OpenWorkRemote.xcodeproj"/>'
(scheme/'OpenWorkRemote.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2700" version="1.7"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildref(app,'OpenWorkRemote.app')}</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildref(test,'OpenWorkRemoteUITests.xctest')}</TestableReference></Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildref(app,'OpenWorkRemote.app')}</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildref(app,'OpenWorkRemote.app')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>''')
print('Generated OpenWorkRemote.xcodeproj')
