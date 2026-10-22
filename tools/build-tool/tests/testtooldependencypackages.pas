{
  Copyright 2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.md,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automatic tests of dependency package commands in the build tool. }
unit TestToolDependencyPackages;

interface

uses
  Classes, SysUtils, DOM, CastleTester;

type
  TTestToolDependencyPackages = class(TCastleTestCase)
  published
    procedure TestGitRepositoryUrlAnalysis;
    procedure TestGitAvailability;
    procedure TestSeparateToolProjectDirectory;
    procedure TestPackageDataDirectory;
    procedure TestPackageCodeSearchPath;
    procedure TestPackageEditorUnits;
    procedure TestCommands;
  end;

implementation

uses
  CastleFilesUtils, CastleInternalArchitectures, CastleInternalProcess,
  CastleXmlUtils,
  CastleUtils,
  CastleUriUtils, ToolCommonUtils, ToolDependencyPackages, ToolGitDownload;

const
  FirstPackageId = 'test-package-one';
  SecondPackageId = 'test-package-two';

procedure TTestToolDependencyPackages.TestGitRepositoryUrlAnalysis;
var
  Reference: TGitRepositoryReference;
begin
  Reference := AnalyzeGitRepositoryUrl('https://github.com/user/repository/');
  AssertEquals('https://github.com/user/repository', Reference.RepositoryUrl);
  AssertEquals('', Reference.Branch);
  AssertEquals('', Reference.Path);

  Reference := AnalyzeGitRepositoryUrl(
    'https://github.com/user/repository/blob/main/src/component.pas');
  AssertEquals('https://github.com/user/repository', Reference.RepositoryUrl);
  AssertEquals('main', Reference.Branch);
  AssertEquals('src/component.pas', Reference.Path);
  AssertTrue(Reference.IsSingleFile);
  AssertEquals('https://raw.githubusercontent.com/user/repository/main/src/component.pas',
    Reference.RawFileUrl);

  Reference := AnalyzeGitRepositoryUrl(
    'https://github.com/user/repository/src/component.pas');
  AssertEquals('https://github.com/user/repository', Reference.RepositoryUrl);
  AssertEquals('', Reference.Branch);
  AssertEquals('src/component.pas', Reference.Path);

  Reference := AnalyzeGitRepositoryUrl(
    'https://gitlab.com/user/repository/-/blob/master/src/component.pas');
  AssertEquals('https://gitlab.com/user/repository', Reference.RepositoryUrl);
  AssertEquals('master', Reference.Branch);
  AssertEquals('src/component.pas', Reference.Path);
  AssertTrue(Reference.IsSingleFile);
  AssertEquals('', Reference.RawFileUrl);
end;

procedure TTestToolDependencyPackages.TestGitAvailability;
var
  ProjectDirectory: String;
begin
  if not IsGitInstalled then
    Exit;

  ProjectDirectory := CreateTemporaryDir;
  try
    AssertFalse(CanOperateGitProject(ProjectDirectory));
    ExecuteCommandCheckStatus(ProjectDirectory, 'git', ['init']);
    AssertTrue(CanOperateGitProject(ProjectDirectory));
  finally
    RemoveNonEmptyDir(ProjectDirectory);
  end;
end;

procedure TTestToolDependencyPackages.TestSeparateToolProjectDirectory;
var
  Directory: String;
begin
  Directory := CreateTemporaryDir;
  try
    StringToFile(FilenameToUriSafe(CombinePaths(Directory, 'component.pas')),
      'unit Component;');
    AssertFalse(IsSeparateToolProjectDirectory(Directory));

    StringToFile(FilenameToUriSafe(CombinePaths(Directory, 'standalone.lpi')),
      '<CONFIG/>');
    AssertTrue(IsSeparateToolProjectDirectory(Directory));
    DeleteFile(CombinePaths(Directory, 'standalone.lpi'));

    StringToFile(FilenameToUriSafe(CombinePaths(Directory, 'tool.dproj')),
      '<Project/>');
    AssertTrue(IsSeparateToolProjectDirectory(Directory));
    DeleteFile(CombinePaths(Directory, 'tool.dproj'));

    StringToFile(FilenameToUriSafe(CombinePaths(Directory, 'app.lpr')),
      'program App;');
    AssertTrue(IsSeparateToolProjectDirectory(Directory));
  finally
    RemoveNonEmptyDir(Directory);
  end;
