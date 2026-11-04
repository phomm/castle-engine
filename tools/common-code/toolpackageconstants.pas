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

{ Constants and helpers for package download and filtering behavior. }
unit ToolPackageConstants;

{$I castleconf.inc}

interface

const
  GitRepositoryUrlSchemes: array [0..1] of String = ('http', 'https');
  GitRepositoryViewSegments: array [0..1] of String = ('blob', 'tree');
  GitInvalidPathSegments: array [0..1] of String = ('.', '..');
  GitInvalidPathSubstrings: array [0..1] of String = ('../', '/..');
  GitHubHostName = 'github.com';
  GitHubRawFileUrlPrefix = 'https://raw.githubusercontent.com/';
  GitRepositorySuffix = '.git';
  GitSingleFileViewSegment = 'blob';
  GitRepositoryViewPrefixSegment = '-';

  TestDirectoryPrefixes: array [0..3] of String = (
    'test', 'demo', 'example', 'sample'
  );
  SeparateToolProjectExtensions: array [0..5] of String = (
    '.lpi', '.dpr', '.lpr', '.dproj', '.cbproj', '.groupproj'
  );
  PascalSourceExtensions: array [0..1] of String = ('.pas', '.pp');
  CastleDataFileExtensionPrefix = '.castle-';
  PackageDataExtensions: array [0..47] of String = (
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.tga', '.dds',
    '.ktx', '.ktx2', '.hdr', '.exr', '.svg', '.ico',
    '.wav', '.ogg', '.mp3', '.flac', '.opus', '.m4a', '.aac', '.mid', '.midi',
    '.glsl', '.vert', '.frag', '.geom', '.tesc', '.tese', '.comp', '.vs', '.fs',
    '.x3d', '.x3dv', '.x3dz', '.x3dvz', '.gltf', '.glb', '.obj', '.dae',
    '.3ds', '.stl', '.ply', '.fbx', '.blend', '.md2', '.md3', '.ifc'
  );
  PackageIgnoredDirectoryNames: array [0..2] of String = ('.', '..', '.git');

{ Return whether Text starts with any Prefix, ignoring case. }
function ToolStartsWithAnyText(const Text: String;
  const Prefixes: array of String): Boolean;

{ Return whether Text contains any Substring. }
function ToolContainsAnySubstring(const Text: String;
  const Substrings: array of String): Boolean;

implementation

uses StrUtils;

function ToolStartsWithAnyText(const Text: String;
  const Prefixes: array of String): Boolean;
var
  I: Integer;
begin
  for I := Low(Prefixes) to High(Prefixes) do
    if StartsText(Prefixes[I], Text) then
      Exit(true);
  Result := false;
end;

function ToolContainsAnySubstring(const Text: String;
  const Substrings: array of String): Boolean;
var
  I: Integer;
begin
  for I := Low(Substrings) to High(Substrings) do
    if Pos(Substrings[I], Text) <> 0 then
      Exit(true);
  Result := false;
end;

end.
