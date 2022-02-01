{ -*- buffer-read-only: t -*-

  Copyright 2015-2021 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{ Automatically generated node properties.

  Do not edit this file manually!
  To add new properties:
  - add them to the text files in tools/internal/x3d-nodes-to-pascal/nodes-specification/ ,
  - and regenerate include files by running x3d-nodes-to-pascal .

  The documentation for properties should go to x3dnodes_documentation.txt . }

{$ifdef read_interface}

  strict private
    function GetEnabled: Boolean;
    procedure SetEnabled(const Value: Boolean);
  public
    { X3D field "enabled". } { }
    property Enabled: Boolean read GetEnabled write SetEnabled;
    { Set X3D field "parts". } { }
    procedure SetParts(const Value: array of TEffectPartNode);

{$endif read_interface}

{$ifdef read_implementation}

{ TEffectNode ----------------------------------------------- }

function TEffectNode.GetEnabled: Boolean;
begin
  Result := FdEnabled.Value;
end;

procedure TEffectNode.SetEnabled(const Value: Boolean);
begin
  FdEnabled.Send(Value);
end;

procedure TEffectNode.SetParts(const Value: array of TEffectPartNode);
var
  L: Integer;
  A: array of TX3DNode;
begin
  L := High(Value) + 1;
  SetLength(A, L);
  if L > 0 then
    Move(Value[0], A[0], L * SizeOf(TEffectPartNode));
  FdParts.Send(A);
end;

{$endif read_implementation}