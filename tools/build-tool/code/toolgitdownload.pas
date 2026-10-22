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

{ Download code from a Git repository. }
unit ToolGitDownload;

{$I castleconf.inc}

interface

uses ToolPackageLibrary;

type
  { Git repository URL split into repository, branch and optional path. }
  TGitRepositoryReference = record
    { URL of the repository itself. }
    RepositoryUrl: String;
    { Branch to check out, empty to use the repository default branch. }
    Branch: String;
    { Optional path within the repository. }
    Path: String;
    { Whether the URL explicitly refers to a single file. }
    IsSingleFile: Boolean;
    { Direct raw URL, if this references a single file on GitHub. }
    RawFileUrl: String;
  end;

{ Analyze an HTTP(S) repository URL, optionally pointing to a file or directory
  within the repository. }
function AnalyzeGitRepositoryUrl(const Url: String): TGitRepositoryReference;

{ Return whether the Git executable can be found on the system PATH. }
function IsGitInstalled: Boolean;

{ Return whether ProjectDirectory is inside a Git worktree where git status
  succeeds. }
function CanOperateGitProject(const ProjectDirectory: String): Boolean;

{ Return whether a directory contains a project file identifying a separate
  tool project. }
function IsSeparateToolProjectDirectory(const Directory: String): Boolean;

{ Return whether a directory contains image, audio, shader, model, or
  Castle-format data files after applying the package folder filters. }
function DirectoryContainsPackageData(const Directory: String;
  const SkipTest, SkipTool: Boolean): Boolean;

{ Download the sources/data described by PackageInfo into ProjectDirectory.
  Code goes into packages/<id>, data into data/<id>. }
procedure DownloadPackage(const PackageInfo: TPackageInfo;
  const ProjectDirectory: String);

implementation

uses Classes, SysUtils,
  CastleDownload, CastleFilesUtils, CastleInternalProcess, CastleLog,
  CastleStringUtils;

function IsGitInstalled: Boolean;
begin
  Result := FindExe('git') <> '';
end;

function CanOperateGitProject(const ProjectDirectory: String): Boolean;
var
  Output: String;
  ExitStatus: Integer;
begin
  Result := false;
  if not IsGitInstalled then
    Exit;

  ExecuteCommandCapture(ProjectDirectory, 'git', ['status', '--short'],
    Output, ExitStatus);
  Result := ExitStatus = 0;
end;

function AnalyzeGitRepositoryUrl(const Url: String): TGitRepositoryReference;
var
  CleanUrl, Scheme, Authority, PathPart, RepositoryPath, ViewKind: String;
  PathSegments: TStringList;
  PathStart, SegmentStart, I, FirstPathSegment: Integer;
  IsGitHubOrGitLabPath: Boolean;
