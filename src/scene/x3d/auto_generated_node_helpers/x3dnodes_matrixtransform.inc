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
    function GetMatrix: TMatrix4;
    procedure SetMatrix(const Value: TMatrix4);
  public
    procedure CreateNode; override;
    class function ClassX3DType: string; override;

    strict private FFdMatrix: TSFMatrix4f;
    { X3D field "matrix". } { }
    public property FdMatrix: TSFMatrix4f read FFdMatrix;
    { X3D field "matrix". } { }
    property Matrix: TMatrix4 read GetMatrix write SetMatrix;

{$endif read_interface}

{$ifdef read_implementation}

{ TMatrixTransformNode ----------------------------------------------- }

function TMatrixTransformNode.GetMatrix: TMatrix4;
begin
  Result := FdMatrix.Value;
end;

procedure TMatrixTransformNode.SetMatrix(const Value: TMatrix4);
begin
  FdMatrix.Send(Value);
end;

class function TMatrixTransformNode.ClassX3DType: String;
begin
  Result := 'MatrixTransform';
end;

procedure TMatrixTransformNode.CreateNode;
begin
  inherited;

  FFdMatrix := TSFMatrix4f.Create(Self, True, 'matrix', TMatrix4.Identity);
   FdMatrix.ChangeAlways := chVisibleNonGeometry;
  AddField(FFdMatrix);
end;

{$endif read_implementation}