end;

procedure TTestToolDependencyPackages.TestPackageDataDirectory;
const
  DataExtensions: array [0..5] of String = (
    '.png', '.wav', '.glsl', '.gltf', '.castle-user-interface', '.pas'
  );
var
  Directory, FileName: String;
  I: Integer;
begin
  Directory := CreateTemporaryDir;
  try
    for I := 0 to High(DataExtensions) do
    begin
      FileName := CombinePaths(Directory, 'asset' + DataExtensions[I]);
      StringToFile(FilenameToUriSafe(FileName), 'test');
      AssertEquals(I < High(DataExtensions),
        DirectoryContainsPackageData(Directory, false, false));
      DeleteFile(FileName);
    end;

    CheckForceDirectories(CombinePaths(Directory, 'tests'));
    StringToFile(FilenameToUriSafe(
      CombinePaths(Directory, 'tests' + PathDelim + 'hidden.png')), 'test');
    AssertFalse(DirectoryContainsPackageData(Directory, true, false));
    AssertTrue(DirectoryContainsPackageData(Directory, false, false));

    CheckForceDirectories(CombinePaths(Directory, 'tools'));
    StringToFile(FilenameToUriSafe(
      CombinePaths(Directory, 'tools' + PathDelim + 'hidden.png')), 'test');
    StringToFile(FilenameToUriSafe(
      CombinePaths(Directory, 'tools' + PathDelim + 'standalone.lpi')), '<CONFIG/>');
    AssertFalse(DirectoryContainsPackageData(Directory, true, true));
    AssertTrue(DirectoryContainsPackageData(Directory, false, false));
  finally
    RemoveNonEmptyDir(Directory);
  end;
end;

procedure TTestToolDependencyPackages.TestPackageCodeSearchPath;
var
  Document: TXMLDocument;
  PackageDirectory, NestedDirectory: String;
  CompilerOptions, SearchPaths: TDOMElement;
  Children: TXMLElementIterator;
  Paths: TStringList;
begin
  PackageDirectory := CreateTemporaryDir;
  Document := TXMLDocument.Create;
  try
    Document.AppendChild(Document.CreateElement('project'));
    NestedDirectory := CombinePaths(PackageDirectory, 'castle-bars');
    CheckForceDirectories(NestedDirectory);
    StringToFile(FilenameToUriSafe(CombinePaths(NestedDirectory, 'component.pas')),
      'unit Component;');
    StringToFile(FilenameToUriSafe(CombinePaths(PackageDirectory, 'root.pp')),
      'unit Root;');
    AddPackageCodeSearchPaths(Document, 'test-package', PackageDirectory);
    AddPackageCodeSearchPaths(Document, 'test-package', PackageDirectory);

    CompilerOptions := Document.DocumentElement.ChildElement('compiler_options');
    SearchPaths := CompilerOptions.ChildElement('search_paths');
    Children := SearchPaths.ChildrenIterator('path');
    Paths := TStringList.Create;
    try
      while Children.GetNext do
        Paths.Add(Children.Current.AttributeString('value'));
      AssertEquals(2, Paths.Count);
      AssertTrue(Paths.IndexOf('packages/test-package/castle-bars/') <> -1);
      AssertTrue(Paths.IndexOf('packages/test-package/') <> -1);
    finally
      FreeAndNil(Paths);
      FreeAndNil(Children);
    end;
  finally
    FreeAndNil(Document);
    RemoveNonEmptyDir(PackageDirectory);
  end;
end;

