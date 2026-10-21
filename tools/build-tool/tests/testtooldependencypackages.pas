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
  Classes, SysUtils, CastleTester;

type
  TTestToolDependencyPackages = class(TCastleTestCase)
  published
    procedure TestCommands;
  end;

implementation

uses
  CastleFilesUtils, CastleInternalArchitectures, CastleInternalProcess,
  CastleUtils,
  CastleUriUtils, ToolCommonUtils, ToolDependencyPackages;

const
  FirstPackageId = 'test-package-one';
  SecondPackageId = 'test-package-two';

procedure TTestToolDependencyPackages.TestCommands;
var
  BuildToolExecutable, ProjectDirectory, PackageLibraryFileName,
    ManifestFileName, Output, ManifestBeforeUpdate: String;

  procedure RunBuildTool(const Parameters: array of String;
    const ExpectedExitStatus: Integer; out Output: String);
  var
    Process: TCastleProcess;
    Environment: TStringList;
    BytesRead: Integer;
    Buffer: array [0..1023] of Byte;
  begin
    Process := TCastleProcess.Create(nil);
    try
      Process.Executable := BuildToolExecutable;
      Process.CurrentDirectory := ProjectDirectory;
      Process.Options := [poUsePipes, poStderrToOutput];
      Process.Parameters.AddStrings(Parameters);

      Environment := EnvironmentStrings;
      try
        Environment.Values['CASTLE_PACKAGES_LIBRARY_URL'] :=
          FilenameToUriSafe(PackageLibraryFileName);
        Process.Environment := Environment;
      finally FreeAndNil(Environment) end;

      Process.Execute;
      Process.WaitOnExit;
      Output := '';
      repeat
        BytesRead := Process.Output.Read(Buffer, SizeOf(Buffer));
        if BytesRead > 0 then
          SetLength(Output, Length(Output) + BytesRead);
        if BytesRead > 0 then
          Move(Buffer, Output[Length(Output) - BytesRead + 1], BytesRead);
      until BytesRead = 0;

      if Process.ExitStatus <> ExpectedExitStatus then
        Fail(Format('Command "%s" exited with status %d instead of %d. Output: %s',
          [Parameters[0], Process.ExitStatus, ExpectedExitStatus, Output]));
    finally FreeAndNil(Process) end;
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
        '"author":"CGE tests","links":[]},' +
      '{"id":"' + SecondPackageId + '","title":"Test package two",' +
        '"description":"","image":"","page":"https://example.invalid/two",' +
        '"author":"CGE tests","links":[]}' +
      ']}');

    RunBuildTool(['get-installed-packages'], 0, Output);
    AssertEquals('', Trim(Output));
    AssertPackages('', '');

    RunBuildTool(['install-package', FirstPackageId], 0, Output);
    AssertPackages(FirstPackageId, '');
    RunBuildTool(['install-package', FirstPackageId], 0, Output);
    AssertPackages(FirstPackageId, '');
    RunBuildTool(['install-package', SecondPackageId], 0, Output);
    AssertPackages(FirstPackageId, SecondPackageId);

    RunBuildTool(['get-installed-packages'], 0, Output);
    AssertEquals(FirstPackageId + ',' + SecondPackageId, Trim(Output));

    ManifestBeforeUpdate := FileToString(FilenameToUriSafe(ManifestFileName));
    RunBuildTool(['update-package', FirstPackageId], 0, Output);
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
