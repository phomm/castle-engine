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

{ Dependency package commands. }
unit ToolDependencyPackages;

{$I castleconf.inc}

interface

uses Classes;

{ List installed dependency package IDs from the project manifest.
  UseLogOutput writes diagnostic messages through WritelnLog instead of stdout,
  which is useful when called directly from a GUI application. }
procedure ReadInstalledPackages(const ManifestFileName: String;
  const PackageIds: TStrings; const UseLogOutput: Boolean = false);

{ List installed dependency package IDs from the project manifest to stdout. }
procedure GetInstalledPackages(const ManifestFileName: String);

{ Add a dependency package ID to the project manifest. }
procedure InstallPackage(const ManifestFileName, PackageId: String);

{ Check that a dependency package ID is installed.
  Package metadata, including its supported features, is read from the package library. }
procedure UpdatePackage(const ManifestFileName, PackageId: String);

{ Remove a dependency package ID from the project manifest. }
procedure RemovePackage(const ManifestFileName, PackageId: String);

implementation

uses SysUtils,
  CastleUriUtils, CastleXmlUtils,
  CastleDownload,
  CastleLog,
  ToolPackageLibrary,
  DOM, XMLWrite;

const
  DependencyPackagesElementName = 'dependency_packages';
  DependencyPackageElementName = 'package';
  PackagesLibraryUrlEnvironmentVariable = 'CASTLE_PACKAGES_LIBRARY_URL';

procedure DependencyPackagesWrite(const Message: String;
  const UseLogOutput: Boolean = false; const UsePrefix: Boolean = true);
begin
  if UseLogOutput then
    WritelnLog('DependencyPackages', Message)
  else
  if UsePrefix then
    Writeln('[DependencyPackages] ', Message)
  else
    Writeln(Message);
end;

procedure LoadPackages(const ManifestFileName: String;
  out Document: TXMLDocument; out PackagesElement: TDOMElement;
  const PackageIds: TStrings; const UseLogOutput: Boolean);
var
  PackageSections, ChildElements: TXMLElementIterator;
  ChildElement: TDOMElement;
  PackageId: String;
begin
  Document := nil;
  PackagesElement := nil;
  try
    DependencyPackagesWrite(
      Format('Loading manifest "%s"', [ManifestFileName]), UseLogOutput);
    URLReadXML(Document, FilenameToUriSafe(ManifestFileName));
    DependencyPackagesWrite(
      Format('Loaded root element <%s>', [Document.DocumentElement.TagName]),
      UseLogOutput);
    if Document.DocumentElement.TagName <> 'project' then
      raise Exception.CreateFmt('Root node of "%s" must be <project>',
        [ManifestFileName]);

    PackageSections := Document.DocumentElement.ChildrenIterator(DependencyPackagesElementName);

    if PackageSections = nil then
    begin
      DependencyPackagesWrite(
        'No packages section to read from project manifest', UseLogOutput);
      Exit;
    end;

    try
      if PackageSections.GetNext then
      begin
        PackagesElement := PackageSections.Current;
        DependencyPackagesWrite(Format('Found <%s> section',
          [DependencyPackagesElementName]), UseLogOutput);
        if PackageSections.GetNext then
          raise Exception.CreateFmt('Multiple <%s> sections in "%s"',
            [DependencyPackagesElementName, ManifestFileName]);
      end else
      begin
        DependencyPackagesWrite(Format('No <%s> section found',
          [DependencyPackagesElementName]), UseLogOutput);
      end;
    finally FreeAndNil(PackageSections) end;

    if PackagesElement = nil then
    begin
      DependencyPackagesWrite(
        'No packages section to read from project manifest', UseLogOutput);
      Exit;
    end;

    ChildElements := PackagesElement.ChildrenIterator;
    try
      while ChildElements.GetNext do
      begin
        ChildElement := ChildElements.Current;
        if ChildElement.TagName <> DependencyPackageElementName then
          raise Exception.CreateFmt('Unexpected <%s> element inside <%s> in "%s"',
            [ChildElement.TagName, DependencyPackagesElementName, ManifestFileName]);
        PackageId := Trim(ChildElement.TextData);
        if PackageId = '' then
          raise Exception.CreateFmt('Empty package ID in "%s"', [ManifestFileName]);
        if PackageIds.IndexOf(PackageId) <> -1 then
          raise Exception.CreateFmt('Duplicate package ID "%s" in "%s"',
            [PackageId, ManifestFileName]);
        PackageIds.Add(PackageId);
        DependencyPackagesWrite(
          Format('Read package "%s"', [PackageId]), UseLogOutput);
      end;
    finally FreeAndNil(ChildElements) end;
    DependencyPackagesWrite(Format('Read %d package(s) from manifest',
      [PackageIds.Count]), UseLogOutput);
  except
    FreeAndNil(Document);
    raise;
  end;
