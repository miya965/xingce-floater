#!/usr/bin/env python3
"""生成可在 Xcode 14 打开的 macOS 工程。本机没有 xcodebuild 时仍用 scripts/build-app.sh 编译。"""

import hashlib
import pathlib

root = pathlib.Path(__file__).resolve().parents[1]
core = sorted((root / "Sources" / "XingceCore").glob("*.swift"))
app = sorted((root / "Sources" / "XingceApp").glob("*.swift"))
app = [path for path in app if path.suffix == ".swift"]
resources = [
    root / "Fixtures" / "sample-bank.json",
    root / "Fixtures" / "images" / "dots.png",
    root / "Fixtures" / "images" / "bars.png",
]
tests = [root / "Tests" / "main.swift"]


def uid(name: str) -> str:
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


def ref(path: pathlib.Path, kind: str) -> str:
    rel = path.relative_to(root).as_posix()
    return f"""
\t\t{uid('file:' + rel)} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = {kind}; path = {path.name}; sourceTree = "<group>"; }};"""


def build(path: pathlib.Path, phase: str) -> str:
    rel = path.relative_to(root).as_posix()
    return f"""
\t\t{uid(phase + ':' + rel)} /* {path.name} in {phase} */ = {{isa = PBXBuildFile; fileRef = {uid('file:' + rel)} /* {path.name} */; }};"""


file_kinds = {".swift": "sourcecode.swift", ".json": "text.json", ".png": "image.png", ".plist": "text.plist.xml"}
plist = root / "Sources" / "XingceApp" / "Info.plist"

files = core + app + resources + tests + [plist]
file_refs = "".join(ref(path, file_kinds[path.suffix]) for path in files)
build_files = "".join(build(path, "Sources") for path in core + app + tests)
build_files += "".join(build(path, "Resources") for path in resources)

app_sources = "".join(
    f"\n\t\t\t\t{uid('Sources:' + path.relative_to(root).as_posix())} /* {path.name} in Sources */,"
    for path in core + app
)
test_sources = "".join(
    f"\n\t\t\t\t{uid('Sources:' + path.relative_to(root).as_posix())} /* {path.name} in Sources */,"
    for path in core + tests
)
resource_lines = "".join(
    f"\n\t\t\t\t{uid('Resources:' + path.relative_to(root).as_posix())} /* {path.name} in Resources */,"
    for path in resources
)

def group(name, children, path):
    body = "".join(
        f"\n\t\t\t\t{uid('file:' + child.relative_to(root).as_posix())} /* {child.name} */,"
        for child in children
    )
    return f"""
\t\t{uid('group:' + name)} /* {name} */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = ({body}
\t\t\t);
\t\t\tpath = {path};
\t\t\tsourceTree = "<group>";
\t\t}};"""


groups = group("XingceCore", core, "XingceCore")
groups += group("XingceApp", app + [plist], "XingceApp")
groups += group("images", [root / "Fixtures" / "images" / "dots.png", root / "Fixtures" / "images" / "bars.png"], "images")
groups += group("Fixtures", [root / "Fixtures" / "sample-bank.json", root / "Fixtures" / "images"], "Fixtures")
# images group path is images, but children are files inside images. The Fixtures group contains sample json and the images group, not the png files directly.
# Fix Fixtures children: the images entry above used a directory. PBXGroup for images is separate. Fixtures should reference the images group id not a file ref.
# I'll rewrite Fixtures group manually below and not use the broken one.

groups = group("XingceCore", core, "XingceCore")
groups += group("XingceApp", app + [plist], "XingceApp")
groups += group("images", [root / "Fixtures" / "images" / "dots.png", root / "Fixtures" / "images" / "bars.png"], "images")
groups += f"""
\t\t{uid('group:Fixtures')} /* Fixtures */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{uid('file:' + (root / 'Fixtures' / 'sample-bank.json').relative_to(root).as_posix())} /* sample-bank.json */,
\t\t\t\t{uid('group:images')} /* images */,
\t\t\t);
\t\t\tpath = Fixtures;
\t\t\tsourceTree = "<group>";
\t\t}};"""
groups += group("Tests", tests, "Tests")
groups += f"""
\t\t{uid('group:Sources')} /* Sources */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{uid('group:XingceCore')} /* XingceCore */,
\t\t\t\t{uid('group:XingceApp')} /* XingceApp */,
\t\t\t);
\t\t\tpath = Sources;
\t\t\tsourceTree = "<group>";
\t\t}};"""
groups += f"""
\t\t{uid('group:Products')} /* Products */ = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{uid('product:app')} /* XingceFloater.app */,
\t\t\t\t{uid('product:tests')} /* xingce-tests */,
\t\t\t);
\t\t\tname = Products;
\t\t\tsourceTree = "<group>";
\t\t}};"""

