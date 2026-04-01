unit Pixie.TagBar.Colors;

// Colour palette and state derivation for tag pills.
// Pure math — no LCL dependency.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Math, Pixie.Types, Pixie.WebColor;

type
  TPixieTagPaletteArray = array of TPixieWebColor;

{ HSL conversion }
procedure PixieTagRgbToHsl(R, G, B: Byte; out H, S, L: Single);
function PixieTagHslToColor(H, S, L: Single; A: Byte = 255): TPixieWebColor;

{ Colour manipulation }
function PixieTagBlend(const A, B: TPixieWebColor; T: Single): TPixieWebColor;
function PixieTagWithAlpha(const C: TPixieWebColor; A: Byte): TPixieWebColor;
function PixieTagLuminance(const C: TPixieWebColor): Single;

{ State derivation — all work from the tag's base colour }
function PixieTagRestFill(const Base: TPixieWebColor): TPixieWebColor;
function PixieTagHoverFill(const Base: TPixieWebColor): TPixieWebColor;
function PixieTagPressFill(const Base: TPixieWebColor): TPixieWebColor;
function PixieTagCheckedFill(const Base: TPixieWebColor): TPixieWebColor;
function PixieTagInactiveFill(const Base: TPixieWebColor): TPixieWebColor;
function PixieTagTextColor(const Base: TPixieWebColor;
  Checked: Boolean): TPixieWebColor;
function PixieTagBorderColor(const Base: TPixieWebColor): TPixieWebColor;

{ Default palette — 8 well-separated hues }
function PixieTagDefaultPalette: TPixieTagPaletteArray;

implementation

// ---------------------------------------------------------------------------
// HSL conversion
// ---------------------------------------------------------------------------

procedure PixieTagRgbToHsl(R, G, B: Byte; out H, S, L: Single);
var
  Rf, Gf, Bf, MaxC, MinC, Delta: Single;
begin
  Rf := R / 255;
  Gf := G / 255;
  Bf := B / 255;
  MaxC := Max(Rf, Max(Gf, Bf));
  MinC := Min(Rf, Min(Gf, Bf));
  L := (MaxC + MinC) / 2;

  if MaxC = MinC then
  begin
    H := 0;
    S := 0;
  end
  else
  begin
    Delta := MaxC - MinC;
    if L > 0.5 then
      S := Delta / (2 - MaxC - MinC)
    else
      S := Delta / (MaxC + MinC);

    if MaxC = Rf then
    begin
      H := (Gf - Bf) / Delta;
      if Gf < Bf then
        H := H + 6;
    end
    else if MaxC = Gf then
      H := (Bf - Rf) / Delta + 2
    else
      H := (Rf - Gf) / Delta + 4;

    H := H * 60;
  end;

  S := S * 100;
  L := L * 100;
end;

function PixieTagHslToColor(H, S, L: Single; A: Byte): TPixieWebColor;
var
  Rf, Gf, Bf: Single;
begin
  PixieHslToRgb(H, S, L, Rf, Gf, Bf);
  Result := TPixieWebColor.Create(
    Byte(EnsureRange(Round(Rf * 255), 0, 255)),
    Byte(EnsureRange(Round(Gf * 255), 0, 255)),
    Byte(EnsureRange(Round(Bf * 255), 0, 255)),
    A);
end;

// ---------------------------------------------------------------------------
// Colour manipulation
// ---------------------------------------------------------------------------

function PixieTagBlend(const A, B: TPixieWebColor; T: Single): TPixieWebColor;
var
  Tc: Single;
begin
  Tc := EnsureRange(T, 0, 1);
  Result := TPixieWebColor.Create(
    Byte(Round(A.Red   + (B.Red   - A.Red)   * Tc)),
    Byte(Round(A.Green + (B.Green - A.Green) * Tc)),
    Byte(Round(A.Blue  + (B.Blue  - A.Blue)  * Tc)),
    Byte(Round(A.Alpha + (B.Alpha - A.Alpha) * Tc)));
end;

function PixieTagWithAlpha(const C: TPixieWebColor; A: Byte): TPixieWebColor;
begin
  Result := TPixieWebColor.Create(C.Red, C.Green, C.Blue, A);
end;

function PixieTagLuminance(const C: TPixieWebColor): Single;

  function Linearize(V: Byte): Single;
  var
    Sv: Single;
  begin
    Sv := V / 255;
    if Sv <= 0.04045 then
      Result := Sv / 12.92
    else
      Result := Power((Sv + 0.055) / 1.055, 2.4);
  end;

begin
  Result := 0.2126 * Linearize(C.Red) +
            0.7152 * Linearize(C.Green) +
            0.0722 * Linearize(C.Blue);
end;

// ---------------------------------------------------------------------------
// State derivation
// ---------------------------------------------------------------------------

function PixieTagRestFill(const Base: TPixieWebColor): TPixieWebColor;
var
  H, S, L: Single;
begin
  PixieTagRgbToHsl(Base.Red, Base.Green, Base.Blue, H, S, L);
  S := Min(S, 45);
  L := 92;
  Result := PixieTagHslToColor(H, S, L);
end;

function PixieTagHoverFill(const Base: TPixieWebColor): TPixieWebColor;
var
  H, S, L: Single;
begin
  PixieTagRgbToHsl(Base.Red, Base.Green, Base.Blue, H, S, L);
  S := Min(S, 55);
  L := 85;
  Result := PixieTagHslToColor(H, S, L);
end;

function PixieTagPressFill(const Base: TPixieWebColor): TPixieWebColor;
var
  H, S, L: Single;
begin
  PixieTagRgbToHsl(Base.Red, Base.Green, Base.Blue, H, S, L);
  S := Min(S, 60);
  L := 75;
  Result := PixieTagHslToColor(H, S, L);
end;

function PixieTagCheckedFill(const Base: TPixieWebColor): TPixieWebColor;
begin
  Result := Base;
end;

function PixieTagInactiveFill(const Base: TPixieWebColor): TPixieWebColor;
var
  H, S, L: Single;
begin
  PixieTagRgbToHsl(Base.Red, Base.Green, Base.Blue, H, S, L);
  S := 10;
  L := 90;
  Result := PixieTagHslToColor(H, S, L);
end;

function PixieTagTextColor(const Base: TPixieWebColor;
  Checked: Boolean): TPixieWebColor;
var
  H, S, L: Single;
begin
  if Checked then
  begin
    if PixieTagLuminance(Base) > 0.5 then
      Result := TPixieWebColor.Create(30, 30, 30)
    else
      Result := TPixieWebColor.White;
  end
  else
  begin
    PixieTagRgbToHsl(Base.Red, Base.Green, Base.Blue, H, S, L);
    S := Min(S, 70);
    L := 25;
    Result := PixieTagHslToColor(H, S, L);
  end;
end;

function PixieTagBorderColor(const Base: TPixieWebColor): TPixieWebColor;
begin
  Result := PixieTagWithAlpha(Base, 80);
end;

// ---------------------------------------------------------------------------
// Default palette
// ---------------------------------------------------------------------------

function PixieTagDefaultPalette: TPixieTagPaletteArray;
begin
  Result := nil;
  SetLength(Result, 8);
  Result[0] := TPixieWebColor.Create($21, $96, $F3); // Blue
  Result[1] := TPixieWebColor.Create($4C, $AF, $50); // Green
  Result[2] := TPixieWebColor.Create($FF, $98, $00); // Orange
  Result[3] := TPixieWebColor.Create($9C, $27, $B0); // Purple
  Result[4] := TPixieWebColor.Create($00, $96, $88); // Teal
  Result[5] := TPixieWebColor.Create($F4, $43, $36); // Red
  Result[6] := TPixieWebColor.Create($FF, $C1, $07); // Amber
  Result[7] := TPixieWebColor.Create($60, $7D, $8B); // Blue-grey
end;

end.