end;

function CheckedPackageId(const PackageId: String): String;
begin
  Result := Trim(PackageId);
  if Result = '' then
    raise Exception.Create('Package ID cannot be empty');
end;

function PackageInfoById(const PackageId: String): TPackageInfo;
var
  Packages: TPackageInfoArray;
  PackagesLibraryUrl: String;
  I: Integer;
begin
  PackagesLibraryUrl := GetEnvironmentVariable(PackagesLibraryUrlEnvironmentVariable);
  if PackagesLibraryUrl = '' then
    PackagesLibraryUrl := DefaultPackagesLibraryUrl;
  Packages := LoadPackageLibrary(PackagesLibraryUrl);
  for I := 0 to High(Packages) do
    if Packages[I].Id = PackageId then
    begin
      Result := Packages[I];
      if Result.RepoUrl = '' then
        raise Exception.CreateFmt('Package "%s" has no repository URL in the packages library',
          [PackageId]);
      Exit;
    end;

  raise Exception.CreateFmt('Package "%s" was not found in the packages library',
    [PackageId]);
end;

procedure WritePackageFeatures(const PackageInfo: TPackageInfo);
var
  I: Integer;
begin
  for I := 0 to High(PackageInfo.Features) do
    DependencyPackagesWrite('Package feature is ' + PackageInfo.Features[I]);
end;

procedure ReadInstalledPackages(const ManifestFileName: String;
  const PackageIds: TStrings; const UseLogOutput: Boolean);
var
  Document: TXMLDocument;
  PackagesElement: TDOMElement;
begin
  PackageIds.Clear;
  LoadPackages(ManifestFileName, Document, PackagesElement, PackageIds,
    UseLogOutput);
  FreeAndNil(Document);
end;

procedure GetInstalledPackages(const ManifestFileName: String);
var
  PackageIds: TStringList;
begin
  PackageIds := TStringList.Create;
  PackageIds.CaseSensitive := true;
  try
    DependencyPackagesWrite(Format('Listing installed packages in "%s"',
      [ManifestFileName]));
    ReadInstalledPackages(ManifestFileName, PackageIds);
    DependencyPackagesWrite('Packages: ' + PackageIds.CommaText, false, false);
  finally FreeAndNil(PackageIds) end;
end;

procedure InstallPackage(const ManifestFileName, PackageId: String);
var
  Document: TXMLDocument;
  PackagesElement, PackageElement: TDOMElement;
  PackageIds: TStringList;
  CheckedId: String;
  PackageInfo: TPackageInfo;
begin
  DependencyPackagesWrite(Format('Install command: manifest="%s", package="%s"',
    [ManifestFileName, PackageId]));
  CheckedId := CheckedPackageId(PackageId);
  DependencyPackagesWrite(Format('Checked package ID is "%s"', [CheckedId]));
  PackageInfo := PackageInfoById(CheckedId);
  WritelnLog('DependencyPackages', Format(
    'Preparing to install package "%s" from %s', [CheckedId, PackageInfo.RepoUrl]));
  DependencyPackagesWrite('Package repository URL is ' + PackageInfo.RepoUrl);
  WritePackageFeatures(PackageInfo);
  PackageIds := TStringList.Create;
  PackageIds.CaseSensitive := true;
  try
    LoadPackages(ManifestFileName, Document, PackagesElement, PackageIds, false);
    try
      if PackageIds.IndexOf(CheckedId) <> -1 then
      begin
        DependencyPackagesWrite(Format(
          'Package "%s" is already listed; manifest will not be changed',
          [CheckedId]));
        Exit;
      end;

      if PackagesElement = nil then
      begin
        DependencyPackagesWrite(Format('Creating <%s> section',
          [DependencyPackagesElementName]));
        PackagesElement := Document.CreateElement(DependencyPackagesElementName);
        Document.DocumentElement.AppendChild(PackagesElement);
        DependencyPackagesWrite(Format('Appended <%s> to <%s>',
          [DependencyPackagesElementName, Document.DocumentElement.TagName]));
      end;

      PackageElement := Document.CreateElement(DependencyPackageElementName);
      PackageElement.AppendChild(Document.CreateTextNode(UTF8Decode(CheckedId)));
      DependencyPackagesWrite(Format('Appending <%s> with text "%s" to <%s>',
        [DependencyPackageElementName, CheckedId, DependencyPackagesElementName]));
      PackagesElement.AppendChild(PackageElement);
      DependencyPackagesWrite('Appended package node; writing manifest "' +
        ManifestFileName + '"');
      WriteXMLFile(Document, ManifestFileName);
      DependencyPackagesWrite('Manifest write completed: "' +
        ManifestFileName + '"');
    finally FreeAndNil(Document) end;
  finally FreeAndNil(PackageIds) end;
