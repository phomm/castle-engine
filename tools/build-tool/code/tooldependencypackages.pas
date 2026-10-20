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

{ List installed dependency package IDs from the project manifest. }
procedure ReadInstalledPackages(const ManifestFileName: String;
  const PackageIds: TStrings);

{ List installed dependency package IDs from the project manifest to stdout. }
procedure GetInstalledPackages(const ManifestFileName: String);

{ Add a dependency package ID to the project manifest. }
procedure InstallPackage(const ManifestFileName, PackageId: String);

{ Check that a dependency package ID is installed.
  Package IDs do not currently have additional metadata to update. }
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

procedure LoadPackages(const ManifestFileName: String;
  out Document: TXMLDocument; out PackagesElement: TDOMElement;
  const PackageIds: TStrings);
var
  PackageSections, ChildElements: TXMLElementIterator;
  ChildElement: TDOMElement;
  PackageId: String;
begin
  Document := nil;
  PackagesElement := nil;
  try
    URLReadXML(Document, FilenameToUriSafe(ManifestFileName));
    if Document.DocumentElement.TagName <> 'project' then
      raise Exception.CreateFmt('Root node of "%s" must be <project>',
        [ManifestFileName]);

    PackageSections := Document.DocumentElement.ChildrenIterator(
      DependencyPackagesElementName);
    try
      if PackageSections.GetNext then
      begin
        PackagesElement := PackageSections.Current;
        if PackageSections.GetNext then
          raise Exception.CreateFmt('Multiple <%s> sections in "%s"',
            [DependencyPackagesElementName, ManifestFileName]);
      end;
    finally FreeAndNil(PackageSections) end;

    if PackagesElement = nil then
      Exit;

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
      end;
    finally FreeAndNil(ChildElements) end;
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

function PackageRepoUrl(const PackageId: String): String;
var
  Packages: TPackageInfoArray;
  I: Integer;
begin
  Packages := LoadPackageLibrary(DefaultPackagesLibraryUrl);
  for I := 0 to High(Packages) do
    if Packages[I].Id = PackageId then
    begin
      Result := Packages[I].RepoUrl;
      if Result = '' then
        raise Exception.CreateFmt('Package "%s" has no repository URL in the packages library',
          [PackageId]);
      Exit;
    end;

  raise Exception.CreateFmt('Package "%s" was not found in the packages library',
    [PackageId]);
end;

procedure ReadInstalledPackages(const ManifestFileName: String;
  const PackageIds: TStrings);
var
  Document: TXMLDocument;
  PackagesElement: TDOMElement;
begin
  PackageIds.Clear;
  LoadPackages(ManifestFileName, Document, PackagesElement, PackageIds);
  FreeAndNil(Document);
end;

procedure GetInstalledPackages(const ManifestFileName: String);
var
  PackageIds: TStringList;
  I: Integer;
  Output: String;
begin
  PackageIds := TStringList.Create;
  PackageIds.CaseSensitive := true;
  try
    ReadInstalledPackages(ManifestFileName, PackageIds);
    Output := '';
    for I := 0 to PackageIds.Count - 1 do
    begin
      if I > 0 then
        Output += ',';
      Output += PackageIds[I];
    end;
    Writeln(Output);
  finally FreeAndNil(PackageIds) end;
end;

procedure InstallPackage(const ManifestFileName, PackageId: String);
var
  Document: TXMLDocument;
  PackagesElement, PackageElement: TDOMElement;
  PackageIds: TStringList;
  CheckedId, RepoUrl: String;
begin
  CheckedId := CheckedPackageId(PackageId);
  RepoUrl := PackageRepoUrl(CheckedId);
  WritelnLog('DependencyPackages', Format(
    'Preparing to install package "%s" from %s', [CheckedId, RepoUrl]));
  PackageIds := TStringList.Create;
  PackageIds.CaseSensitive := true;
  try
    LoadPackages(ManifestFileName, Document, PackagesElement, PackageIds);
    try
      if PackageIds.IndexOf(CheckedId) <> -1 then
        Exit;

      if PackagesElement = nil then
      begin
        PackagesElement := Document.CreateElement(DependencyPackagesElementName);
        Document.DocumentElement.AppendChild(PackagesElement);
      end;

      PackageElement := Document.CreateElement(DependencyPackageElementName);
      PackageElement.AppendChild(Document.CreateTextNode(UTF8Decode(CheckedId)));
      PackagesElement.AppendChild(PackageElement);
      WriteXMLFile(Document, ManifestFileName);
    finally FreeAndNil(Document) end;
  finally FreeAndNil(PackageIds) end;
end;

procedure UpdatePackage(const ManifestFileName, PackageId: String);
var
  Document: TXMLDocument;
  PackagesElement: TDOMElement;
  PackageIds: TStringList;
  CheckedId, RepoUrl: String;
begin
  CheckedId := CheckedPackageId(PackageId);
  RepoUrl := PackageRepoUrl(CheckedId);
  WritelnLog('DependencyPackages', Format(
    'Preparing to update package "%s" from %s', [CheckedId, RepoUrl]));
  PackageIds := TStringList.Create;
  PackageIds.CaseSensitive := true;
  try
    LoadPackages(ManifestFileName, Document, PackagesElement, PackageIds);
    try
      if PackageIds.IndexOf(CheckedId) = -1 then
        raise Exception.CreateFmt('Package "%s" is not installed', [CheckedId]);
      Writeln('Package "', CheckedId,
        '" is listed in the manifest; there is no package metadata to update.');
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
  CheckedId := CheckedPackageId(PackageId);
  PackageIds := TStringList.Create;
  PackageIds.CaseSensitive := true;
  try
    LoadPackages(ManifestFileName, Document, PackagesElement, PackageIds);
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
            PackagesElement.RemoveChild(PackageElement);
            Break;
          end;
        end;
      finally FreeAndNil(ChildElements) end;

      if PackageIds.Count = 1 then
        Document.DocumentElement.RemoveChild(PackagesElement);
      WriteXMLFile(Document, ManifestFileName);
    finally FreeAndNil(Document) end;
  finally FreeAndNil(PackageIds) end;
end;

end.