procedure TTestToolDependencyPackages.TestPackageEditorUnits;
var
  Document: TXMLDocument;
  PackageDirectory, SourceDirectory: String;
  EditorUnits: String;
begin
  PackageDirectory := CreateTemporaryDir;
  Document := TXMLDocument.Create;
  try
    Document.AppendChild(Document.CreateElement('project'));
    SourceDirectory := CombinePaths(PackageDirectory, 'source-files');
    CheckForceDirectories(SourceDirectory);
    StringToFile(FilenameToUriSafe(CombinePaths(SourceDirectory, 'component.pas')),
      'unit PackageComponent;' + LineEnding +
      'initialization' + LineEnding +
      '  RegisterSerializableComponent(TComponent, ''Component'');');
    StringToFile(FilenameToUriSafe(CombinePaths(PackageDirectory, 'other.pp')),
      'unit PackageOther;' + LineEnding +
      'initialization' + LineEnding +
      '  RegisterSerializableComponent(TOther, ''Other'');');
    AddPackageEditorUnits(Document, PackageDirectory);
    EditorUnits := Document.DocumentElement.AttributeString('editor_units');
    AssertTrue(Pos('PackageComponent', EditorUnits) <> 0);
    AssertTrue(Pos('PackageOther', EditorUnits) <> 0);

    Document.DocumentElement.SetAttribute('editor_units', 'ExistingUnit, packagecomponent');
    AddPackageEditorUnits(Document, PackageDirectory);
    AssertEquals('ExistingUnit, packagecomponent,PackageOther',
      Document.DocumentElement.AttributeString('editor_units'));
  finally
    FreeAndNil(Document);
    RemoveNonEmptyDir(PackageDirectory);
  end;
end;

procedure TTestToolDependencyPackages.TestCommands;
var
  BuildToolExecutable, ProjectDirectory, PackageLibraryFileName,
    ManifestFileName, Output, ManifestBeforeUpdate: String;

  procedure RunBuildTool(const Parameters: array of String;
    const ExpectedExitStatus: Integer; out Output: String);
  var
    Environment: TStringList;
    ExitStatus: Integer;
  begin
    Environment := EnvironmentStrings;
    try
      Environment.Values['CASTLE_PACKAGES_LIBRARY_URL'] :=
        FilenameToUriSafe(PackageLibraryFileName);
      ExecuteCommandCapture(ProjectDirectory, BuildToolExecutable, Parameters,
        Output, ExitStatus, nil, nil, [], Environment);
    finally FreeAndNil(Environment) end;

    if ExitStatus <> ExpectedExitStatus then
      Fail(Format('Command "%s" exited with status %d instead of %d. Output: %s',
        [Parameters[0], ExitStatus, ExpectedExitStatus, Output]));
  end;

  procedure AssertPackages(const ExpectedFirst, ExpectedSecond: String);
  var
    PackageIds: TStringList;
  begin
    PackageIds := TStringList.Create;
    PackageIds.CaseSensitive := true;
    try
      ReadInstalledPackages(ManifestFileName, PackageIds);
      if ExpectedFirst = '' then
        AssertEquals(0, PackageIds.Count)
      else
      if ExpectedSecond = '' then
      begin
        AssertEquals(1, PackageIds.Count);
        AssertEquals(ExpectedFirst, PackageIds[0]);
      end else
      begin
        AssertEquals(2, PackageIds.Count);
        AssertEquals(ExpectedFirst, PackageIds[0]);
        AssertEquals(ExpectedSecond, PackageIds[1]);
      end;
    finally FreeAndNil(PackageIds) end;
  end;

