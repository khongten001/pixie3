unit Pixie.CssLength;

{$mode delphi}

interface

uses
  SysUtils, Generics.Collections, Pixie.Types, Pixie.Html;

const
  // from_token options (flags)
  fLength           = 1;
  fPercentage       = 2;
  fLengthPercentage = 3;
  fNumber           = 4;
  fInteger          = 8;
  fPositive         = 16;

  // Sentinel predefined value for minmax() in grid template vectors.
  // When a TPixieCssLength has IsPredefined=True and Predef=CssGridMinmaxMarker,
  // the FValue field holds the min length value and FUnits the min units.
  // The NEXT entry in the vector contains the max length.
  CssGridMinmaxMarker = $7FFE;

type
  { TPixieCssLength }
  TPixieCssLength = record
  private
    FValue: Single;
    FPredef: Integer;
    FUnits: TPixieCssUnits;
    FIsPredefined: Boolean;
  public
    class function Create(AValue: Single; AUnits: TPixieCssUnits = cssUnitsPx): TPixieCssLength; static;
    class function PredefValue(AVal: Integer = 0): TPixieCssLength; static;
    function IsPredefined: Boolean;
    function Predef: Integer;
    function Val: Single;
    function Units: TPixieCssUnits;
    function CalcPercent(AWidth: pixel_t): pixel_t;
    procedure SetValue(AVal: Single; AUnits: TPixieCssUnits);
    procedure SetPredef(AVal: Integer);
    function ToString: string;
  end;
  PPixieCssLength = ^TPixieCssLength;

  { TPixieCssMargins }
  TPixieCssMargins = record
    Left: TPixieCssLength;
    Right: TPixieCssLength;
    Top: TPixieCssLength;
    Bottom: TPixieCssLength;
    function ToString: string;
  end;

  { TPixieCssSize }
  TPixieCssSize = record
    Width: TPixieCssLength;
    Height: TPixieCssLength;
    class function Create(AWidth, AHeight: TPixieCssLength): TPixieCssSize; static;
  end;

  { TPixieCssOffsets }
  TPixieCssOffsets = record
    Left: TPixieCssLength;
    Top: TPixieCssLength;
    Right: TPixieCssLength;
    Bottom: TPixieCssLength;
    function ToString: string;
  end;

  TPixieLengthVector = TList<TPixieCssLength>;
  TPixieSizeVector = TList<TPixieCssSize>;

implementation

{ TPixieCssLength }

class function TPixieCssLength.Create(AValue: Single; AUnits: TPixieCssUnits): TPixieCssLength;
begin
  Result.FValue := AValue;
  Result.FPredef := 0;
  Result.FUnits := AUnits;
  Result.FIsPredefined := False;
end;

class function TPixieCssLength.PredefValue(AVal: Integer): TPixieCssLength;
begin
  Result.FValue := 0;
  Result.FPredef := AVal;
  Result.FUnits := cssUnitsNone;
  Result.FIsPredefined := True;
end;

function TPixieCssLength.IsPredefined: Boolean;
begin
  Result := FIsPredefined;
end;

function TPixieCssLength.Predef: Integer;
begin
  if FIsPredefined then
    Result := FPredef
  else
    Result := 0;
end;

function TPixieCssLength.Val: Single;
begin
  if not FIsPredefined then
    Result := FValue
  else
    Result := 0;
end;

function TPixieCssLength.Units: TPixieCssUnits;
begin
  Result := FUnits;
end;

function TPixieCssLength.CalcPercent(AWidth: pixel_t): pixel_t;
begin
  if not IsPredefined then
  begin
    if FUnits = cssUnitsPercentage then
      Result := AWidth * FValue / 100
    else
      Result := pixel_t(Val);
  end
  else
    Result := 0;
end;

procedure TPixieCssLength.SetValue(AVal: Single; AUnits: TPixieCssUnits);
begin
  FValue := AVal;
  FIsPredefined := False;
  FUnits := AUnits;
end;

procedure TPixieCssLength.SetPredef(AVal: Integer);
begin
  FPredef := AVal;
  FIsPredefined := True;
end;

function TPixieCssLength.ToString: string;
begin
  if FIsPredefined then
    Result := 'predef(' + IntToStr(FPredef) + ')'
  else
    Result := FloatToStr(FValue) + '(' + PixieIndexValue(Ord(FUnits), CssUnitsStrings) + ')';
end;

{ TPixieCssMargins }

function TPixieCssMargins.ToString: string;
begin
  Result := 'left: ' + Left.ToString +
            ', right: ' + Right.ToString +
            ', top: ' + Top.ToString +
            ', bottom: ' + Bottom.ToString;
end;

{ TPixieCssSize }

class function TPixieCssSize.Create(AWidth, AHeight: TPixieCssLength): TPixieCssSize;
begin
  Result.Width := AWidth;
  Result.Height := AHeight;
end;

{ TPixieCssOffsets }

function TPixieCssOffsets.ToString: string;
begin
  Result := 'left: ' + Left.ToString +
            ', top: ' + Top.ToString +
            ', right: ' + Right.ToString +
            ', bottom: ' + Bottom.ToString;
end;

end.