begin
  CleanUrl := Trim(Url);
  PathStart := Pos('?', CleanUrl);
  if PathStart <> 0 then
    Delete(CleanUrl, PathStart, MaxInt);
  PathStart := Pos('#', CleanUrl);
  if PathStart <> 0 then
    Delete(CleanUrl, PathStart, MaxInt);
  PathStart := Pos('://', CleanUrl);
  if PathStart = 0 then
    raise Exception.CreateFmt('Git repository URL "%s" must use HTTP or HTTPS',
      [Url]);
  Scheme := LowerCase(Copy(CleanUrl, 1, PathStart - 1));
  if (Scheme <> 'http') and (Scheme <> 'https') then
    raise Exception.CreateFmt('Unsupported Git repository URL scheme "%s"',
      [Scheme]);

  Delete(CleanUrl, 1, PathStart + 2);
  PathStart := Pos('/', CleanUrl);
  if PathStart = 0 then
  begin
    Authority := CleanUrl;
    PathPart := '';
  end else
  begin
    Authority := Copy(CleanUrl, 1, PathStart - 1);
    PathPart := Copy(CleanUrl, PathStart + 1, MaxInt);
  end;

  if (Authority = '') or (Pos(' ', Authority) <> 0) then
    raise Exception.CreateFmt('Invalid Git repository host in URL "%s"', [Url]);
  if Pos('@', Authority) <> 0 then
    raise Exception.CreateFmt('Invalid Git repository URL "%s"', [Url]);

  PathStart := Pos('?', PathPart);
  if PathStart <> 0 then
    Delete(PathPart, PathStart, MaxInt);
  PathStart := Pos('#', PathPart);
  if PathStart <> 0 then
    Delete(PathPart, PathStart, MaxInt);
  while (PathPart <> '') and (PathPart[Length(PathPart)] = '/') do
    Delete(PathPart, Length(PathPart), 1);

  PathSegments := TStringList.Create;
  try
    SegmentStart := 1;
    for I := 1 to Length(PathPart) + 1 do
      if (I > Length(PathPart)) or (PathPart[I] = '/') then
      begin
        if I > SegmentStart then
          PathSegments.Add(Copy(PathPart, SegmentStart, I - SegmentStart));
        SegmentStart := I + 1;
      end;

    if PathSegments.Count < 2 then
      raise Exception.CreateFmt(
        'Git repository URL "%s" must contain a host, user/group and repository',
        [Url]);

    for I := 0 to PathSegments.Count - 1 do
      if (PathSegments[I] = '.') or (PathSegments[I] = '..') then
        raise Exception.CreateFmt('Invalid path in Git repository URL "%s"',
          [Url]);

    RepositoryPath := PathSegments[0] + '/' + PathSegments[1];
    if (Length(RepositoryPath) >= 4) and
      (Copy(RepositoryPath, Length(RepositoryPath) - 3, 4) = '.git') then
      Delete(RepositoryPath, Length(RepositoryPath) - 3, 4);
    Result.RepositoryUrl := Scheme + '://' + Authority + '/' + RepositoryPath;

    Result.Branch := '';
    Result.Path := '';
    Result.IsSingleFile := false;
    Result.RawFileUrl := '';
    FirstPathSegment := 2;
    if FirstPathSegment < PathSegments.Count then
    begin
      IsGitHubOrGitLabPath :=
        (PathSegments[FirstPathSegment] = 'blob') or
        (PathSegments[FirstPathSegment] = 'tree');
      if (PathSegments[FirstPathSegment] = '-') and
        (FirstPathSegment + 1 < PathSegments.Count) and
        ((PathSegments[FirstPathSegment + 1] = 'blob') or
         (PathSegments[FirstPathSegment + 1] = 'tree')) then
      begin
        Inc(FirstPathSegment);
        IsGitHubOrGitLabPath := true;
      end;

      if IsGitHubOrGitLabPath then
      begin
        ViewKind := PathSegments[FirstPathSegment];
        Result.IsSingleFile := ViewKind = 'blob';
        Result.RawFileUrl := '';
        if (LowerCase(Authority) = 'github.com') and Result.IsSingleFile then
          Result.RawFileUrl := 'https://raw.githubusercontent.com/' +
            RepositoryPath + '/';
        Inc(FirstPathSegment);
        if FirstPathSegment >= PathSegments.Count then
          raise Exception.CreateFmt(
            'Git URL "%s" has a blob/tree path but no branch name', [Url]);
        Result.Branch := PathSegments[FirstPathSegment];
        if Result.RawFileUrl <> '' then
          Result.RawFileUrl += Result.Branch + '/';
        Inc(FirstPathSegment);
      end;

      if FirstPathSegment < PathSegments.Count then
      begin
        Result.Path := PathSegments[FirstPathSegment];
        for I := FirstPathSegment + 1 to PathSegments.Count - 1 do
          Result.Path += '/' + PathSegments[I];
        if Result.RawFileUrl <> '' then
          Result.RawFileUrl += Result.Path;
        if (Result.Path = '.') or (Result.Path = '..') or
          (Pos('../', Result.Path) = 1) or
          (Pos('/..', Result.Path) <> 0) then
          raise Exception.CreateFmt('Invalid path in Git URL "%s"', [Url]);
      end;
      if Result.IsSingleFile and (Result.Path = '') then
        raise Exception.CreateFmt('Git file URL "%s" has no file path', [Url]);
    end;
  finally FreeAndNil(PathSegments) end;
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

