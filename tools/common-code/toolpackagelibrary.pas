{
  Copyright 2026 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Download and parse the Castle packages library. }
unit ToolPackageLibrary;

{$I castleconf.inc}

interface

type
  { Link attached to a package in the library. }
  TPackageLink = record
    { Display name of the link. }
    Name: String;
    { Destination URL. }
    Url: String;
  end;

  { Feature identifiers supported by a package. }
  TPackageFeatureArray = array of String;

  { Component information from the packages library. }
  TPackageInfo = record
    { Stable package identifier. }
    Id: String;
    { Package title. }
    Name: String;
    { Package description, which may contain HTML. }
    Description: String;
    { Image path relative to the packages library's images/ directory. }
    ImageUrl: String;
    { Package repository or project page URL. }
    RepoUrl: String;
    { Package author. }
    Author: String;
    { Additional links associated with the package. }
    Links: array of TPackageLink;
    { Features supported by the package. }
    Features: TPackageFeatureArray;
  end;

  { Array of package information returned by @link(LoadPackageLibrary). }
  TPackageInfoArray = array of TPackageInfo;

const
  { Default JSON source for the packages library. }
  DefaultPackagesLibraryUrl = 'https://raw.githubusercontent.com/phomm/cge-packages/refs/heads/main/unified.json';

  { Feature identifier for downloading package sources into packages/. }
  PackageFeatureCopyCode = 'copy-code';
  { Feature identifier for excluding a package from test runs. }
  PackageFeatureSkipTest = 'skip-test';
  { Feature identifier for excluding a package from tool builds. }
  PackageFeatureSkipTool = 'skip-tool';
  { Feature identifier for registering a package in the editor. }
  PackageFeatureRegisterEditor = 'register-editor';
  { Feature identifier for installing a package as a Git submodule. }
  PackageFeatureGitSubmodule = 'git-submodule';
  { Feature identifier for copying package data into a project. }
  PackageFeatureCopyData = 'copy-data';

{ Parse packages from a JSON library document. }
function ParsePackageLibraryJson(const Content: String): TPackageInfoArray;

{ Download the JSON packages library and parse it. }
function LoadPackageLibrary(const Url: String): TPackageInfoArray;

{ Get a package image URL from the directory containing the given library URL,
  using its images/ subdirectory. }
function PackageLibraryImageUrl(const LibraryUrl, ImagePath: String): String;

implementation

uses
  Classes, SysUtils, fpjson, jsonparser,
  CastleDownload, CastleLog;

function PackageLibraryImageUrl(const LibraryUrl, ImagePath: String): String;
var
  UrlWithoutQueryOrFragment: String;
  QueryPosition: SizeInt;
  FragmentPosition: SizeInt;
  PathPosition: SizeInt;
begin
  UrlWithoutQueryOrFragment := LibraryUrl;
  QueryPosition := Pos('?', UrlWithoutQueryOrFragment);
  FragmentPosition := Pos('#', UrlWithoutQueryOrFragment);
  if (QueryPosition > 0) and
    ((FragmentPosition = 0) or (QueryPosition < FragmentPosition)) then
    Delete(UrlWithoutQueryOrFragment, QueryPosition, Length(UrlWithoutQueryOrFragment));
  FragmentPosition := Pos('#', UrlWithoutQueryOrFragment);
  if FragmentPosition > 0 then
    Delete(UrlWithoutQueryOrFragment, FragmentPosition,
      Length(UrlWithoutQueryOrFragment));

  PathPosition := LastDelimiter('/', UrlWithoutQueryOrFragment);
  Result := Copy(UrlWithoutQueryOrFragment, 1, PathPosition) +
    'images/' + ImagePath;
end;

function ParsePackageLibraryJson(const Content: String): TPackageInfoArray;
var
  JSONData: TJSONData;
  LibraryPackages: TJSONArray;
  PackageData: TJSONObject;
  PackageLinks: TJSONArray;
  PackageFeatures: TJSONArray;
  LinkData: TJSONObject;
  Field: TJSONData;
  PackageInfo: TPackageInfo;
  I, J: Integer;

  function RequiredString(const ObjectData: TJSONObject;
    const FieldName: String): String;
  var
    FieldData: TJSONData;
  begin
    FieldData := ObjectData.Find(FieldName);
    if (FieldData = nil) or (FieldData.JSONType <> jtString) then
      raise Exception.Create('Invalid package field "' + FieldName + '"');
    Result := FieldData.AsString;
  end;

begin
  Result := nil;
  JSONData := GetJSON(Content);
  try
    if JSONData.JSONType <> jtObject then
      raise Exception.Create('Library JSON root must be an object');

    Field := TJSONObject(JSONData).Find('packages');
    if (Field = nil) or (Field.JSONType <> jtArray) then
      raise Exception.Create('Library JSON must contain a packages array');
    LibraryPackages := TJSONArray(Field);

    SetLength(Result, LibraryPackages.Count);
    for I := 0 to LibraryPackages.Count - 1 do
    begin
      if LibraryPackages[I].JSONType <> jtObject then
        raise Exception.Create('Library package must be an object');

      PackageData := TJSONObject(LibraryPackages[I]);
      PackageInfo.Id := RequiredString(PackageData, 'id');
      PackageInfo.Name := RequiredString(PackageData, 'title');
      PackageInfo.Description := RequiredString(PackageData, 'description');
      PackageInfo.ImageUrl := RequiredString(PackageData, 'image');
      PackageInfo.RepoUrl := RequiredString(PackageData, 'page');
      PackageInfo.Author := RequiredString(PackageData, 'author');

      Field := PackageData.Find('links');
      if (Field = nil) or (Field.JSONType <> jtArray) then
        raise Exception.Create('Invalid package field "links"');
      PackageLinks := TJSONArray(Field);
      SetLength(PackageInfo.Links, PackageLinks.Count);
      for J := 0 to PackageLinks.Count - 1 do
      begin
        if PackageLinks[J].JSONType <> jtObject then
          raise Exception.Create('Package link must be an object');
        LinkData := TJSONObject(PackageLinks[J]);
        PackageInfo.Links[J].Name := RequiredString(LinkData, 'name');
        PackageInfo.Links[J].Url := RequiredString(LinkData, 'url');
      end;

      Field := PackageData.Find('features');
      if Field = nil then
        PackageInfo.Features := nil
      else
      begin
        if Field.JSONType <> jtArray then
          raise Exception.Create('Invalid package field "features"');
        PackageFeatures := TJSONArray(Field);
        SetLength(PackageInfo.Features, PackageFeatures.Count);
        for J := 0 to PackageFeatures.Count - 1 do
        begin
          if PackageFeatures[J].JSONType <> jtString then
            raise Exception.Create('Package feature must be a string');
          PackageInfo.Features[J] := PackageFeatures[J].AsString;
        end;
      end;

      Result[I] := PackageInfo;
      WritelnLog('PackageLibrary', 'Found component: ' + PackageInfo.Name);
    end;
  finally
    JSONData.Free;
  end;
end;

function DownloadContent(const Url: String): String;
var
  DownloadStream: TStream;
begin
  DownloadStream := Download(Url);
  try
    SetLength(Result, DownloadStream.Size);
    if DownloadStream.Size > 0 then
      DownloadStream.ReadBuffer(Result[1], DownloadStream.Size);
  finally
    DownloadStream.Free;
  end;
end;

function LoadPackageLibrary(const Url: String): TPackageInfoArray;
var
  Content: String;
  PreviousEnableBlockingDownloads: Boolean;
begin
  PreviousEnableBlockingDownloads := EnableBlockingDownloads;
  EnableBlockingDownloads := true;
  try
    WritelnLog('PackageLibrary', 'Downloading library from: ' + Url);
    Content := DownloadContent(Url);
    WritelnLog('PackageLibrary', 'Downloaded ' + IntToStr(Length(Content)) + ' bytes');
    Result := ParsePackageLibraryJson(Content);
  finally
    EnableBlockingDownloads := PreviousEnableBlockingDownloads;
  end;
  WritelnLog('PackageLibrary', 'Parsed ' + IntToStr(Length(Result)) + ' components');
end;

end.
