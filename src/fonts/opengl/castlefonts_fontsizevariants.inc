{%MainUnit castlefonts.pas}
{
  Copyright 2001-2021 Michalis Kamburelis.

  This file is part of "Castle Game Engine".

  "Castle Game Engine" is free software; see the file COPYING.txt,
  included in this distribution, for details about the copyright.

  "Castle Game Engine" is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

  ----------------------------------------------------------------------------
}

{$ifdef read_interface}

type
  { Font that uses @italic(another) TCastleAbstractFont for rendering and sizing,
    but modifies the underlying font size.
    Simply set the @code(Size) property of this instance to non-zero
    to force the specific size.

    The underlying font properties remain unchanged
    (so it can be still used for other purposes,
    directly or by other TCustomizedFont wrappers). }
  TCustomizedFont = class(TCastleAbstractFont)
  strict private
    FSourceFont: TCastleAbstractFont;
    FAlternativeSizes: TComponentList;
    SubFont: TCastleAbstractFont;
    { Set SubFont to one of SourceFont of FAlternativeSizes,
      depending on the current Size. }
    procedure UpdateSubFont;
    procedure SubFontCustomizeBegin;
    procedure SubFontCustomizeEnd;
    procedure SetSourceFont(const Value: TCastleAbstractFont);
  strict protected
    procedure Measure(out ARowHeight, ARowHeightBase, ADescend: Single); override;
    procedure GLContextClose; override;
    procedure SetSize(const Value: Single); override;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    property SourceFont: TCastleAbstractFont read FSourceFont write SetSourceFont;

    procedure PrepareResources; override;
    procedure Print(const X, Y: Single; const Color: TCastleColor;
      const S: string); override;
    function TextWidth(const S: string): Single; override;
    function TextHeight(const S: string): Single; override;
    function TextHeightBase(const S: string): Single; override;
    function TextMove(const S: string): TVector2; override;
    function EffectiveSize: Single; override;

    { Add any number of alternative source fonts.
      Before actually using them for rendering,
      we always choose the one with size most matching our desired @link(Size).
      This way you can e.g. load the same font in sizes 10, 50, 100,
      and have good quality font rendering in various sizes. }
    procedure AddAlternativeSourceFont(const ASourceFont: TCastleAbstractFont);

    { Load the same font to a number of textures with different sizes.
      At rendering, we will automatically use the best size.
      This sets @link(SourceFont) and @link(AddAlternativeSourceFont).

      This allows to achieve better look than TTexturedFont with one size. }
    procedure Load(const URL: string;
      const ASizes: array of Integer; const AnAntiAliased: boolean;
      const ACharacters: TUnicodeCharList = nil);

    { Return SourceFont or one of the fonts added by @link(AddAlternativeSourceFont),
      to have the font with @link(TCastleAbstractFont.Size) closest to the given ASize. }
    function BestSourceFont(const ASize: Single): TCastleAbstractFont;
  end;

{$endif read_interface}

{$ifdef read_implementation}

{ TCustomizedFont ------------------------------------------------------------ }

constructor TCustomizedFont.Create(AOwner: TComponent);
begin
  inherited;
end;

destructor TCustomizedFont.Destroy;
begin
  SourceFont := nil; // this will free FSourceFont if needed
  FreeAndNil(FAlternativeSizes);
  inherited;
end;

procedure TCustomizedFont.SetSourceFont(const Value: TCastleAbstractFont);
begin
  if FSourceFont <> Value then
  begin
    if FSourceFont <> nil then
      FSourceFont.RemoveFreeNotification(Self);
    FSourceFont := Value;
    if FSourceFont <> nil then
      FSourceFont.FreeNotification(Self);

    { Recalculate SubFont, since fonts changed.
      TODO: This will not fire when a font on FAlternativeSizes list is freed,
      SubFont may be left pointing to one of freed fonts. }
    UpdateSubFont;
  end;
end;

procedure TCustomizedFont.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;

  if (Operation = opRemove) and (AComponent = FSourceFont) then
  begin
    { set to nil by SetSourceFont to clean nicely }
    SourceFont := nil;
  end;
end;

procedure TCustomizedFont.PrepareResources;
var
  I: Integer;
begin
  if FSourceFont <> nil then
    FSourceFont.PrepareResources;

  if FAlternativeSizes <> nil then
  begin
    for I := 0 to FAlternativeSizes.Count - 1 do
      TCastleAbstractFont(FAlternativeSizes[I]).PrepareResources;
  end;
end;

procedure TCustomizedFont.GLContextClose;
var
  I: Integer;
begin
  if FSourceFont <> nil then
    FSourceFont.GLContextClose;

  if FAlternativeSizes <> nil then
  begin
    for I := 0 to FAlternativeSizes.Count - 1 do
      TCastleAbstractFont(FAlternativeSizes[I]).GLContextClose;
  end;
end;

procedure TCustomizedFont.SetSize(const Value: Single);
begin
  if Size <> Value then
  begin
    inherited SetSize(Value);
    UpdateSubFont;
  end;
end;