function IsTestDirectory(const Name: String): Boolean;
var
  LowerName: String;
begin
  LowerName := LowerCase(Name);
  Result :=
    (Copy(LowerName, 1, 4) = 'test') or
    (Copy(LowerName, 1, 4) = 'demo') or
    (Copy(LowerName, 1, 7) = 'example') or
    (Copy(LowerName, 1, 6) = 'sample');
end;

function IsSeparateToolProjectDirectory(const Directory: String): Boolean;
var
  Search: TSearchRec;
  SearchResult: Integer;
  Extension: String;
begin
  Result := false;
  SearchResult := FindFirst(IncludeTrailingPathDelimiter(Directory) + '*',
    faAnyFile, Search);
  if SearchResult <> 0 then
    Exit;
  try
    repeat
      if ((Search.Attr and faDirectory) = 0) then
      begin
        Extension := LowerCase(ExtractFileExt(Search.Name));
        if (Extension = '.lpi') or
          (Extension = '.dpr') or
          (Extension = '.lpr') or
          (Extension = '.dproj') or
          (Extension = '.cbproj') or
          (Extension = '.groupproj') then
          Exit(true);
      end;
      SearchResult := FindNext(Search);
    until SearchResult <> 0;
  finally FindClose(Search) end;
end;

function DirectoryContainsPascalFiles(const Directory: String;
  const SkipTest, SkipTool: Boolean): Boolean;
var
  Search: TSearchRec;
  SearchResult: Integer;
  EntryName, EntryPath, Extension: String;
begin
  Result := false;
  SearchResult := FindFirst(IncludeTrailingPathDelimiter(Directory) + '*',
    faAnyFile, Search);
  if SearchResult <> 0 then
    Exit;
  try
    repeat
      EntryName := Search.Name;
      if (EntryName <> '.') and (EntryName <> '..') then
      begin
        EntryPath := CombinePaths(Directory, EntryName);
        if (Search.Attr and faDirectory) <> 0 then
        begin
          if (not SkipTest or not IsTestDirectory(EntryName)) and
            (not SkipTool or not IsSeparateToolProjectDirectory(EntryPath)) and
            DirectoryContainsPascalFiles(EntryPath, SkipTest, SkipTool) then
            Exit(true);
        end else
        begin
          Extension := LowerCase(ExtractFileExt(EntryName));
          if (Extension = '.pas') or (Extension = '.pp') then
            Exit(true);
        end;
      end;
      SearchResult := FindNext(Search);
    until SearchResult <> 0;
  finally FindClose(Search) end;
end;

function IsPackageDataFile(const FileName: String): Boolean;
var
  Extension: String;
begin
  Extension := LowerCase(ExtractFileExt(FileName));
  Result :=
    (Extension = '.png') or (Extension = '.jpg') or
    (Extension = '.jpeg') or (Extension = '.gif') or
    (Extension = '.bmp') or (Extension = '.webp') or
    (Extension = '.tga') or (Extension = '.dds') or
    (Extension = '.ktx') or (Extension = '.ktx2') or
    (Extension = '.hdr') or (Extension = '.exr') or
    (Extension = '.svg') or (Extension = '.ico') or
    (Extension = '.wav') or (Extension = '.ogg') or
    (Extension = '.mp3') or (Extension = '.flac') or
    (Extension = '.opus') or (Extension = '.m4a') or
    (Extension = '.aac') or (Extension = '.mid') or
    (Extension = '.midi') or (Extension = '.glsl') or
    (Extension = '.vert') or (Extension = '.frag') or
    (Extension = '.geom') or (Extension = '.tesc') or
    (Extension = '.tese') or (Extension = '.comp') or
    (Extension = '.vs') or (Extension = '.fs') or
    (Extension = '.x3d') or (Extension = '.x3dv') or
    (Extension = '.x3dz') or (Extension = '.x3dvz') or
    (Extension = '.gltf') or (Extension = '.glb') or
    (Extension = '.obj') or (Extension = '.dae') or
    (Extension = '.3ds') or (Extension = '.stl') or
    (Extension = '.ply') or (Extension = '.fbx') or
    (Extension = '.blend') or (Extension = '.md2') or
    (Extension = '.md3') or (Extension = '.ifc') or
    (Copy(Extension, 1, 8) = '.castle-');
