unit Pixie.CssLength;

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

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
    FCalcPercent: Single;
    FPredef: Integer;
    FUnits: TPixieCssUnits;
    FIsPredefined: Boolean;
  public
    class function Create(AValue: Single; AUnits: TPixieCssUnits = cssUnitsPx): TPixieCssLength; static;
    class function CreateCalc(AAbsolutePx, APercentCoeff: Single): TPixieCssLength; static;
    class function PredefValue(AVal: Integer = 0): TPixieCssLength; static;
    function IsPredefined: Boolean;
    function IsCalc: Boolean;
    function Predef: Integer;
    function Val: Single;
    function CalcPercentCoeff: Single;
    function Units: TPixieCssUnits;
    function CalcPercent(AWidth: TPixiePixel): TPixiePixel;
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
  Result.FCalcPercent := 0;
  Result.FPredef := 0;
  Result.FUnits := AUnits;
  Result.FIsPredefined := False;
end;

class function TPixieCssLength.CreateCalc(AAbsolutePx, APercentCoeff: Single): TPixieCssLength;
begin
  if APercentCoeff = 0 then
  begin
    Result.FValue := AAbsolutePx;
    Result.FCalcPercent := 0;
    Result.FPredef := 0;
    Result.FUnits := cssUnitsPx;
    Result.FIsPredefined := False;
  end
  else if AAbsolutePx = 0 then
  begin
    Result.FValue := APercentCoeff;
    Result.FCalcPercent := 0;
    Result.FPredef := 0;
    Result.FUnits := cssUnitsPercentage;
    Result.FIsPredefined := False;
  end
  else
  begin
    Result.FValue := AAbsolutePx;
    Result.FCalcPercent := APercentCoeff;
    Result.FPredef := 0;
    Result.FUnits := cssUnitsCalc;
    Result.FIsPredefined := False;
  end;
end;

class function TPixieCssLength.PredefValue(AVal: Integer): TPixieCssLength;
begin
  Result.FValue := 0;
  Result.FCalcPercent := 0;
  Result.FPredef := AVal;
  Result.FUnits := cssUnitsNone;
  Result.FIsPredefined := True;
end;

function TPixieCssLength.IsPredefined: Boolean;
begin
  Result := FIsPredefined;
end;

function TPixieCssLength.IsCalc: Boolean;
begin
  Result := FUnits = cssUnitsCalc;
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

function TPixieCssLength.CalcPercentCoeff: Single;
begin
  Result := FCalcPercent;
end;

function TPixieCssLength.Units: TPixieCssUnits;
begin
  Result := FUnits;
end;

function TPixieCssLength.CalcPercent(AWidth: TPixiePixel): TPixiePixel;
begin
  if not IsPredefined then
  begin
    if FUnits = cssUnitsCalc then
      Result := AWidth * FCalcPercent / 100 + FValue
    else if FUnits = cssUnitsPercentage then
      Result := AWidth * FValue / 100
    else
      Result := TPixiePixel(Val);
  end
  else
    Result := 0;
end;

procedure TPixieCssLength.SetValue(AVal: Single; AUnits: TPixieCssUnits);
begin
  FValue := AVal;
  FCalcPercent := 0;
  FIsPredefined := False;
  FUnits := AUnits;
end;

procedure TPixieCssLength.SetPredef(AVal: Integer);
begin
  FPredef := AVal;
  FCalcPercent := 0;
  FIsPredefined := True;
end;

function TPixieCssLength.ToString: string;
begin
  if FIsPredefined then
    Result := 'predef(' + IntToStr(FPredef) + ')'
  else if FUnits = cssUnitsCalc then
    Result := 'calc(' + FloatToStr(FCalcPercent) + '% + ' + FloatToStr(FValue) + 'px)'
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
