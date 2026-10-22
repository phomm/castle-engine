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

uses Classes, DOM;

{ List installed dependency package IDs from the project manifest.
  UseLogOutput writes diagnostic messages through WritelnLog instead of stdout,
  which is useful when called directly from a GUI application. }
procedure ReadInstalledPackages(const ManifestFileName: String;
  const PackageIds: TStrings; const UseLogOutput: Boolean = false);

{ List installed dependency package IDs from the project manifest to stdout. }
procedure GetInstalledPackages(const ManifestFileName: String);

{ Add a dependency package ID to the project manifest. }
procedure InstallPackage(const ManifestFileName, PackageId: String);

{ Add package directories containing Pascal source files to compiler search paths. }
procedure AddPackageCodeSearchPaths(const Document: TXMLDocument;
  const PackageId, PackageDirectory: String);

{ Find Pascal units anywhere under PackageDirectory that register serializable
  components, and add them to editor_units. }
procedure AddPackageEditorUnits(const Document: TXMLDocument;
  const PackageDirectory: String);

{ Check that a dependency package ID is installed.
  Package metadata, including its supported features, is read from the package library. }
procedure UpdatePackage(const ManifestFileName, PackageId: String);

{ Remove a dependency package ID from the project manifest. }
procedure RemovePackage(const ManifestFileName, PackageId: String);

implementation

uses SysUtils,
  CastleUriUtils, CastleXmlUtils, CastleFilesUtils,
  CastleDownload,
  CastleLog,
  ToolPackageLibrary, ToolGitDownload,
  XMLWrite;

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