end;

function DirectoryContainsPackageData(const Directory: String;
  const SkipTest, SkipTool: Boolean): Boolean;
var
  Search: TSearchRec;
  SearchResult: Integer;
  EntryName, EntryPath: String;
begin
  Result := false;
  SearchResult := FindFirst(IncludeTrailingPathDelimiter(Directory) + '*',
    faAnyFile, Search);
  if SearchResult <> 0 then
    Exit;
  try
    repeat
      EntryName := Search.Name;
      if (EntryName <> '.') and (EntryName <> '..') then
      begin
        EntryPath := CombinePaths(Directory, EntryName);
        if (Search.Attr and faDirectory) <> 0 then
        begin
          if (not SkipTest or not IsTestDirectory(EntryName)) and
            (not SkipTool or not IsSeparateToolProjectDirectory(EntryPath)) and
            DirectoryContainsPackageData(EntryPath, SkipTest, SkipTool) then
            Exit(true);
        end else
        if IsPackageDataFile(EntryName) then
          Exit(true);
      end;
      SearchResult := FindNext(Search);
    until SearchResult <> 0;
  finally FindClose(Search) end;
end;

procedure CopyPackageDirectory(const SourceDirectory, DestinationDirectory: String;
  const SkipTest, SkipTool, CopyCode: Boolean);
var
  Search: TSearchRec;
  SearchResult: Integer;
  EntryName, SourcePath, DestinationPath: String;
begin
  CheckForceDirectories(DestinationDirectory);
  SearchResult := FindFirst(IncludeTrailingPathDelimiter(SourceDirectory) + '*',
    faAnyFile, Search);
  if SearchResult <> 0 then
    Exit;
  try
    repeat
      EntryName := Search.Name;
      if (EntryName <> '.') and (EntryName <> '..') and (EntryName <> '.git') then
      begin
        SourcePath := CombinePaths(SourceDirectory, EntryName);
        DestinationPath := CombinePaths(DestinationDirectory, EntryName);
        if (Search.Attr and faDirectory) <> 0 then
        begin
          if (not SkipTest or not IsTestDirectory(EntryName)) and
            (not SkipTool or not IsSeparateToolProjectDirectory(SourcePath)) and
            ( (CopyCode and DirectoryContainsPascalFiles(SourcePath,
                SkipTest, SkipTool)) or
              (not CopyCode and DirectoryContainsPackageData(SourcePath,
                SkipTest, SkipTool)) ) then
            CopyPackageDirectory(SourcePath, DestinationPath,
              SkipTest, SkipTool, CopyCode);
        end else
          CheckCopyFile(SourcePath, DestinationPath);
      end;
      SearchResult := FindNext(Search);
    until SearchResult <> 0;
  finally FindClose(Search) end;
end;

procedure DownloadSingleFile(const Url, DestinationDirectory, FileName: String);
var
  SourceStream: TStream;
  DestinationStream: TFileStream;
  DestinationFileName: String;
  PreviousEnableBlockingDownloads: Boolean;
