"""Generate the native Xcode project using only Python's standard library."""
from pathlib import Path
import hashlib

ROOT=Path(__file__).resolve().parents[1]
objects={}
def ident(name):return hashlib.sha256(name.encode()).hexdigest()[:24].upper()
def quoted(value):return '"'+value.replace('\\','\\\\').replace('"','\\"')+'"'
def add(name,body):
    key=ident(name);objects[key]=body;return key
def array(values):return '('+','.join(values)+',)' if values else '()'
def config(name,settings):
    return add(name,'isa = XCBuildConfiguration; buildSettings = {'+' '.join(f'{key} = {value};' for key,value in settings.items())+'}; name = '+quoted(name.rsplit('-',1)[-1])+';')
def configlist(name,configs):return add(name,'isa = XCConfigurationList; buildConfigurations = '+array(configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
def file(path,type):return add('file-'+path,f'isa = PBXFileReference; lastKnownFileType = {type}; path = {quoted(path)}; sourceTree = "<group>";')
def buildfile(path,reference):return add('build-'+path,'isa = PBXBuildFile; fileRef = '+reference+';')
def phase(name,isa,files):return add(name,f'isa = {isa}; buildActionMask = 2147483647; files = '+array(files)+'; runOnlyForDeploymentPostprocessing = 0;')

sources=[];children=[];resources=[]
for path in sorted((ROOT/'ThreadsStudio').glob('*.swift')):
    ref=file(path.name,'sourcecode.swift');children.append(ref);sources.append(buildfile(path.name,ref))
for path,type in [('ThreadsScan.js','sourcecode.javascript'),('Assets.xcassets','folder.assetcatalog'),('Library','folder')]:
    ref=file(path,type);children.append(ref);resources.append(buildfile(path,ref))
children.append(file('Info.plist','text.plist.xml'))
group=add('app-group','isa = PBXGroup; children = '+array(children)+'; path = ThreadsStudio; sourceTree = "<group>";')
tests=file('StudioTests.swift','sourcecode.swift')
testgroup=add('test-group','isa = PBXGroup; children = '+array([tests])+'; path = Tests; sourceTree = "<group>";')
product=add('app-product','isa = PBXFileReference; explicitFileType = wrapper.application; path = ThreadsStudio.app; sourceTree = BUILT_PRODUCTS_DIR;')
testproduct=add('test-product','isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = ThreadsStudioTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products=add('products-group','isa = PBXGroup; children = '+array([product,testproduct])+'; name = Products; sourceTree = "<group>";')
main=add('main-group','isa = PBXGroup; children = '+array([group,testgroup,products])+'; sourceTree = "<group>";')
projectsettings={'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES','ENABLE_STRICT_OBJC_MSGSEND':'YES','SWIFT_STRICT_CONCURRENCY':'minimal'}
projectconfigs=[];appconfigs=[];testconfigs=[]
for mode in ['Debug','Release']:
    debug=mode=='Debug'
    projectconfigs.append(config('project-'+mode,{**projectsettings,'SWIFT_OPTIMIZATION_LEVEL':quoted('-Onone' if debug else '-O'),'DEBUG_INFORMATION_FORMAT':quoted('dwarf' if debug else 'dwarf-with-dsym'),'ENABLE_TESTABILITY':'YES' if debug else 'NO','SWIFT_ACTIVE_COMPILATION_CONDITIONS':quoted('DEBUG' if debug else '')}))
    appconfigs.append(config('app-'+mode,{'PRODUCT_NAME':'ThreadsStudio','PRODUCT_BUNDLE_IDENTIFIER':'com.threads.studio.local','INFOPLIST_FILE':quoted('ThreadsStudio/Info.plist'),'TARGETED_DEVICE_FAMILY':quoted('1'),'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGN_STYLE':'Automatic','GENERATE_INFOPLIST_FILE':'NO','LD_RUNPATH_SEARCH_PATHS':quoted('$(inherited) @executable_path/Frameworks')}))
    testconfigs.append(config('tests-'+mode,{'PRODUCT_NAME':'ThreadsStudioTests','PRODUCT_BUNDLE_IDENTIFIER':'com.threads.studio.local.tests','GENERATE_INFOPLIST_FILE':'YES','TARGETED_DEVICE_FAMILY':'1','TEST_HOST':quoted('$(BUILT_PRODUCTS_DIR)/ThreadsStudio.app/ThreadsStudio'),'BUNDLE_LOADER':quoted('$(TEST_HOST)'),'LD_RUNPATH_SEARCH_PATHS':quoted('$(inherited) @executable_path/Frameworks @loader_path/Frameworks')}))
appconfig=configlist('app-config',appconfigs);testconfig=configlist('tests-config',testconfigs);projectconfig=configlist('project-config',projectconfigs)
app_phases=[phase('app-sources','PBXSourcesBuildPhase',sources),phase('app-frameworks','PBXFrameworksBuildPhase',[]),phase('app-resources','PBXResourcesBuildPhase',resources)]
app=add('app-target','isa = PBXNativeTarget; buildConfigurationList = '+appconfig+'; buildPhases = '+array(app_phases)+'; buildRules = (); dependencies = (); name = ThreadsStudio; productName = ThreadsStudio; productReference = '+product+'; productType = "com.apple.product-type.application";')
proxy=add('app-proxy','isa = PBXContainerItemProxy; containerPortal = '+ident('project')+'; proxyType = 1; remoteGlobalIDString = '+app+'; remoteInfo = ThreadsStudio;')
dependency=add('test-dependency','isa = PBXTargetDependency; target = '+app+'; targetProxy = '+proxy+';')
test_phases=[phase('test-sources','PBXSourcesBuildPhase',[buildfile('test-source',tests)]),phase('test-frameworks','PBXFrameworksBuildPhase',[]),phase('test-resources','PBXResourcesBuildPhase',[])]
test=add('test-target','isa = PBXNativeTarget; buildConfigurationList = '+testconfig+'; buildPhases = '+array(test_phases)+'; buildRules = (); dependencies = '+array([dependency])+'; name = ThreadsStudioTests; productName = ThreadsStudioTests; productReference = '+testproduct+'; productType = "com.apple.product-type.bundle.unit-test";')
project=add('project','isa = PBXProject; attributes = { LastUpgradeCheck = 1600; TargetAttributes = { '+test+' = { TestTargetID = '+app+'; }; }; }; buildConfigurationList = '+projectconfig+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = vi; hasScannedForEncodings = 0; knownRegions = (vi,en,Base,); mainGroup = '+main+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+array([app,test])+';')
folder=ROOT/'ThreadsStudio.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+''.join(key+' = { '+body+' };\n' for key,body in objects.items())+'}; rootObject = '+project+'; }\n',encoding='utf-8')
schemes=folder/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
def reference(target,name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:ThreadsStudio.xcodeproj"/>'
(schemes/'ThreadsStudio.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(app,'ThreadsStudio.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference(test,'ThreadsStudioTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app,'ThreadsStudio.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(app,'ThreadsStudio.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''',encoding='utf-8')
print('Generated',folder)
