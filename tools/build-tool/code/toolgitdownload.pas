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

{ Return whether a directory contains package content after applying the
  package folder filters. CopyCode determines whether Pascal source or data
  files are counted. }
function DirectoryContainsPackageContent(const Directory: String;
  const SkipTest, SkipTool, CopyCode: Boolean): Boolean;

{ Download the sources/data described by PackageInfo into ProjectDirectory.
  Code goes into packages/<id>, data into data/<id>. }
procedure DownloadPackage(const PackageInfo: TPackageInfo;
  const ProjectDirectory: String);

implementation

uses Classes, SysUtils, StrUtils,
  CastleDownload, CastleFilesUtils, CastleInternalProcess, CastleLog,
  CastleStringUtils, CastleFindFiles, ToolPackageConstants;

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
  if not MatchText(Scheme, GitRepositoryUrlSchemes) then
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
      if MatchText(PathSegments[I], GitInvalidPathSegments) then
        raise Exception.CreateFmt('Invalid path in Git repository URL "%s"',
          [Url]);

    RepositoryPath := PathSegments[0] + '/' + PathSegments[1];
    if (Length(RepositoryPath) >= Length(GitRepositorySuffix)) and
      (Copy(RepositoryPath,
        Length(RepositoryPath) - Length(GitRepositorySuffix) + 1,
        Length(GitRepositorySuffix)) = GitRepositorySuffix) then
      Delete(RepositoryPath, Length(RepositoryPath) - Length(GitRepositorySuffix) + 1,
        Length(GitRepositorySuffix));
    Result.RepositoryUrl := Scheme + '://' + Authority + '/' + RepositoryPath;

    Result.Branch := '';
    Result.Path := '';
    Result.IsSingleFile := false;
    Result.RawFileUrl := '';
    FirstPathSegment := 2;
    if FirstPathSegment < PathSegments.Count then
    begin
      IsGitHubOrGitLabPath :=
        MatchText(PathSegments[FirstPathSegment], GitRepositoryViewSegments);
      if (PathSegments[FirstPathSegment] = GitRepositoryViewPrefixSegment) and
        (FirstPathSegment + 1 < PathSegments.Count) and
        MatchText(PathSegments[FirstPathSegment + 1], GitRepositoryViewSegments) then
      begin
        Inc(FirstPathSegment);
        IsGitHubOrGitLabPath := true;
      end;

      if IsGitHubOrGitLabPath then
      begin
        ViewKind := PathSegments[FirstPathSegment];
        Result.IsSingleFile := ViewKind = GitSingleFileViewSegment;
        Result.RawFileUrl := '';
        if (LowerCase(Authority) = GitHubHostName) and Result.IsSingleFile then
          Result.RawFileUrl := GitHubRawFileUrlPrefix + RepositoryPath + '/';
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
        if MatchText(Result.Path, GitInvalidPathSegments) or
          ToolContainsAnySubstring(Result.Path, GitInvalidPathSubstrings) then
          raise Exception.CreateFmt('Invalid path in Git URL "%s"', [Url]);
      end;
      if Result.IsSingleFile and (Result.Path = '') then
        raise Exception.CreateFmt('Git file URL "%s" has no file path', [Url]);
    end;
  finally FreeAndNil(PathSegments) end;
end;

function IsTestDirectory(const Name: String): Boolean;
begin
  Result := ToolStartsWithAnyText(Name, TestDirectoryPrefixes);
end;

function IsSeparateToolProjectDirectory(const Directory: String): Boolean;
var
  FileInfos: TFileInfoList;
  FileInfo: TFileInfo;
  I: Integer;
  Extension: String;
begin
  Result := false;
  FileInfos := FindFilesList(Directory, '*', false, []);
  try
    for I := 0 to FileInfos.Count - 1 do
    begin
      FileInfo := FileInfos[I];
      if not FileInfo.Directory then
      begin
        Extension := LowerCase(ExtractFileExt(FileInfo.Name));
        if MatchText(Extension, SeparateToolProjectExtensions) then
          Exit(true);
      end;
    end;
  finally FreeAndNil(FileInfos) end;
end;

function IsPascalSourceFile(const FileName: String): Boolean;
var
  Extension: String;
begin
  Extension := LowerCase(ExtractFileExt(FileName));
  Result := MatchText(Extension, PascalSourceExtensions);