begin
  CheckForceDirectories(DestinationDirectory);
  DestinationFileName := CombinePaths(DestinationDirectory, FileName);
  if DirectoryExists(DestinationFileName) then
    raise Exception.CreateFmt('Package file destination "%s" is a directory',
      [DestinationFileName]);
  PreviousEnableBlockingDownloads := EnableBlockingDownloads;
  EnableBlockingDownloads := true;
  try
    SourceStream := Download(Url);
    try
      DestinationStream := TFileStream.Create(DestinationFileName, fmCreate);
      try
        DestinationStream.CopyFrom(SourceStream, 0);
      finally FreeAndNil(DestinationStream) end;
    finally FreeAndNil(SourceStream) end;
  finally
    EnableBlockingDownloads := PreviousEnableBlockingDownloads;
  end;
end;

procedure CopySingleFile(const SourceFileName, DestinationDirectory,
  FileName: String);
var
  DestinationFileName: String;
begin
  CheckForceDirectories(DestinationDirectory);
  DestinationFileName := CombinePaths(DestinationDirectory, FileName);
  if DirectoryExists(DestinationFileName) then
    raise Exception.CreateFmt('Package file destination "%s" is a directory',
      [DestinationFileName]);
  CheckCopyFile(SourceFileName, DestinationFileName);
end;

procedure ClearReadOnlyAttributes(const Directory: String);
var
  Search: TSearchRec;
  SearchResult: Integer;
  EntryName, EntryPath: String;
begin
  SearchResult := FindFirst(IncludeTrailingPathDelimiter(Directory) + '*',
    faAnyFile, Search);
  if SearchResult = 0 then
  try
    repeat
      EntryName := Search.Name;
      if (EntryName <> '.') and (EntryName <> '..') then
      begin
        EntryPath := CombinePaths(Directory, EntryName);
        if (Search.Attr and faDirectory) <> 0 then
          ClearReadOnlyAttributes(EntryPath)
        else
          FileSetAttr(EntryPath, FileGetAttr(EntryPath) and not faReadOnly);
      end;
      SearchResult := FindNext(Search);
    until SearchResult <> 0;
  finally FindClose(Search) end;

  FileSetAttr(Directory, FileGetAttr(Directory) and not faReadOnly);
end;

procedure DownloadPackage(const PackageInfo: TPackageInfo;
  const ProjectDirectory: String);
var
  Reference: TGitRepositoryReference;
  PackageDirectory, CodeDestination, DataDestination: String;
  DestinationParent, StagingDirectory, PackageSourceDirectory: String;
  Output, CheckedOutPath, FileName: String;
  StagingGuid: TGUID;
  Arguments: TCastleStringList;
  Environment: TStringList;
  ExitStatus: Integer;
  CopyCode, CopyData, SkipTest, SkipTool: Boolean;
