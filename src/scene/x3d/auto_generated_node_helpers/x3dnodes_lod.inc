{ -*- buffer-read-only: t -*-

  Copyright 2015-2025 Michalis Kamburelis.

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
  - and regenerate include files by running x3d-nodes-to-pascal }

{$ifdef read_interface}

  public
    { Create node fields and events. }
    procedure CreateNode; override;
    class function ClassX3DType: String; override;

    strict private FEventLevel_changed: TSFInt32Event;
    {  }
    public property EventLevel_changed: TSFInt32Event read FEventLevel_changed;

    strict private FFdCenter: TSFVec3f;
    { Internal wrapper for property @code(Center). This wrapper API may change, we advise to access simpler @code(Center) instead, if it is defined (TODO: for now, some field types do not have a simpler counterpart). }
    public property FdCenter: TSFVec3f read FFdCenter;

    strict private FFdForceTransitions: TSFBool;
    { Internal wrapper for property @code(ForceTransitions). This wrapper API may change, we advise to access simpler @code(ForceTransitions) instead, if it is defined (TODO: for now, some field types do not have a simpler counterpart). }
    public property FdForceTransitions: TSFBool read FFdForceTransitions;

    strict private FFdRange: TMFFloat;
    { Internal wrapper for property @code(Range). This wrapper API may change, we advise to access simpler @code(Range) instead, if it is defined (TODO: for now, some field types do not have a simpler counterpart). }
    public property FdRange: TMFFloat read FFdRange;

{$endif read_interface}

{$ifdef read_implementation}

{ TLODNode ----------------------------------------------- }

class function TLODNode.ClassX3DType: String;
begin
  Result := 'LOD';
end;

procedure TLODNode.CreateNode;
begin
  inherited;

  FEventLevel_changed := TSFInt32Event.Create(Self, 'level_changed', false);
  AddEvent(FEventLevel_changed);

  FFdCenter := TSFVec3f.Create(Self, False, 'center', Vector3(0, 0, 0));
   FdCenter.ChangeAlways := chRedisplay;
  AddField(FFdCenter);

  FFdForceTransitions := TSFBool.Create(Self, False, 'forceTransitions', false);
   FdForceTransitions.ChangeAlways := chVisibleNonGeometry;
  AddField(FFdForceTransitions);

  FFdRange := TMFFloat.Create(Self, False, 'range', []);
   FdRange.ChangeAlways := chRedisplay;
  AddField(FFdRange);
end;

{$endif read_implementation}