end;

function IsPackageDataFile(const FileName: String): Boolean;
var
  Extension: String;
begin
  Extension := LowerCase(ExtractFileExt(FileName));
  Result := MatchText(Extension, PackageDataExtensions) or
    ToolStartsWithAnyText(Extension, [CastleDataFileExtensionPrefix]);
end;

function DirectoryContainsPackageContent(const Directory: String;
  const SkipTest, SkipTool, CopyCode: Boolean): Boolean;
var
  FileInfos: TFileInfoList;
  FileInfo: TFileInfo;
  I: Integer;
  EntryPath: String;
begin
  Result := false;
  FileInfos := FindFilesList(Directory, '*', true, []);
  try
    for I := 0 to FileInfos.Count - 1 do
    begin
      FileInfo := FileInfos[I];
      EntryPath := CombinePaths(Directory, FileInfo.Name);
      if FileInfo.Directory then
      begin
        if (not SkipTest or not IsTestDirectory(FileInfo.Name)) and
          (not SkipTool or not IsSeparateToolProjectDirectory(EntryPath)) and
          DirectoryContainsPackageContent(EntryPath, SkipTest, SkipTool, CopyCode) then
          Exit(true);
      end else
      if (CopyCode and IsPascalSourceFile(FileInfo.Name)) or
        (not CopyCode and IsPackageDataFile(FileInfo.Name)) then
        Exit(true);
    end;
  finally FreeAndNil(FileInfos) end;
end;

procedure CopyPackageDirectory(const SourceDirectory, DestinationDirectory: String;
  const SkipTest, SkipTool, CopyCode: Boolean);
var
  FileInfos: TFileInfoList;
  FileInfo: TFileInfo;
  I: Integer;
  SourcePath, DestinationPath: String;
begin
  CheckForceDirectories(DestinationDirectory);
  FileInfos := FindFilesList(SourceDirectory, '*', true, []);
  try
    for I := 0 to FileInfos.Count - 1 do
    begin
      FileInfo := FileInfos[I];
      if not MatchText(FileInfo.Name, PackageIgnoredDirectoryNames) then
      begin
        SourcePath := CombinePaths(SourceDirectory, FileInfo.Name);
        DestinationPath := CombinePaths(DestinationDirectory, FileInfo.Name);
        if FileInfo.Directory then
        begin
          if (not SkipTest or not IsTestDirectory(FileInfo.Name)) and
            (not SkipTool or not IsSeparateToolProjectDirectory(SourcePath)) and
            DirectoryContainsPackageContent(SourcePath, SkipTest, SkipTool,
              CopyCode) then
            CopyPackageDirectory(SourcePath, DestinationPath,
              SkipTest, SkipTool, CopyCode);
        end else
          CheckCopyFile(SourcePath, DestinationPath);
      end;
    end;
  finally FreeAndNil(FileInfos) end;
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
  FileInfos: TFileInfoList;
  FileInfo: TFileInfo;
  I: Integer;
  EntryPath: String;
begin
  FileInfos := FindFilesList(Directory, '*', true, []);
  try
    for I := 0 to FileInfos.Count - 1 do
    begin
      FileInfo := FileInfos[I];
      EntryPath := CombinePaths(Directory, FileInfo.Name);
      if FileInfo.Directory then
        ClearReadOnlyAttributes(EntryPath)
      else
        FileSetAttr(EntryPath, FileGetAttr(EntryPath) and not faReadOnly);
    end;
  finally FreeAndNil(FileInfos) end;

  FileSetAttr(Directory, FileGetAttr(Directory) and not faReadOnly);
end;

procedure DownloadPackage(const PackageInfo: TPackageInfo;
  const ProjectDirectory: String);
var
  Reference: TGitRepositoryReference;
  PackageDirectory, CodeDestination, DataDestination: String;
  StagingDirectory, PackageSourceDirectory: String;
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

  if CreateGUID(StagingGuid) <> 0 then
    raise Exception.Create('Cannot create a unique temporary Git clone path');
  StagingDirectory := CombinePaths(GetTempDir(false),
    'castle-package-' + GUIDToString(StagingGuid));
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
      RemoveNonEmptyDir(StagingDirectory, true);
    end;
  end;
end;

end.