function TCustomizedFont.BestSourceFont(const ASize: Single): TCastleAbstractFont;
var
  SizeDist, NewSizeDist: Single;
  AltFont: TCastleAbstractFont;
  I: Integer;
begin
  Result := SourceFont;

  if (FAlternativeSizes <> nil) and (ASize <> 0) then
  begin
    { At destruction it can happen that SourceFont is nil,
      while FAlternativeSizes is non-nil. }
    if SourceFont <> nil then
      SizeDist := Abs(SourceFont.Size - ASize)
    else
      SizeDist := MaxSingle;

    for I := 0 to FAlternativeSizes.Count - 1 do
    begin
      AltFont := TCastleAbstractFont(FAlternativeSizes[I]);
      NewSizeDist := Abs(AltFont.Size - ASize);
      if NewSizeDist < SizeDist then
      begin
        Result := AltFont;
        SizeDist := NewSizeDist;
      end;
    end;
  end;

  // Writeln('for size ', Size:1:2, ' using font with size ', Result.Size:1:2);
end;

procedure TCustomizedFont.UpdateSubFont;
begin
  SubFont := BestSourceFont(Size);
end;

procedure TCustomizedFont.SubFontCustomizeBegin;
begin
  if Size <> 0 then
  begin
    SubFont.PushProperties;
    SubFont.Size := Size;
  end;
end;

procedure TCustomizedFont.SubFontCustomizeEnd;
begin
  if Size <> 0 then
    SubFont.PopProperties;
end;

procedure TCustomizedFont.Print(const X, Y: Single; const Color: TCastleColor;
  const S: string);
begin
  SubFontCustomizeBegin;
  SubFont.Print(X, Y, Color, S);
  SubFontCustomizeEnd;
end;

function TCustomizedFont.TextWidth(const S: string): Single;
begin
  { One may think that only for rendering (Print) we have to use SubFont,
    for sizing it's enough to use SourceFont (since all alternatives should
    be the same font, just scaled).

    In practice it's important to use best font (always SubFont),
    since the underlying fonts data have integer sizes,
    so taking sizes of a different font always introduces some imprecision,
    this is visible by slightly misaligned labels etc. }

  SubFontCustomizeBegin;
  Result := SubFont.TextWidth(S);
  SubFontCustomizeEnd;
end;

function TCustomizedFont.TextHeight(const S: string): Single;
begin
  SubFontCustomizeBegin;
  Result := SubFont.TextHeight(S);
  SubFontCustomizeEnd;
end;

function TCustomizedFont.TextHeightBase(const S: string): Single;
begin
  SubFontCustomizeBegin;
  Result := SubFont.TextHeightBase(S);
  SubFontCustomizeEnd;
end;

function TCustomizedFont.TextMove(const S: string): TVector2;
begin
  SubFontCustomizeBegin;
  Result := SubFont.TextMove(S);
  SubFontCustomizeEnd;
end;

function TCustomizedFont.EffectiveSize: Single;
begin
  if Size <> 0 then
    Result := Size
  else
    Result := SourceFont.EffectiveSize;
end;

procedure TCustomizedFont.Measure(out ARowHeight, ARowHeightBase, ADescend: Single);
begin
  { In usual circumstances, overriding Measure in TCustomizedFont is not needed.
    The default implementation of ancestor would work OK,
    by calling TextHeight to measure "Wy" for RowHeight,
    and TCustomizedFont.TextHeight refers to FSourceFont.TextHeight already.

    But if the FSourceFont has some custom override for Measure,
    like TLargeDigitsFont.Measure in testcastlefonts.pas
    that returns constant instead of measuring "Wy" height for RowHeight
    (because TLargeDigitsFont doesn't have "Wy" letters)
    then it would be ignored.
    This would cause problems when wrapping a font in TCustomizedFont
    (which is what e.g. TCastleLabel does when it has some size),
    wrapping TLargeDigitsFont in TCustomizedFont would ignore the
    TLargeDigitsFont.Measure override.

    So instead we implement our Measure we calling FSourceFont.Measure. }

  SubFontCustomizeBegin;
  SubFont.Measure(ARowHeight, ARowHeightBase, ADescend);
  SubFontCustomizeEnd;
end;

procedure TCustomizedFont.AddAlternativeSourceFont(const ASourceFont: TCastleAbstractFont);
begin
  if FAlternativeSizes = nil then
    FAlternativeSizes := TComponentList.Create(false);
  FAlternativeSizes.Add(ASourceFont);
  UpdateSubFont;
end;

procedure TCustomizedFont.Load(const URL: string;
  const ASizes: array of Integer; const AnAntiAliased: boolean;
  const ACharacters: TUnicodeCharList);
var
  F: TCastleFont;
  I: Integer;
begin
  Assert(Length(ASizes) > 0);

  // clear previous
  SourceFont := nil;
  if FAlternativeSizes <> nil then
    FAlternativeSizes.Clear;

  for I := 0 to Length(ASizes) - 1 do
  begin
    F := TCastleFont.Create(Self);
    F.Load(URL, ASizes[I], AnAntiAliased, ACharacters);
    if SourceFont = nil then
      SourceFont := F
    else
      AddAlternativeSourceFont(F);
  end;
end;

{$endif read_implementation}