project = f"""// !$*UTF8*$!
{{
\tarchiveVersion = 1;
\tclasses = {{
\t}};
\tobjectVersion = 56;
\tobjects = {{
{build_files}
{file_refs}
\t\t{uid('product:app')} /* XingceFloater.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = XingceFloater.app; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{uid('product:tests')} /* xingce-tests */ = {{isa = PBXFileReference; explicitFileType = "compiled.mach-o.executable"; includeInIndex = 0; path = "xingce-tests"; sourceTree = BUILT_PRODUCTS_DIR; }};
{groups}

\t\t{uid('group:root')} = {{
\t\t\tisa = PBXGroup;
\t\t\tchildren = (
\t\t\t\t{uid('group:Sources')} /* Sources */,
\t\t\t\t{uid('group:Fixtures')} /* Fixtures */,
\t\t\t\t{uid('group:Tests')} /* Tests */,
\t\t\t\t{uid('group:Products')} /* Products */,
\t\t\t);
\t\t\tsourceTree = "<group>";
\t\t}};

\t\t{uid('phase:app-sources')} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ({app_sources}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{uid('phase:test-sources')} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ({test_sources}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{uid('phase:app-resources')} /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = ({resource_lines}
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{uid('phase:frameworks')} /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};

\t\t{uid('target:app')} /* 行测刷题器 */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {uid('cfglist:app')} /* Build configuration list for PBXNativeTarget "行测刷题器" */;
\t\t\tbuildPhases = (
\t\t\t\t{uid('phase:app-sources')} /* Sources */,
\t\t\t\t{uid('phase:frameworks')} /* Frameworks */,
\t\t\t\t{uid('phase:app-resources')} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = "行测刷题器";
\t\t\tproductName = XingceFloater;
\t\t\tproductReference = {uid('product:app')} /* XingceFloater.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t{uid('target:tests')} /* xingce-tests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {uid('cfglist:tests')} /* Build configuration list for PBXNativeTarget "xingce-tests" */;
\t\t\tbuildPhases = (
\t\t\t\t{uid('phase:test-sources')} /* Sources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = "xingce-tests";
\t\t\tproductName = xingce-tests;
\t\t\tproductReference = {uid('product:tests')} /* xingce-tests */;
\t\t\tproductType = "com.apple.product-type.tool";
\t\t}};

\t\t{uid('project')} /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastUpgradeCheck = 1420;
\t\t\t}};
\t\t\tbuildConfigurationList = {uid('cfglist:project')} /* Build configuration list for PBXProject "XingceFloater" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = "zh-Hans";
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\tzh-Hans,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {uid('group:root')};
\t\t\tproductRefGroup = {uid('group:Products')} /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t{uid('target:app')} /* 行测刷题器 */,
\t\t\t\t{uid('target:tests')} /* xingce-tests */,
\t\t\t);
\t\t}};

\t\t{uid('cfg:project-debug')} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 12.0;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{uid('cfg:project-release')} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 12.0;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{uid('cfg:app-debug')} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_IDENTITY = "-";
\t\t\t\tCODE_SIGN_STYLE = Manual;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 2;
\t\t\t\tENABLE_HARDENED_RUNTIME = NO;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Sources/XingceApp/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 0.2.0;
\t\t\t\tOTHER_LDFLAGS = "-lsqlite3";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.local.xingcefloater;
\t\t\t\tPRODUCT_NAME = XingceFloater;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{uid('cfg:app-release')} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_IDENTITY = "-";
\t\t\t\tCODE_SIGN_STYLE = Manual;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 2;
\t\t\t\tENABLE_HARDENED_RUNTIME = NO;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Sources/XingceApp/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 0.2.0;
\t\t\t\tOTHER_LDFLAGS = "-lsqlite3";
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.local.xingcefloater;
\t\t\t\tPRODUCT_NAME = XingceFloater;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t{uid('cfg:tests-debug')} /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_IDENTITY = "-";
\t\t\t\tCODE_SIGNING_REQUIRED = NO;
\t\t\t\tOTHER_LDFLAGS = "-lsqlite3";
\t\t\t\tPRODUCT_NAME = "xingce-tests";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t{uid('cfg:tests-release')} /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tCODE_SIGN_IDENTITY = "-";
\t\t\t\tCODE_SIGNING_REQUIRED = NO;
\t\t\t\tOTHER_LDFLAGS = "-lsqlite3";
\t\t\t\tPRODUCT_NAME = "xingce-tests";
\t\t\t}};
\t\t\tname = Release;
\t\t}};

\t\t{uid('cfglist:project')} /* Build configuration list for PBXProject "XingceFloater" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{uid('cfg:project-debug')} /* Debug */,
\t\t\t\t{uid('cfg:project-release')} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{uid('cfglist:app')} /* Build configuration list for PBXNativeTarget "行测刷题器" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{uid('cfg:app-debug')} /* Debug */,
\t\t\t\t{uid('cfg:app-release')} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t{uid('cfglist:tests')} /* Build configuration list for PBXNativeTarget "xingce-tests" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{uid('cfg:tests-debug')} /* Debug */,
\t\t\t\t{uid('cfg:tests-release')} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t}};
\trootObject = {uid('project')} /* Project object */;
}}
"""

out = root / "XingceFloater.xcodeproj"
out.mkdir(exist_ok=True)
(out / "project.pbxproj").write_text(project, encoding="utf-8")
scheme_dir = out / "xcshareddata" / "xcschemes"
scheme_dir.mkdir(parents=True, exist_ok=True)
app_id = uid("target:app")
test_id = uid("target:tests")
project_id = uid("project")
(scheme_dir / "行测刷题器.xcscheme").write_text(f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1420"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app_id}"
               BuildableName = "XingceFloater.app"
               BlueprintName = "行测刷题器"
               ReferencedContainer = "container:XingceFloater.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_id}"
            BuildableName = "XingceFloater.app"
            BlueprintName = "行测刷题器"
            ReferencedContainer = "container:XingceFloater.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app_id}"
            BuildableName = "XingceFloater.app"
            BlueprintName = "行测刷题器"
            ReferencedContainer = "container:XingceFloater.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
""", encoding="utf-8")
print(out)
print("app", app_id, "tests", test_id, "project", project_id)