begin
  BuildToolExecutable := GetEnvironmentVariable('CASTLE_ENGINE_TEST_EXECUTABLE');
  if BuildToolExecutable = '' then
    BuildToolExecutable := CastleEnginePath + 'tools' + PathDelim +
      'build-tool' + PathDelim + 'castle-engine' + ExeExtension;
  if not RegularFileExists(BuildToolExecutable) then
    Fail('Cannot find build tool executable: ' + BuildToolExecutable);

  ProjectDirectory := CreateTemporaryDir;
  try
    ManifestFileName := CombinePaths(ProjectDirectory, 'CastleEngineManifest.xml');
    PackageLibraryFileName := CombinePaths(ProjectDirectory, 'packages.json');

    StringToFile(FilenameToUriSafe(ManifestFileName),
      '<?xml version="1.0" encoding="utf-8"?>' + LineEnding +
      '<project name="dependency-package-test">' +
      '<data exists="false" />' +
      '</project>' + LineEnding);
    StringToFile(FilenameToUriSafe(PackageLibraryFileName),
      '{"packages":[' +
      '{"id":"' + FirstPackageId + '","title":"Test package one",' +
        '"description":"","image":"","page":"https://example.invalid/one",' +
        '"author":"CGE tests","links":[],"features":["feature-one","feature-two"]},' +
      '{"id":"' + SecondPackageId + '","title":"Test package two",' +
        '"description":"","image":"","page":"https://example.invalid/two",' +
        '"author":"CGE tests","links":[],"features":[]}' +
      ']}');

    RunBuildTool(['get-installed-packages'], 0, Output);
    AssertTrue(Pos('Packages: ', Output) <> 0);
    AssertPackages('', '');

    RunBuildTool(['install-package', FirstPackageId], 0, Output);
    AssertTrue(Pos('Package feature is feature-one', Output) <> 0);
    AssertTrue(Pos('Package feature is feature-two', Output) <> 0);
    AssertTrue(Pos('[DependencyPackages] Appended package node; writing manifest ',
      Output) <> 0);
    AssertTrue(Pos('[DependencyPackages] Manifest write completed: ',
      Output) <> 0);
    AssertPackages(FirstPackageId, '');
    RunBuildTool(['install-package', FirstPackageId], 0, Output);
    AssertTrue(Pos('refreshing installed package files', Output) <> 0);
    AssertPackages(FirstPackageId, '');
    RunBuildTool(['install-package', SecondPackageId], 0, Output);
    AssertPackages(FirstPackageId, SecondPackageId);

    RunBuildTool(['get-installed-packages'], 0, Output);
    AssertTrue(Pos('Packages: ' + FirstPackageId + ',' + SecondPackageId,
      Output) <> 0);

    ManifestBeforeUpdate := FileToString(FilenameToUriSafe(ManifestFileName));
    RunBuildTool(['update-package', FirstPackageId], 0, Output);
    AssertTrue(Pos('Package feature is feature-one', Output) <> 0);
    AssertTrue(Pos('Package feature is feature-two', Output) <> 0);
    AssertTrue(Pos('there is no package metadata to update', Output) <> 0);
    AssertEquals(ManifestBeforeUpdate,
      FileToString(FilenameToUriSafe(ManifestFileName)));
    AssertPackages(FirstPackageId, SecondPackageId);

    RunBuildTool(['remove-package', FirstPackageId], 0, Output);
    AssertPackages(SecondPackageId, '');
    RunBuildTool(['remove-package', SecondPackageId], 0, Output);
    AssertPackages('', '');
    AssertTrue(Pos('<dependency_packages>', FileToString(
      FilenameToUriSafe(ManifestFileName))) = 0);

    RunBuildTool(['install-package', FirstPackageId], 0, Output);
    ManifestBeforeUpdate := FileToString(FilenameToUriSafe(ManifestFileName));
    RunBuildTool(['update-package', FirstPackageId], 0, Output);
    AssertEquals(ManifestBeforeUpdate,
      FileToString(FilenameToUriSafe(ManifestFileName)));

    RunBuildTool(['remove-package', 'not-installed'], 1, Output);
    AssertPackages(FirstPackageId, '');
  finally
    RemoveNonEmptyDir(ProjectDirectory);
  end;
end;

initialization
  RegisterTest(TTestToolDependencyPackages);
end.