begin
  CopyCode := PackageHasFeature(PackageInfo, PackageFeatureCopyCode);
  CopyData := PackageHasFeature(PackageInfo, PackageFeatureCopyData);
  if not CopyCode and not CopyData then
    Exit;

  Reference := AnalyzeGitRepositoryUrl(PackageInfo.RepoUrl);
  PackageDirectory := PackageInfo.Id;
  CodeDestination := CombinePaths(ProjectDirectory,
    'packages' + PathDelim + PackageDirectory);
  DataDestination := CombinePaths(ProjectDirectory,
    'data' + PathDelim + PackageDirectory);
  if Reference.RawFileUrl <> '' then
  begin
    if CopyCode then
      DownloadSingleFile(Reference.RawFileUrl, CodeDestination,
        ExtractFileName(Reference.Path));
    if CopyData then
      DownloadSingleFile(Reference.RawFileUrl, DataDestination,
        ExtractFileName(Reference.Path));
    Exit;
  end;

  if not IsGitInstalled then
    raise Exception.CreateFmt(
      'Package "%s" uses copy-code or copy-data, which is not supported for now because Git is not installed',
      [PackageInfo.Id]);

  DestinationParent := ProjectDirectory;
  CheckForceDirectories(DestinationParent);
  if CreateGUID(StagingGuid) <> 0 then
    raise Exception.Create('Cannot create a unique temporary Git clone path');
  StagingDirectory := CombinePaths(DestinationParent,
    'package-' + GUIDToString(StagingGuid));
  if DirectoryExists(StagingDirectory) or FileExists(StagingDirectory) then
    raise Exception.CreateFmt('Temporary Git clone path "%s" already exists',
      [StagingDirectory]);

  Arguments := TCastleStringList.Create;
  Environment := nil;
  PackageSourceDirectory := StagingDirectory;
  try
    Environment := EnvironmentStrings;
    Arguments.Add('clone');
    Arguments.Add('--depth');
    Arguments.Add('1');
    if Reference.Path <> '' then
    begin
      Arguments.Add('--filter=blob:none');
      Arguments.Add('--sparse');
    end;
    if Reference.Branch <> '' then
    begin
      Arguments.Add('--branch');
      Arguments.Add(Reference.Branch);
    end;
    Arguments.Add(Reference.RepositoryUrl);
    Arguments.Add(StagingDirectory);
    Environment.Values['GIT_TERMINAL_PROMPT'] := '0';
    ExecuteCommandCapture('', 'git', Arguments.ToArray, Output, ExitStatus,
      nil, nil, [], Environment);
    if ExitStatus <> 0 then
      raise Exception.CreateFmt('Git clone failed for "%s" (exit status %d): %s',
        [Reference.RepositoryUrl, ExitStatus, Trim(Output)]);

    if Reference.Path <> '' then
    begin
      if Reference.IsSingleFile then
      begin
        ExecuteCommandCapture(StagingDirectory, 'git',
          ['sparse-checkout', 'set', '--no-cone', '--', Reference.Path],
          Output, ExitStatus, nil, nil, [], Environment);
      end else
      begin
        ExecuteCommandCapture(StagingDirectory, 'git',
          ['sparse-checkout', 'set', Reference.Path],
          Output, ExitStatus, nil, nil, [], Environment);
      end;
      if ExitStatus <> 0 then
        raise Exception.CreateFmt(
          'Git sparse checkout failed for path "%s" (exit status %d): %s',
          [Reference.Path, ExitStatus, Trim(Output)]);
      CheckedOutPath := CombinePaths(StagingDirectory,
        StringReplace(Reference.Path, '/', PathDelim, [rfReplaceAll]));
      if not FileExists(CheckedOutPath) and
        not DirectoryExists(CheckedOutPath) then
        raise Exception.CreateFmt('Git path "%s" was not found in "%s"',
          [Reference.Path, Reference.RepositoryUrl]);
      PackageSourceDirectory := CheckedOutPath;
    end;

    SkipTest := PackageHasFeature(PackageInfo, PackageFeatureSkipTest);
    SkipTool := PackageHasFeature(PackageInfo, PackageFeatureSkipTool);
    if Reference.IsSingleFile then
    begin
      FileName := ExtractFileName(Reference.Path);
      if CopyCode then
        CopySingleFile(PackageSourceDirectory, CodeDestination, FileName);
      if CopyData then
        CopySingleFile(PackageSourceDirectory, DataDestination, FileName);
    end else
    begin
      if CopyCode then
      begin
        CopyPackageDirectory(PackageSourceDirectory, CodeDestination,
          SkipTest, SkipTool, true);
        WritelnLog('GitDownload', Format('Copied package code to "%s"',
          [CodeDestination]));
      end;
      if CopyData then
      begin
        CopyPackageDirectory(PackageSourceDirectory, DataDestination,
          SkipTest, SkipTool, false);
        WritelnLog('GitDownload', Format('Copied package data to "%s"',
          [DataDestination]));
      end;
    end;
  finally
    FreeAndNil(Environment);
    FreeAndNil(Arguments);
    if DirectoryExists(StagingDirectory) then
    begin
      ClearReadOnlyAttributes(StagingDirectory);
      RemoveNonEmptyDir(StagingDirectory);
    end;
  end;
end;

end.