end;

procedure UpdatePackage(const ManifestFileName, PackageId: String);
var
  Document: TXMLDocument;
  PackagesElement: TDOMElement;
  PackageIds: TStringList;
  CheckedId: String;
  PackageInfo: TPackageInfo;
begin
  DependencyPackagesWrite(Format('Update command: manifest="%s", package="%s"',
    [ManifestFileName, PackageId]));
  CheckedId := CheckedPackageId(PackageId);
  DependencyPackagesWrite(Format('Checked package ID is "%s"', [CheckedId]));
  PackageInfo := PackageInfoById(CheckedId);
  WritelnLog('DependencyPackages', Format(
    'Preparing to update package "%s" from %s', [CheckedId, PackageInfo.RepoUrl]));
  DependencyPackagesWrite('Package repository URL is ' + PackageInfo.RepoUrl);
  WritePackageFeatures(PackageInfo);
  PackageIds := TStringList.Create;
  PackageIds.CaseSensitive := true;
  try
    LoadPackages(ManifestFileName, Document, PackagesElement, PackageIds, false);
    try
      if PackageIds.IndexOf(CheckedId) = -1 then
        raise Exception.CreateFmt('Package "%s" is not installed', [CheckedId]);
      DependencyPackagesWrite(Format(
        'Package "%s" is listed in the manifest; no manifest write is needed',
        [CheckedId]));
      DependencyPackagesWrite(Format(
        'Package "%s" is listed in the manifest; there is no package metadata to update.',
        [CheckedId]), false, false);
    finally FreeAndNil(Document) end;
  finally FreeAndNil(PackageIds) end;
end;

procedure RemovePackage(const ManifestFileName, PackageId: String);
var
  Document: TXMLDocument;
  PackagesElement, PackageElement: TDOMElement;
  ChildElements: TXMLElementIterator;
  PackageIds: TStringList;
  CheckedId: String;
begin
  DependencyPackagesWrite(Format('Remove command: manifest="%s", package="%s"',
    [ManifestFileName, PackageId]));
  CheckedId := CheckedPackageId(PackageId);
  DependencyPackagesWrite(Format('Checked package ID is "%s"', [CheckedId]));
  PackageIds := TStringList.Create;
  PackageIds.CaseSensitive := true;
  try
    LoadPackages(ManifestFileName, Document, PackagesElement, PackageIds, false);
    try
      if PackageIds.IndexOf(CheckedId) = -1 then
        raise Exception.CreateFmt('Package "%s" is not installed', [CheckedId]);

      ChildElements := PackagesElement.ChildrenIterator(DependencyPackageElementName);
      try
        while ChildElements.GetNext do
        begin
          PackageElement := ChildElements.Current;
          if Trim(PackageElement.TextData) = CheckedId then
          begin
            DependencyPackagesWrite(Format('Removing <%s> node with text "%s"',
              [DependencyPackageElementName, CheckedId]));
            PackagesElement.RemoveChild(PackageElement);
            Break;
          end;
        end;
      finally FreeAndNil(ChildElements) end;

      if PackageIds.Count = 1 then
      begin
        DependencyPackagesWrite(Format('Removing now-empty <%s> section',
          [DependencyPackagesElementName]));
        Document.DocumentElement.RemoveChild(PackagesElement);
      end;
      DependencyPackagesWrite('Writing manifest "' + ManifestFileName + '"');
      WriteXMLFile(Document, ManifestFileName);
      DependencyPackagesWrite('Manifest write completed: "' +
        ManifestFileName + '"');
    finally FreeAndNil(Document) end;
  finally FreeAndNil(PackageIds) end;
end;

end.