function CheckedPackageDirectoryName(const PackageId: String): String;
begin
  Result := PackageId;
  if (Result = '.') or (Result = '..') or
    (Pos('/', Result) <> 0) or (Pos('\', Result) <> 0) or
    (Pos(':', Result) <> 0) then
    raise Exception.CreateFmt('Package ID "%s" cannot be used as a directory name',
      [PackageId]);
end;

function ChildElementOrCreate(const Parent: TDOMElement;
  const ChildName: String): TDOMElement;
var
  Children: TXMLElementIterator;
begin
  Result := nil;
  Children := Parent.ChildrenIterator(ChildName);
  if Children <> nil then
  try
    while Children.GetNext do
    begin
      if Result <> nil then
        raise Exception.CreateFmt('Multiple <%s> elements inside <%s>',
          [ChildName, Parent.TagName]);
      Result := Children.Current;
    end;
  finally FreeAndNil(Children) end;

  if Result = nil then
    Result := Parent.CreateChild(ChildName);
end;

procedure AddPackageCodeSearchPath(const Document: TXMLDocument;
  const PackageId, RelativeDirectory: String);
var
  CompilerOptions, SearchPaths, PathElement: TDOMElement;
  Paths: TXMLElementIterator;
  SearchPath: String;
begin
  SearchPath := 'packages/' + CheckedPackageDirectoryName(PackageId) + '/';
  if RelativeDirectory <> '' then
    SearchPath := SearchPath + StringReplace(RelativeDirectory, '\', '/',
      [rfReplaceAll]) + '/';
  CompilerOptions := ChildElementOrCreate(Document.DocumentElement,
    'compiler_options');
  SearchPaths := ChildElementOrCreate(CompilerOptions, 'search_paths');

  Paths := SearchPaths.ChildrenIterator('path');
  if Paths <> nil then
  try
    while Paths.GetNext do
      if Paths.Current.AttributeString('value') = SearchPath then
        Exit;
  finally FreeAndNil(Paths) end;

  PathElement := SearchPaths.CreateChild('path');
  PathElement.SetAttribute('value', UTF8Decode(SearchPath));
end;

procedure AddPackageCodeSearchPathsInDirectory(const Document: TXMLDocument;
  const PackageId, PackageDirectory, RelativeDirectory: String);
var
  Search: TSearchRec;
  SearchResult: Integer;
  EntryName, SourcePath, ChildRelativeDirectory, Extension: String;
  HasPascalFile: Boolean;
begin
  HasPascalFile := false;
  SearchResult := FindFirst(IncludeTrailingPathDelimiter(PackageDirectory) + '*',
    faAnyFile, Search);
  if SearchResult <> 0 then
    Exit;
  try
    repeat
      EntryName := Search.Name;
      if (EntryName <> '.') and (EntryName <> '..') then
      begin
        SourcePath := CombinePaths(PackageDirectory, EntryName);
        if (Search.Attr and faDirectory) <> 0 then
        begin
          if RelativeDirectory = '' then
            ChildRelativeDirectory := EntryName
          else
            ChildRelativeDirectory := CombinePaths(RelativeDirectory, EntryName);
          AddPackageCodeSearchPathsInDirectory(Document, PackageId, SourcePath,
            ChildRelativeDirectory);
        end else
        begin
          Extension := LowerCase(ExtractFileExt(EntryName));
          if (Extension = '.pas') or (Extension = '.pp') then
            HasPascalFile := true;
        end;
      end;
      SearchResult := FindNext(Search);
    until SearchResult <> 0;
  finally FindClose(Search) end;

  if HasPascalFile then
    AddPackageCodeSearchPath(Document, PackageId, RelativeDirectory);
end;

procedure AddPackageCodeSearchPaths(const Document: TXMLDocument;
  const PackageId, PackageDirectory: String);
begin
  if not DirectoryExists(PackageDirectory) then
    raise Exception.CreateFmt('Package directory "%s" does not exist',
      [PackageDirectory]);
  AddPackageCodeSearchPathsInDirectory(Document, PackageId, PackageDirectory, '');
end;

function PascalUnitName(const SourceFileName, Source: String): String;
var
  Lines: TStringList;
  I, SemicolonPosition: Integer;
  Declaration, Line: String;
  FoundUnitKeyword: Boolean;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Source;
    Declaration := '';
    FoundUnitKeyword := false;
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if not FoundUnitKeyword then
      begin
        if LowerCase(Line) = 'unit' then
        begin
          FoundUnitKeyword := true;
          Continue;
        end;
        if
          ((LowerCase(Copy(Line, 1, 4)) <> 'unit') or
           (Length(Line) < 5) or (Line[5] > ' ')) then
          Continue;
        FoundUnitKeyword := true;
        Declaration := Trim(Copy(Line, 5, MaxInt));
      end else
        Declaration := Declaration + ' ' + Line;

      SemicolonPosition := Pos(';', Declaration);
      if SemicolonPosition <> 0 then
        Exit(Trim(Copy(Declaration, 1, SemicolonPosition - 1)));
    end;
  finally FreeAndNil(Lines) end;

  raise Exception.CreateFmt(
    'Cannot find Pascal unit declaration in "%s", which calls RegisterSerializableComponent',
    [SourceFileName]);
end;

procedure AddEditorUnit(const Document: TXMLDocument;
  const UnitName: String);
var
  CurrentUnits, UnitListEntry: String;
  StartPosition, SeparatorPosition: Integer;
  UnitFound: Boolean;
begin
  CurrentUnits := Document.DocumentElement.AttributeStringDef('editor_units', '');
  StartPosition := 1;
  UnitFound := false;
  while StartPosition <= Length(CurrentUnits) do
  begin
    SeparatorPosition := Pos(',', Copy(CurrentUnits, StartPosition, MaxInt));
    if SeparatorPosition = 0 then
    begin
      UnitListEntry := Trim(Copy(CurrentUnits, StartPosition, MaxInt));
      StartPosition := Length(CurrentUnits) + 1;
    end else
    begin
      UnitListEntry := Trim(Copy(CurrentUnits, StartPosition,
        SeparatorPosition - 1));
      Inc(StartPosition, SeparatorPosition);
    end;
    if SameText(UnitListEntry, UnitName) then
      UnitFound := true;
  end;

  if not UnitFound then
  begin
    if CurrentUnits <> '' then
      CurrentUnits := CurrentUnits + ',';
    CurrentUnits := CurrentUnits + UnitName;
    Document.DocumentElement.SetAttribute('editor_units',
      UTF8Decode(CurrentUnits));
  end;
end;

procedure AddPackageEditorUnits(const Document: TXMLDocument;
  const PackageDirectory: String);
var
  Search: TSearchRec;
  SearchResult: Integer;
  EntryName, FileName, Contents, Extension: String;
begin
  if not DirectoryExists(PackageDirectory) then
    raise Exception.CreateFmt(
      'Package directory "%s" is required by the register-editor feature',
      [PackageDirectory]);

  SearchResult := FindFirst(IncludeTrailingPathDelimiter(PackageDirectory) + '*',
    faAnyFile, Search);
  if SearchResult <> 0 then
    Exit;
  try
    repeat
      EntryName := Search.Name;
      if (EntryName <> '.') and (EntryName <> '..') then
      begin
        FileName := CombinePaths(PackageDirectory, EntryName);
        if (Search.Attr and faDirectory) <> 0 then
          AddPackageEditorUnits(Document, FileName)
        else
        begin
          Extension := LowerCase(ExtractFileExt(EntryName));
          if (Extension = '.pas') or (Extension = '.pp') then
          begin
            Contents := FileToString(FilenameToUriSafe(FileName));
            if Pos('registerserializablecomponent',
              LowerCase(Contents)) <> 0 then
              AddEditorUnit(Document, PascalUnitName(FileName, Contents));
          end;
        end;
      end;
      SearchResult := FindNext(Search);
    until SearchResult <> 0;
  finally FindClose(Search) end;
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

function PackageHasFeature(const PackageInfo: TPackageInfo;
  const Feature: String): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(PackageInfo.Features) do
    if PackageInfo.Features[I] = Feature then
      Exit(true);
  Result := false;
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
  AlreadyInstalled: Boolean;
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
      AlreadyInstalled := PackageIds.IndexOf(CheckedId) <> -1;
      if AlreadyInstalled then
      begin
        DependencyPackagesWrite(Format(
          'Package "%s" is already listed; refreshing installed package files',
          [CheckedId]));
      end;

      if PackageHasFeature(PackageInfo, PackageFeatureCopyCode) or
        PackageHasFeature(PackageInfo, PackageFeatureCopyData) then
      begin
        DependencyPackagesWrite(Format('Downloading package "%s"',
          [CheckedId]));
        PackageInfo.Id := CheckedPackageDirectoryName(CheckedId);
        DownloadPackage(PackageInfo,
          ExtractFileDir(ExpandFileName(ManifestFileName)));
      end;

      if PackageHasFeature(PackageInfo, PackageFeatureCopyCode) then
        AddPackageCodeSearchPaths(Document, CheckedId, CombinePaths(
          ExtractFileDir(ExpandFileName(ManifestFileName)),
          CombinePaths('packages', CheckedPackageDirectoryName(CheckedId))));

      if PackageHasFeature(PackageInfo, PackageFeatureRegisterEditor) then
        AddPackageEditorUnits(Document, CombinePaths(
          ExtractFileDir(ExpandFileName(ManifestFileName)),
          CombinePaths('packages', CheckedPackageDirectoryName(CheckedId))));

      if PackagesElement = nil then
      begin
        DependencyPackagesWrite(Format('Creating <%s> section',
          [DependencyPackagesElementName]));
        PackagesElement := Document.CreateElement(DependencyPackagesElementName);
        Document.DocumentElement.AppendChild(PackagesElement);
        DependencyPackagesWrite(Format('Appended <%s> to <%s>',
          [DependencyPackagesElementName, Document.DocumentElement.TagName]));
      end;

      if not AlreadyInstalled then
      begin
        PackageElement := Document.CreateElement(DependencyPackageElementName);
        PackageElement.AppendChild(Document.CreateTextNode(UTF8Decode(CheckedId)));
        DependencyPackagesWrite(Format('Appending <%s> with text "%s" to <%s>',
          [DependencyPackageElementName, CheckedId, DependencyPackagesElementName]));
        PackagesElement.AppendChild(PackageElement);
      end;
      if AlreadyInstalled then
        DependencyPackagesWrite('Writing updated manifest "' +
          ManifestFileName + '"')
      else
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
