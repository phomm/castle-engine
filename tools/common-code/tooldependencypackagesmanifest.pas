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

{ Read dependency package IDs from project manifests. }
unit ToolDependencyPackagesManifest;

{$I castleconf.inc}

interface

uses Classes, DOM;

{ Load a project manifest and read its dependency package IDs.
  The returned document and package section must be freed by the caller.
  UseLogOutput writes diagnostic messages through WritelnLog instead of stdout. }
procedure LoadDependencyPackagesManifest(const ManifestFileName: String;
  out Document: TXMLDocument; out PackagesElement: TDOMElement;
  const PackageIds: TStrings; const UseLogOutput: Boolean = false);

{ Read installed dependency package IDs from a project manifest. }
procedure ReadInstalledDependencyPackages(const ManifestFileName: String;
  const PackageIds: TStrings; const UseLogOutput: Boolean = false);

implementation

uses SysUtils,
  CastleUriUtils, CastleXmlUtils, CastleLog;

const
  DependencyPackagesElementName = 'dependency_packages';
  DependencyPackageElementName = 'package';

procedure DependencyPackagesWrite(const Message: String;
  const UseLogOutput: Boolean = false);
begin
  if UseLogOutput then
    WritelnLog('DependencyPackages', Message)
  else
    Writeln('[DependencyPackages] ', Message);
end;

procedure LoadDependencyPackagesManifest(const ManifestFileName: String;
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

    PackageSections := Document.DocumentElement.ChildrenIterator(
      DependencyPackagesElementName);
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
        DependencyPackagesWrite(Format('No <%s> section found',
          [DependencyPackagesElementName]), UseLogOutput);
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

procedure ReadInstalledDependencyPackages(const ManifestFileName: String;
  const PackageIds: TStrings; const UseLogOutput: Boolean);
var
  Document: TXMLDocument;
  PackagesElement: TDOMElement;
begin
  PackageIds.Clear;
  LoadDependencyPackagesManifest(ManifestFileName, Document, PackagesElement,
    PackageIds, UseLogOutput);
  FreeAndNil(Document);
end;

end.
