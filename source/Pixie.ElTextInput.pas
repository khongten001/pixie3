unit Pixie.ElTextInput;

// Owner-drawn <input type="text">, <input type="password"> and <textarea>
// elements. All are replaced elements with editable text, caret, selection,
// and clipboard support.

{$mode delphi}

interface

uses
  SysUtils, Classes, Math,
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.Container,
  Pixie.Element, Pixie.HtmlTag;

type
  { TPixieElTextBase — abstract base for editable text elements }

  TPixieElTextBase = class(TPixieHtmlTag)
  protected
    FValue: string;
    FCaretPos: Integer;       // byte position 0..Length(FValue)
    FSelStart: Integer;       // selection start (-1 = no selection)
    FSelEnd: Integer;         // selection end
    FScrollX: pixel_t;        // horizontal scroll offset
    FPassword: Boolean;       // show bullets
    FPlaceholder: string;     // placeholder text
    FReadOnly: Boolean;
    FMaxLength: Integer;      // -1 = unlimited
    FMultiLine: Boolean;
    FScrollY: pixel_t;        // vertical scroll (textarea)
    FCaretMoved: Boolean;     // AdjustScroll needed
    FUndoValue: string;       // previous value for Ctrl+Z
    FUndoCaret: Integer;      // previous caret position
    FUndoSaved: Boolean;      // undo snapshot available
    procedure SaveUndo;

    function DisplayText: string;
    function IsDisabled: Boolean;
    procedure InsertText(const S: string);
    procedure DeleteSelection;
    procedure DeleteChar(Forward: Boolean);
    procedure MoveCaret(Direction: Integer; Shift: Boolean);
    procedure MoveCaretWord(Direction: Integer; Shift: Boolean);
    procedure MoveCaretHome(Shift: Boolean);
    procedure MoveCaretEnd(Shift: Boolean);
    procedure SelectAll;
    procedure SelectWordAtCaret;
    procedure ClearSelection;
    function HasSelection: Boolean;
    function GetSelectedText: string;

    // Line helpers (multiline)
    procedure CaretToLineCol(out Line, Col: Integer);
    function GetLineStart(Line: Integer): Integer;
    function GetLineEnd(Line: Integer): Integer;
    function GetLineCount: Integer;
    function GetLineText(Line: Integer): string;

    // Coordinate mapping
    function DocToLocal(DocX, DocY: pixel_t;
      out LocalX, LocalY: pixel_t): Boolean;
    function ClickToCaret(RelX, RelY: pixel_t): Integer;
    function CaretToPixelXY(out PxX, PxY: pixel_t): Boolean;
    procedure AdjustScroll(ContentW, ContentH: pixel_t);

    // Drawing
    procedure DrawContent(Cv: TObject; P: TPixiePosition;
      Pad: TPixieMargins; IsFocused: Boolean; Ri: Pointer);
  public
    constructor Create(ADoc: TObject);

    function IsReplaced: Boolean; override;
    procedure ParseAttributes; override;
    procedure Draw(Hdc: PtrUInt; X, Y: pixel_t;
      Clip: PPixiePosition; Ri: Pointer); override;
    function CreateRenderItem(ParentRi: Pointer): Pointer; override;
    procedure OnClick; override;
    function OnLButtonDown: Boolean; override;
    function OnLButtonDblClick: Boolean; override;
    function OnMouseDrag(X, Y: pixel_t): Boolean; override;

    // Focus and keyboard
    procedure OnFocus; override;
    procedure OnBlur; override;
    function OnKeyDown(Key: Word; Shift: TShiftState): Boolean; override;
    function OnUTF8KeyPress(const UTF8Char: string): Boolean; override;
    function IsFocusable: Boolean; override;

    property Value: string read FValue write FValue;
  end;

  { TPixieElTextInput — <input type="text|password"> }

  TPixieElTextInput = class(TPixieElTextBase)
  public
    procedure ParseAttributes; override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: pixel_t); override;
    function DumpGetName: string; override;
  end;

  { TPixieElTextArea — <textarea> }

  TPixieElTextArea = class(TPixieElTextBase)
  private
    FRows: Integer;
    FCols: Integer;
  public
    constructor Create(ADoc: TObject);
    procedure ParseAttributes; override;
    procedure GetContentSize(var Sz: TPixieSize;
      MaxWidth: pixel_t); override;
    function OnKeyDown(Key: Word; Shift: TShiftState): Boolean; override;
    function OnMouseWheel(Delta: Integer): Boolean; override;
    function DumpGetName: string; override;
  end;

implementation

uses
  LCLType, Clipbrd,
  Pixie.StringId, Pixie.Background, Pixie.Canvas,
  Pixie.NativeContainer,
  Pixie.Document, Pixie.RenderItem, Pixie.RenderInput,
  Pixie.RenderTable, Pixie.Utf8;

function GetCanvas(Tag: TPixieHtmlTag): TPixieCanvas;
var
  Cont: TPixieContainer;
begin
  Result := nil;
  Cont := Tag.GetDocContainer;
  if (Cont <> nil) and (Cont is TPixieNativeContainer) then
    Result := TPixieNativeContainer(Cont).Canvas;
end;

function GetNativeContainer(Tag: TPixieHtmlTag): TPixieNativeContainer;
var
  Cont: TPixieContainer;
begin
  Result := nil;
  Cont := Tag.GetDocContainer;
  if (Cont <> nil) and (Cont is TPixieNativeContainer) then
    Result := TPixieNativeContainer(Cont);
end;

{ UTF-8 navigation helpers }

function UTF8NextCharPos(const S: string; BytePos: Integer): Integer;
var
  B: Byte;
  Len: Integer;
begin
  Len := Length(S);
  if BytePos >= Len then
    Exit(Len);
  B := Byte(S[BytePos + 1]);
  if B < $80 then
    Result := BytePos + 1
  else if B < $E0 then
    Result := Min(BytePos + 2, Len)
  else if B < $F0 then
    Result := Min(BytePos + 3, Len)
  else
    Result := Min(BytePos + 4, Len);
end;

function UTF8PrevCharPos(const S: string; BytePos: Integer): Integer;
var
  I: Integer;
begin
  if BytePos <= 0 then
    Exit(0);
  I := BytePos - 1;
  while (I > 0) and ((Byte(S[I + 1]) and $C0) = $80) do
    Dec(I);
  Result := I;
end;

function UTF8CharCount(const S: string): Integer;
var
  I, Len: Integer;
begin
  Result := 0;
  I := 1;
  Len := Length(S);
  while I <= Len do
  begin
    Inc(Result);
    if Byte(S[I]) < $80 then
      Inc(I)
    else if Byte(S[I]) < $E0 then
      Inc(I, 2)
    else if Byte(S[I]) < $F0 then
      Inc(I, 3)
    else
      Inc(I, 4);
  end;
end;

{ TPixieElTextBase }

constructor TPixieElTextBase.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
  FValue := '';
  FCaretPos := 0;
  FSelStart := -1;
  FSelEnd := -1;
  FScrollX := 0;
  FScrollY := 0;
  FPassword := False;
  FPlaceholder := '';
  FReadOnly := False;
  FMaxLength := -1;
  FMultiLine := False;
end;

function TPixieElTextBase.IsReplaced: Boolean;
begin
  Result := True;
end;

function TPixieElTextBase.IsFocusable: Boolean;
begin
  Result := not IsDisabled;
end;

function TPixieElTextBase.IsDisabled: Boolean;
begin
  Result := FPseudoClasses.IndexOf(Ord(psid_disabled)) >= 0;
end;

function TPixieElTextBase.DisplayText: string;
var
  I, Len: Integer;
begin
  if FPassword then
  begin
    Len := UTF8CharCount(FValue);
    Result := '';
    for I := 1 to Len do
      Result := Result + #$E2#$80#$A2; // U+2022 BULLET
  end
  else
    Result := FValue;
end;

// ---------------------------------------------------------------------------
// Line helpers — work on FValue, lines separated by #10
// ---------------------------------------------------------------------------

procedure TPixieElTextBase.CaretToLineCol(out Line, Col: Integer);
var
  I, LineStart: Integer;
begin
  Line := 0;
  LineStart := 0;
  for I := 1 to FCaretPos do
    if FValue[I] = #10 then
    begin
      Inc(Line);
      LineStart := I;
    end;
  Col := FCaretPos - LineStart;
end;

function TPixieElTextBase.GetLineStart(Line: Integer): Integer;
var
  I, CurLine: Integer;
begin
  if Line <= 0 then
    Exit(0);
  CurLine := 0;
  for I := 1 to Length(FValue) do
    if FValue[I] = #10 then
    begin
      Inc(CurLine);
      if CurLine = Line then
        Exit(I); // byte offset just past the #10
    end;
  Result := Length(FValue);
end;

function TPixieElTextBase.GetLineEnd(Line: Integer): Integer;
var
  I, CurLine: Integer;
begin
  CurLine := 0;
  for I := 1 to Length(FValue) do
    if FValue[I] = #10 then
    begin
      if CurLine = Line then
        Exit(I - 1);
      Inc(CurLine);
    end;
  Result := Length(FValue);
end;

function TPixieElTextBase.GetLineCount: Integer;
var
  I: Integer;
begin
  Result := 1;
  for I := 1 to Length(FValue) do
    if FValue[I] = #10 then
      Inc(Result);
end;

function TPixieElTextBase.GetLineText(Line: Integer): string;
var
  LS, LE: Integer;
begin
  LS := GetLineStart(Line);
  LE := GetLineEnd(Line);
  Result := Copy(FValue, LS + 1, LE - LS);
end;

// ---------------------------------------------------------------------------
// Coordinate mapping
// ---------------------------------------------------------------------------

function TPixieElTextBase.DocToLocal(DocX, DocY: pixel_t;
  out LocalX, LocalY: pixel_t): Boolean;
var
  Ri, Cur: TPixieRenderItem;
  Chain: array of TPixieRenderItem;
  Count, I: Integer;
begin
  // Replicate the coordinate transform that GetChildByPoint does:
  // at each level, subtract the element's Pos from the point.
  // This gives coordinates relative to the element's content box.
  Ri := TPixieRenderItem(GetRenderItem);
  if Ri = nil then
  begin
    LocalX := DocX;
    LocalY := DocY;
    Exit(False);
  end;

  // Build chain from root to self (inclusive)
  Count := 0;
  Cur := Ri;
  while Cur <> nil do
  begin
    Inc(Count);
    Cur := Cur.GetParent;
  end;

  SetLength(Chain, Count);
  Cur := Ri;
  for I := Count - 1 downto 0 do
  begin
    Chain[I] := Cur;
    Cur := Cur.GetParent;
  end;

  // Transform: subtract each element's Pos going root -> self.
  // Skip tbody/tr render items because table cell positions are
  // relative to the table content area, not to their parent tr/tbody.
  LocalX := DocX;
  LocalY := DocY;
  for I := 0 to Count - 1 do
  begin
    if (Chain[I] is TPixieRenderTablePart) or
       (Chain[I] is TPixieRenderTableRow) then
      Continue;
    LocalX := LocalX - Chain[I].Pos.X;
    LocalY := LocalY - Chain[I].Pos.Y;
  end;

  Result := True;
end;

function TPixieElTextBase.CaretToPixelXY(
  out PxX, PxY: pixel_t): Boolean;
var
  Cv: TPixieCanvas;
  Line, Col, I, CharCount: Integer;
  LineH: pixel_t;
  LineStr: string;
  ColText: string;
begin
  Cv := GetCanvas(Self);
  if Cv = nil then
  begin
    PxX := 0;
    PxY := 0;
    Exit(False);
  end;

  LineH := FCss.FontMetrics.Height;

  if FMultiLine then
  begin
    CaretToLineCol(Line, Col);
    LineStr := GetLineText(Line);
    ColText := Copy(LineStr, 1, Col);
    PxX := Cv.MeasureText(ColText, FCss.Font) - FScrollX;
    PxY := Line * LineH - FScrollY;
  end
  else
  begin
    if FPassword then
    begin
      CharCount := UTF8CharCount(Copy(FValue, 1, FCaretPos));
      ColText := '';
      for I := 1 to CharCount do
        ColText := ColText + #$E2#$80#$A2;
    end
    else
      ColText := Copy(FValue, 1, FCaretPos);
    PxX := Cv.MeasureText(ColText, FCss.Font) - FScrollX;
    PxY := 0;
  end;
  Result := True;
end;

function TPixieElTextBase.ClickToCaret(
  RelX, RelY: pixel_t): Integer;
var
  Cv: TPixieCanvas;
  LineH: pixel_t;
  TargetLine, NumLines: Integer;
  LineStr: string;
  LS, I, BestPos, Len: Integer;
  MeasW, BestDist, Dist, AdjX: pixel_t;
begin
  Cv := GetCanvas(Self);
  if Cv = nil then
    Exit(0);

  LineH := FCss.FontMetrics.Height;

  if FMultiLine then
  begin
    // Determine which line was clicked
    TargetLine := Trunc((RelY + FScrollY) / LineH);
    NumLines := GetLineCount;
    if TargetLine < 0 then
      TargetLine := 0;
    if TargetLine >= NumLines then
      TargetLine := NumLines - 1;

    LineStr := GetLineText(TargetLine);
    LS := GetLineStart(TargetLine);
    AdjX := RelX + FScrollX;
  end
  else
  begin
    TargetLine := 0;
    LineStr := DisplayText;
    LS := 0;
    AdjX := RelX + FScrollX;
  end;

  // Find closest character boundary within the line
  Len := Length(LineStr);
  BestPos := 0;
  BestDist := Abs(AdjX);

  I := 0;
  while I < Len do
  begin
    I := UTF8NextCharPos(LineStr, I);
    MeasW := Cv.MeasureText(Copy(LineStr, 1, I), FCss.Font);
    Dist := Abs(AdjX - MeasW);
    if Dist < BestDist then
    begin
      BestDist := Dist;
      BestPos := I;
    end;
  end;

  // Map back to FValue byte position
  if FPassword and (not FMultiLine) then
  begin
    Result := 0;
    for I := 1 to BestPos div 3 do
      Result := UTF8NextCharPos(FValue, Result);
  end
  else
    Result := LS + BestPos;
end;

procedure TPixieElTextBase.AdjustScroll(ContentW, ContentH: pixel_t);
var
  PxX, PxY: pixel_t;
  LineH, Margin: pixel_t;
begin
  if not CaretToPixelXY(PxX, PxY) then
    Exit;

  LineH := FCss.FontMetrics.Height;
  Margin := 4;

  // Horizontal scroll
  if PxX > ContentW - Margin then
    FScrollX := FScrollX + (PxX - ContentW + Margin);
  if PxX < Margin then
    FScrollX := FScrollX + (PxX - Margin);
  if FScrollX < 0 then
    FScrollX := 0;

  // Vertical scroll (multiline only)
  if FMultiLine then
  begin
    if PxY < 0 then
      FScrollY := FScrollY + PxY;
    if PxY + LineH > ContentH then
      FScrollY := FScrollY + (PxY + LineH - ContentH);
    if FScrollY < 0 then
      FScrollY := 0;
  end;
end;

// ---------------------------------------------------------------------------
// Editing
// ---------------------------------------------------------------------------

procedure TPixieElTextBase.ParseAttributes;
begin
  if GetAttr('disabled', #1) <> #1 then
    SetPseudoClass(Ord(psid_disabled), True);
  FReadOnly := GetAttr('readonly', #1) <> #1;
  inherited ParseAttributes;
end;

procedure TPixieElTextBase.SaveUndo;
begin
  FUndoValue := FValue;
  FUndoCaret := FCaretPos;
  FUndoSaved := True;
end;

procedure TPixieElTextBase.InsertText(const S: string);
var
  I, Cur, MaxChars: Integer;
  TotalChars: Integer;
begin
  if FReadOnly or IsDisabled then
    Exit;
  SaveUndo;
  if HasSelection then
    DeleteSelection;

  if FMaxLength >= 0 then
  begin
    TotalChars := UTF8CharCount(FValue);
    MaxChars := FMaxLength - TotalChars;
    if MaxChars <= 0 then
      Exit;
    Cur := 0;
    for I := 1 to Min(MaxChars, UTF8CharCount(S)) do
      Cur := UTF8NextCharPos(S, Cur);
    if Cur < Length(S) then
    begin
      FValue := Copy(FValue, 1, FCaretPos) + Copy(S, 1, Cur) +
        Copy(FValue, FCaretPos + 1, Length(FValue) - FCaretPos);
      FCaretPos := FCaretPos + Cur;
      Exit;
    end;
  end;

  FValue := Copy(FValue, 1, FCaretPos) + S +
    Copy(FValue, FCaretPos + 1, Length(FValue) - FCaretPos);
  FCaretPos := FCaretPos + Length(S);
  FCaretMoved := True;
end;

procedure TPixieElTextBase.DeleteSelection;
var
  Lo, Hi: Integer;
begin
  if not HasSelection then
    Exit;
  Lo := Min(FSelStart, FSelEnd);
  Hi := Max(FSelStart, FSelEnd);
  FValue := Copy(FValue, 1, Lo) +
    Copy(FValue, Hi + 1, Length(FValue) - Hi);
  FCaretPos := Lo;
  FCaretMoved := True;
  ClearSelection;
end;

procedure TPixieElTextBase.DeleteChar(Forward: Boolean);
var
  NewPos: Integer;
begin
  if FReadOnly or IsDisabled then
    Exit;
  SaveUndo;
  if HasSelection then
  begin
    DeleteSelection;
    Exit;
  end;
  if Forward then
  begin
    if FCaretPos >= Length(FValue) then
      Exit;
    NewPos := UTF8NextCharPos(FValue, FCaretPos);
    FValue := Copy(FValue, 1, FCaretPos) +
      Copy(FValue, NewPos + 1, Length(FValue) - NewPos);
  end
  else
  begin
    if FCaretPos <= 0 then
      Exit;
    NewPos := UTF8PrevCharPos(FValue, FCaretPos);
    FValue := Copy(FValue, 1, NewPos) +
      Copy(FValue, FCaretPos + 1, Length(FValue) - FCaretPos);
    FCaretPos := NewPos;
  end;
  FCaretMoved := True;
end;

procedure TPixieElTextBase.MoveCaret(Direction: Integer; Shift: Boolean);
var
  NewPos: Integer;
begin
  NewPos := FCaretPos;
  if Direction < 0 then
    NewPos := UTF8PrevCharPos(FValue, FCaretPos)
  else if Direction > 0 then
    NewPos := UTF8NextCharPos(FValue, FCaretPos);

  if Shift then
  begin
    if FSelStart < 0 then
      FSelStart := FCaretPos;
    FSelEnd := NewPos;
  end
  else
    ClearSelection;
  FCaretPos := NewPos;
  FCaretMoved := True;
end;

procedure TPixieElTextBase.MoveCaretWord(Direction: Integer;
  Shift: Boolean);

  function IsBreak(BytePos: Integer): Boolean;
  var
    B: Byte;
  begin
    if (BytePos < 0) or (BytePos >= Length(FValue)) then
      Exit(True);
    B := Byte(FValue[BytePos + 1]);
    if B >= $80 then
      Exit(False);
    Result := (B <= 32) or (B = Ord(',')) or (B = Ord('.')) or
      (B = Ord('!')) or (B = Ord('?')) or (B = Ord(';')) or
      (B = Ord(':')) or (B = Ord('"')) or (B = Ord('''')) or
      (B = Ord('(')) or (B = Ord(')')) or (B = Ord('/'));
  end;

var
  NewPos, Prev: Integer;
begin
  NewPos := FCaretPos;
  if Direction < 0 then
  begin
    // Skip breaks, then skip word chars
    while (NewPos > 0) and IsBreak(UTF8PrevCharPos(FValue, NewPos)) do
      NewPos := UTF8PrevCharPos(FValue, NewPos);
    while NewPos > 0 do
    begin
      Prev := UTF8PrevCharPos(FValue, NewPos);
      if IsBreak(Prev) then Break;
      NewPos := Prev;
    end;
  end
  else
  begin
    // Skip word chars, then skip breaks
    while (NewPos < Length(FValue)) and not IsBreak(NewPos) do
      NewPos := UTF8NextCharPos(FValue, NewPos);
    while (NewPos < Length(FValue)) and IsBreak(NewPos) do
      NewPos := UTF8NextCharPos(FValue, NewPos);
  end;

  if Shift then
  begin
    if FSelStart < 0 then
      FSelStart := FCaretPos;
    FSelEnd := NewPos;
  end
  else
    ClearSelection;
  FCaretPos := NewPos;
  FCaretMoved := True;
end;

procedure TPixieElTextBase.MoveCaretHome(Shift: Boolean);
var
  Target: Integer;
  Line, Col: Integer;
begin
  if FMultiLine then
  begin
    CaretToLineCol(Line, Col);
    Target := GetLineStart(Line);
  end
  else
    Target := 0;

  if Shift then
  begin
    if FSelStart < 0 then
      FSelStart := FCaretPos;
    FSelEnd := Target;
  end
  else
    ClearSelection;
  FCaretPos := Target;
  FCaretMoved := True;
end;

procedure TPixieElTextBase.MoveCaretEnd(Shift: Boolean);
var
  Target: Integer;
  Line, Col: Integer;
begin
  if FMultiLine then
  begin
    CaretToLineCol(Line, Col);
    Target := GetLineEnd(Line);
  end
  else
    Target := Length(FValue);

  if Shift then
  begin
    if FSelStart < 0 then
      FSelStart := FCaretPos;
    FSelEnd := Target;
  end
  else
    ClearSelection;
  FCaretPos := Target;
  FCaretMoved := True;
end;

procedure TPixieElTextBase.SelectAll;
begin
  FSelStart := 0;
  FSelEnd := Length(FValue);
end;

procedure TPixieElTextBase.SelectWordAtCaret;

  function IsBreak(BytePos: Integer): Boolean;
  var
    B: Byte;
  begin
    if (BytePos < 0) or (BytePos >= Length(FValue)) then
      Exit(True);
    B := Byte(FValue[BytePos + 1]);
    if B >= $80 then
      Exit(False);
    Result := (B <= 32) or (B = Ord(',')) or (B = Ord('.')) or
      (B = Ord('!')) or (B = Ord('?')) or (B = Ord(';')) or
      (B = Ord(':')) or (B = Ord('"')) or (B = Ord('''')) or
      (B = Ord('(')) or (B = Ord(')')) or (B = Ord('/'));
  end;

var
  WS, WE, Prev: Integer;
begin
  if Length(FValue) = 0 then Exit;

  WS := FCaretPos;
  WE := FCaretPos;

  // If caret is at a break char, try the char before
  if IsBreak(WE) then
  begin
    if WS <= 0 then Exit;
    WS := UTF8PrevCharPos(FValue, WS);
    if IsBreak(WS) then Exit;
    WE := WS;
  end;

  // Scan backward
  while WS > 0 do
  begin
    Prev := UTF8PrevCharPos(FValue, WS);
    if IsBreak(Prev) then Break;
    WS := Prev;
  end;

  // Scan forward
  while (WE < Length(FValue)) and not IsBreak(WE) do
    WE := UTF8NextCharPos(FValue, WE);

  if WS <> WE then
  begin
    FSelStart := WS;
    FSelEnd := WE;
    FCaretPos := WE;
    FCaretMoved := True;
  end;
end;

procedure TPixieElTextBase.ClearSelection;
begin
  FSelStart := -1;
  FSelEnd := -1;
end;

function TPixieElTextBase.HasSelection: Boolean;
begin
  Result := (FSelStart >= 0) and (FSelEnd >= 0) and
    (FSelStart <> FSelEnd);
end;

function TPixieElTextBase.GetSelectedText: string;
var
  Lo, Hi: Integer;
begin
  if not HasSelection then
    Exit('');
  Lo := Min(FSelStart, FSelEnd);
  Hi := Max(FSelStart, FSelEnd);
  Result := Copy(FValue, Lo + 1, Hi - Lo);
end;

// ---------------------------------------------------------------------------
// Focus / keyboard
// ---------------------------------------------------------------------------

procedure TPixieElTextBase.OnFocus;
begin
  // Caret is positioned by OnLButtonDown when clicking.
  // Only reset to end when focus comes from non-click (e.g. tab).
  if FSelStart < 0 then
    FCaretPos := Length(FValue);
end;

procedure TPixieElTextBase.OnBlur;
begin
  ClearSelection;
end;

function TPixieElTextBase.OnKeyDown(Key: Word;
  Shift: TShiftState): Boolean;
var
  ClipText: string;
begin
  Result := False;
  if IsDisabled then
    Exit;

  case Key of
    VK_LEFT:
    begin
      if ssCtrl in Shift then
        MoveCaretWord(-1, ssShift in Shift)
      else
        MoveCaret(-1, ssShift in Shift);
      Result := True;
    end;
    VK_RIGHT:
    begin
      if ssCtrl in Shift then
        MoveCaretWord(1, ssShift in Shift)
      else
        MoveCaret(1, ssShift in Shift);
      Result := True;
    end;
    VK_HOME:
    begin
      MoveCaretHome(ssShift in Shift);
      Result := True;
    end;
    VK_END:
    begin
      MoveCaretEnd(ssShift in Shift);
      Result := True;
    end;
    VK_BACK:
    begin
      DeleteChar(False);
      Result := True;
    end;
    VK_DELETE:
    begin
      DeleteChar(True);
      Result := True;
    end;
    Ord('A'):
      if ssCtrl in Shift then
      begin
        SelectAll;
        Result := True;
      end;
    Ord('C'):
      if (ssCtrl in Shift) and HasSelection and (not FPassword) then
      begin
        Clipboard.AsText := GetSelectedText;
        Result := True;
      end;
    Ord('V'):
      if (ssCtrl in Shift) and (not FReadOnly) then
      begin
        ClipText := Clipboard.AsText;
        if not FMultiLine then
        begin
          ClipText := StringReplace(ClipText, #13#10, ' ', [rfReplaceAll]);
          ClipText := StringReplace(ClipText, #10, ' ', [rfReplaceAll]);
          ClipText := StringReplace(ClipText, #13, ' ', [rfReplaceAll]);
        end;
        InsertText(ClipText);
        Result := True;
      end;
    Ord('X'):
      if (ssCtrl in Shift) and HasSelection and (not FReadOnly) and
         (not FPassword) then
      begin
        Clipboard.AsText := GetSelectedText;
        SaveUndo;
        DeleteSelection;
        Result := True;
      end;
    Ord('Z'):
      if (ssCtrl in Shift) and FUndoSaved then
      begin
        FValue := FUndoValue;
        FCaretPos := FUndoCaret;
        FCaretMoved := True;
        FUndoSaved := False;
        ClearSelection;
        Result := True;
      end;
  end;
end;

function TPixieElTextBase.OnUTF8KeyPress(
  const UTF8Char: string): Boolean;
begin
  Result := False;
  if IsDisabled or FReadOnly then
    Exit;
  if (Length(UTF8Char) = 1) and (Byte(UTF8Char[1]) < 32) then
    Exit;
  InsertText(UTF8Char);
  Result := True;
end;

// ---------------------------------------------------------------------------
// Mouse
// ---------------------------------------------------------------------------

function TPixieElTextBase.OnLButtonDown: Boolean;
var
  Doc: TPixieDocument;
  LocalX, LocalY: pixel_t;
begin
  Result := inherited OnLButtonDown;
  if IsDisabled then
    Exit;

  Doc := TPixieDocument(FDoc);
  Doc.SetFocus(Self);
  DocToLocal(Doc.LastMouseX, Doc.LastMouseY, LocalX, LocalY);
  FCaretPos := ClickToCaret(LocalX, LocalY);
  FCaretMoved := True;
  ClearSelection;
  FSelStart := FCaretPos;
  Result := True;
end;

function TPixieElTextBase.OnLButtonDblClick: Boolean;
begin
  Result := False;
  if IsDisabled then Exit;
  SelectWordAtCaret;
  Result := HasSelection;
end;

function TPixieElTextBase.OnMouseDrag(X, Y: pixel_t): Boolean;
var
  LocalX, LocalY: pixel_t;
  NewPos: Integer;
begin
  Result := False;
  if IsDisabled then
    Exit;

  DocToLocal(X, Y, LocalX, LocalY);
  NewPos := ClickToCaret(LocalX, LocalY);

  if NewPos <> FCaretPos then
  begin
    FSelEnd := NewPos;
    FCaretPos := NewPos;
    FCaretMoved := True;
    Result := True;
  end;
end;

procedure TPixieElTextBase.OnClick;
begin
  inherited OnClick;
end;

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

procedure TPixieElTextBase.DrawContent(Cv: TObject;
  P: TPixiePosition; Pad: TPixieMargins;
  IsFocused: Boolean; Ri: Pointer);
var
  Canvas: TPixieCanvas;
  Cont: TPixieNativeContainer;
  BX, BY, BW, BH: pixel_t;
  BorderW: pixel_t;
  LineH: pixel_t;
  BorderColor, BgColor, TextColor, PlaceholderColor: TPixieWebColor;
  FocusColor: TPixieWebColor;
  SelColor, SelTextColor: TPixieWebColor;
  Rad: TPixieBorderRadiuses;
  ClipPos: TPixiePosition;
  ShowCaret: Boolean;
  NoRadius: TPixieBorderRadiuses;
  CaretPxX, CaretPxY: pixel_t;
  HasCssBorder: Boolean;
  // Multiline vars
  NumLines, L: Integer;
  LineStr: string;
  LS, LE: Integer;
  SelLo, SelHi: Integer;
  SelStartPx, SelEndPx, LineY: pixel_t;
  SelLineStart, SelLineEnd: Integer;
  // Single-line vars
  Disp: string;
begin
  Canvas := TPixieCanvas(Cv);
  Cont := GetNativeContainer(Self);
  LineH := FCss.FontMetrics.Height;

  // Calculate padding box
  BX := P.X - Pad.Left;
  BY := P.Y - Pad.Top;
  BW := P.Width + Pad.Left + Pad.Right;
  BH := P.Height + Pad.Top + Pad.Bottom;

  // Check if CSS specifies border styling
  HasCssBorder := FCss.CssBorders.Left.Style > bsHidden;

  // Border colour — CSS or default
  if IsDisabled then
    BorderColor := TPixieWebColor.Create(204, 204, 204)
  else if HasCssBorder then
    BorderColor := FCss.CssBorders.Left.Color
  else
    BorderColor := TPixieWebColor.Create(153, 153, 153);

  // Background colour — CSS or default
  if IsDisabled then
    BgColor := TPixieWebColor.Create(245, 245, 245)
  else if FCss.Bg.Color.Alpha > 0 then
    BgColor := FCss.Bg.Color
  else
    BgColor := TPixieWebColor.Create(255, 255, 255);

  // Text colour
  if IsDisabled then
    TextColor := TPixieWebColor.Create(153, 153, 153)
  else
    TextColor := FCss.Color;

  // Border radius — CSS or default 3px
  if not FCss.CssBorders.Radius.TopLeftX.IsPredefined then
    Rad := FCss.CssBorders.Radius.CalcPercents(BW, BH)
  else
  begin
    Rad.Init;
    Rad.TopLeftX := 3; Rad.TopLeftY := 3;
    Rad.TopRightX := 3; Rad.TopRightY := 3;
    Rad.BottomRightX := 3; Rad.BottomRightY := 3;
    Rad.BottomLeftX := 3; Rad.BottomLeftY := 3;
  end;

  // Border width
  if HasCssBorder then
    BorderW := Max(1, FCss.CssBorders.Left.Width.Val)
  else
    BorderW := 1;

  PlaceholderColor := TPixieWebColor.Create(153, 153, 153);
  SelColor := TPixieWebColor.Create(51, 102, 204);
  SelTextColor := TPixieWebColor.Create(255, 255, 255);
  FocusColor := TPixieWebColor.Create(0, 112, 201);

  // Draw border and background — skip when CSS handles it via DrawBackground
  if not (HasCssBorder or (FCss.Bg.Color.Alpha > 0)) or IsDisabled then
  begin
    if IsFocused and (not IsDisabled) then
    begin
      // Focused: 2px blue border replaces the default grey
      Canvas.FillRoundedRect(BX, BY, BW, BH, Rad, FocusColor);
      Canvas.FillRoundedRect(BX + 2, BY + 2, BW - 4, BH - 4,
        Rad, BgColor);
    end
    else
    begin
      Canvas.FillRoundedRect(BX, BY, BW, BH, Rad, BorderColor);
      Canvas.FillRoundedRect(BX + BorderW, BY + BorderW,
        BW - BorderW * 2, BH - BorderW * 2, Rad, BgColor);
    end;
  end;

  // Adjust scroll only when caret moved (not on wheel scroll)
  if FCaretMoved then
  begin
    AdjustScroll(P.Width, P.Height);
    FCaretMoved := False;
  end;

  // Clip to content area
  ClipPos := TPixiePosition.Create(P.X, P.Y, P.Width, P.Height);
  Canvas.SaveState;
  NoRadius.Init;
  Canvas.SetClipRect(ClipPos, NoRadius);

  if FMultiLine then
  begin
    // --- Multiline rendering ---
    NumLines := GetLineCount;

    if (FValue = '') and (FPlaceholder <> '') then
      Canvas.DrawText(FPlaceholder, FCss.Font, PlaceholderColor,
        P.X, P.Y, P.Width, LineH)
    else
    begin
      if HasSelection and IsFocused then
      begin
        SelLo := Min(FSelStart, FSelEnd);
        SelHi := Max(FSelStart, FSelEnd);
      end
      else
      begin
        SelLo := -1;
        SelHi := -1;
      end;

      for L := 0 to NumLines - 1 do
      begin
        LineY := P.Y + L * LineH - FScrollY;
        // Skip lines outside visible area
        if LineY + LineH < P.Y then
          Continue;
        if LineY > P.Y + P.Height then
          Break;

        LS := GetLineStart(L);
        LE := GetLineEnd(L);
        LineStr := Copy(FValue, LS + 1, LE - LS);

        // Draw line text (normal colour)
        Canvas.DrawText(LineStr, FCss.Font, TextColor,
          P.X - FScrollX, LineY, P.Width + FScrollX + 100, LineH);

        // Draw selection highlight and white text on top
        if (SelLo >= 0) and (SelLo < LE) and (SelHi > LS) then
        begin
          SelLineStart := Max(SelLo, LS) - LS;
          SelLineEnd := Min(SelHi, LE) - LS;
          SelStartPx := Canvas.MeasureText(
            Copy(LineStr, 1, SelLineStart), FCss.Font);
          SelEndPx := Canvas.MeasureText(
            Copy(LineStr, 1, SelLineEnd), FCss.Font);
          if SelHi > LE then
            SelEndPx := SelEndPx + FCss.FontMetrics.ChWidth * 0.5;
          Canvas.FillRect(
            P.X + SelStartPx - FScrollX, LineY,
            SelEndPx - SelStartPx, LineH, SelColor);
          // Redraw selected portion in white
          Canvas.DrawText(
            Copy(LineStr, SelLineStart + 1, SelLineEnd - SelLineStart),
            FCss.Font, SelTextColor,
            P.X + SelStartPx - FScrollX, LineY,
            SelEndPx - SelStartPx + 100, LineH);
        end;
      end;
    end;
  end
  else
  begin
    // --- Single-line rendering ---
    Disp := DisplayText;
    if (Disp = '') and (FPlaceholder <> '') then
      Canvas.DrawText(FPlaceholder, FCss.Font, PlaceholderColor,
        P.X, P.Y, P.Width, LineH)
    else if Disp <> '' then
    begin
      // Draw full text in normal colour
      Canvas.DrawText(Disp, FCss.Font, TextColor,
        P.X - FScrollX, P.Y, P.Width + FScrollX + 100, LineH);

      // Selection highlight + white text on top
      if HasSelection and IsFocused then
      begin
        SelLo := Min(FSelStart, FSelEnd);
        SelHi := Max(FSelStart, FSelEnd);
        if FPassword then
        begin
          SelStartPx := Canvas.MeasureText(
            Copy(Disp, 1, UTF8CharCount(Copy(FValue, 1, SelLo)) * 3),
            FCss.Font);
          SelEndPx := Canvas.MeasureText(
            Copy(Disp, 1, UTF8CharCount(Copy(FValue, 1, SelHi)) * 3),
            FCss.Font);
        end
        else
        begin
          SelStartPx := Canvas.MeasureText(
            Copy(Disp, 1, SelLo), FCss.Font);
          SelEndPx := Canvas.MeasureText(
            Copy(Disp, 1, SelHi), FCss.Font);
        end;
        Canvas.FillRect(
          P.X + SelStartPx - FScrollX, P.Y,
          SelEndPx - SelStartPx, LineH, SelColor);
        // Redraw selected portion in white
        if FPassword then
          Canvas.DrawText(
            Copy(Disp,
              UTF8CharCount(Copy(FValue, 1, SelLo)) * 3 + 1,
              (UTF8CharCount(Copy(FValue, 1, SelHi)) -
               UTF8CharCount(Copy(FValue, 1, SelLo))) * 3),
            FCss.Font, SelTextColor,
            P.X + SelStartPx - FScrollX, P.Y,
            SelEndPx - SelStartPx + 100, LineH)
        else
          Canvas.DrawText(
            Copy(Disp, SelLo + 1, SelHi - SelLo),
            FCss.Font, SelTextColor,
            P.X + SelStartPx - FScrollX, P.Y,
            SelEndPx - SelStartPx + 100, LineH);
      end;
    end;
  end;

  // Draw caret
  ShowCaret := IsFocused and (not IsDisabled) and
    (Cont <> nil) and Cont.CaretVisible;
  if ShowCaret then
  begin
    CaretToPixelXY(CaretPxX, CaretPxY);
    Canvas.DrawLine(
      P.X + CaretPxX, P.Y + CaretPxY + 1,
      P.X + CaretPxX, P.Y + CaretPxY + LineH - 1,
      TextColor, 1);
  end;

  Canvas.RestoreState;
end;

procedure TPixieElTextBase.Draw(Hdc: PtrUInt; X, Y: pixel_t;
  Clip: PPixiePosition; Ri: Pointer);
var
  RenderIt: TPixieRenderItem;
  P: TPixiePosition;
  Pad: TPixieMargins;
  Cv: TPixieCanvas;
  IsFocused: Boolean;
begin
  inherited Draw(Hdc, X, Y, Clip, Ri);
  Cv := GetCanvas(Self);
  if Cv = nil then Exit;

  RenderIt := TPixieRenderItem(Ri);
  P := RenderIt.Pos;
  P.X := P.X + X;
  P.Y := P.Y + Y;

  if (Clip <> nil) and (not P.DoesIntersect(Clip^)) then
    Exit;
  if (P.Width <= 0) or (P.Height <= 0) then
    Exit;

  Pad := RenderIt.GetPaddings;
  IsFocused := FPseudoClasses.IndexOf(Ord(psid_focus)) >= 0;

  DrawContent(Cv, P, Pad, IsFocused, Ri);
end;

function TPixieElTextBase.CreateRenderItem(
  ParentRi: Pointer): Pointer;
var
  Ret: TPixieRenderInput;
begin
  Ret := TPixieRenderInput.Create(Self);
  Ret.SetParent(TPixieRenderItem(ParentRi));
  Result := Ret;
end;

{ TPixieElTextInput }

procedure TPixieElTextInput.ParseAttributes;
var
  TypeStr, MaxLenStr: string;
  Code: Integer;
begin
  TypeStr := LowerCase(GetAttr('type', 'text'));
  FPassword := TypeStr = 'password';
  FMultiLine := False;
  FValue := GetAttr('value', '');
  FPlaceholder := GetAttr('placeholder', '');
  MaxLenStr := GetAttr('maxlength', '');
  if MaxLenStr <> '' then
  begin
    Val(MaxLenStr, FMaxLength, Code);
    if Code <> 0 then
      FMaxLength := -1;
  end
  else
    FMaxLength := -1;
  inherited ParseAttributes;
end;

procedure TPixieElTextInput.GetContentSize(var Sz: TPixieSize;
  MaxWidth: pixel_t);
var
  Cv: TPixieCanvas;
  SizeAttr: string;
  CharCount, Code: Integer;
begin
  SizeAttr := GetAttr('size', '');
  if SizeAttr <> '' then
  begin
    Val(SizeAttr, CharCount, Code);
    if (Code <> 0) or (CharCount < 1) then
      CharCount := 20;
  end
  else
    CharCount := 20;

  Cv := GetCanvas(Self);
  if Cv <> nil then
    Sz.Width := Cv.MeasureText(StringOfChar('m', CharCount), FCss.Font)
  else
    Sz.Width := CharCount * FCss.FontMetrics.ChWidth;
  Sz.Height := FCss.FontMetrics.Height;
end;

function TPixieElTextInput.DumpGetName: string;
begin
  if FPassword then
    Result := 'input type="password"'
  else
    Result := 'input type="text"';
end;

{ TPixieElTextArea }

constructor TPixieElTextArea.Create(ADoc: TObject);
begin
  inherited Create(ADoc);
  FMultiLine := True;
  FRows := 2;
  FCols := 20;
end;

procedure TPixieElTextArea.ParseAttributes;
var
  S: string;
  Code: Integer;
  I: Integer;
  Ch: TPixieElement;
begin
  S := GetAttr('rows', '');
  if S <> '' then
  begin
    Val(S, FRows, Code);
    if (Code <> 0) or (FRows < 1) then
      FRows := 2;
  end;
  S := GetAttr('cols', '');
  if S <> '' then
  begin
    Val(S, FCols, Code);
    if (Code <> 0) or (FCols < 1) then
      FCols := 20;
  end;

  // Value from child text content
  FValue := '';
  for I := 0 to Children.Count - 1 do
  begin
    Ch := Children[I];
    Ch.GetText(FValue);
  end;
  if (Length(FValue) > 0) and (FValue[1] = #10) then
    Delete(FValue, 1, 1);
  FPlaceholder := GetAttr('placeholder', '');
  inherited ParseAttributes;
end;

procedure TPixieElTextArea.GetContentSize(var Sz: TPixieSize;
  MaxWidth: pixel_t);
var
  Cv: TPixieCanvas;
begin
  Cv := GetCanvas(Self);
  if Cv <> nil then
    Sz.Width := Cv.MeasureText(StringOfChar('m', FCols), FCss.Font)
  else
    Sz.Width := FCols * FCss.FontMetrics.ChWidth;
  Sz.Height := FRows * FCss.FontMetrics.Height;
end;

function TPixieElTextArea.OnKeyDown(Key: Word;
  Shift: TShiftState): Boolean;
var
  Line, Col: Integer;
  TargetLine: Integer;
  TargetLS, TargetLE: Integer;
  NewPos: Integer;
  Cv: TPixieCanvas;
  CurLineText: string;
  TargetLineText: string;
  CurXPx, TestPx: pixel_t;
  I, BestPos: Integer;
  BestDist, Dist: pixel_t;
  IsShift: Boolean;
begin
  IsShift := ssShift in Shift;

  case Key of
    VK_RETURN:
    begin
      if (not FReadOnly) and (not IsDisabled) then
      begin
        InsertText(#10);
        Result := True;
      end
      else
        Result := False;
    end;

    VK_UP, VK_DOWN:
    begin
      CaretToLineCol(Line, Col);

      if Key = VK_UP then
        TargetLine := Line - 1
      else
        TargetLine := Line + 1;

      if (TargetLine < 0) or (TargetLine >= GetLineCount) then
        Exit(True); // consume but do nothing at boundaries

      // Measure current X pixel position of caret within current line
      Cv := GetCanvas(Self);
      if Cv = nil then
        Exit(True);

      CurLineText := GetLineText(Line);
      CurXPx := Cv.MeasureText(Copy(CurLineText, 1, Col), FCss.Font);

      // Find closest byte position in target line
      TargetLS := GetLineStart(TargetLine);
      TargetLE := GetLineEnd(TargetLine);
      TargetLineText := Copy(FValue, TargetLS + 1, TargetLE - TargetLS);

      BestPos := 0;
      BestDist := Abs(CurXPx);
      I := 0;
      while I < Length(TargetLineText) do
      begin
        I := UTF8NextCharPos(TargetLineText, I);
        TestPx := Cv.MeasureText(Copy(TargetLineText, 1, I), FCss.Font);
        Dist := Abs(CurXPx - TestPx);
        if Dist < BestDist then
        begin
          BestDist := Dist;
          BestPos := I;
        end;
      end;

      NewPos := TargetLS + BestPos;

      if IsShift then
      begin
        if FSelStart < 0 then
          FSelStart := FCaretPos;
        FSelEnd := NewPos;
      end
      else
        ClearSelection;

      FCaretPos := NewPos;
      FCaretMoved := True;
      Result := True;
    end;

    VK_HOME:
    begin
      if ssCtrl in Shift then
      begin
        // Ctrl+Home = start of text
        NewPos := 0;
        if IsShift then
        begin
          if FSelStart < 0 then
            FSelStart := FCaretPos;
          FSelEnd := NewPos;
        end
        else
          ClearSelection;
        FCaretPos := NewPos;
        FCaretMoved := True;
      end
      else
        MoveCaretHome(IsShift);
      Result := True;
    end;

    VK_END:
    begin
      if ssCtrl in Shift then
      begin
        // Ctrl+End = end of text
        NewPos := Length(FValue);
        if IsShift then
        begin
          if FSelStart < 0 then
            FSelStart := FCaretPos;
          FSelEnd := NewPos;
        end
        else
          ClearSelection;
        FCaretPos := NewPos;
        FCaretMoved := True;
      end
      else
        MoveCaretEnd(IsShift);
      Result := True;
    end;
  else
    Result := inherited OnKeyDown(Key, Shift);
  end;
end;

function TPixieElTextArea.OnMouseWheel(Delta: Integer): Boolean;
var
  Ri: TPixieRenderItem;
  LineH, ContentH, VisibleH, MaxScroll: pixel_t;
  Steps: Integer;
begin
  Result := False;
  if GetLineCount <= 1 then
    Exit;

  LineH := FCss.FontMetrics.Height;
  ContentH := GetLineCount * LineH;

  Ri := TPixieRenderItem(GetRenderItem);
  if Ri <> nil then
    VisibleH := Ri.Pos.Height
  else
    VisibleH := FRows * LineH;

  MaxScroll := ContentH - VisibleH;
  if MaxScroll <= 0 then
    Exit;

  Steps := 3;
  if Delta > 0 then
    FScrollY := FScrollY - Steps * LineH
  else
    FScrollY := FScrollY + Steps * LineH;

  if FScrollY < 0 then
    FScrollY := 0;
  if FScrollY > MaxScroll then
    FScrollY := MaxScroll;

  Result := True;
end;

function TPixieElTextArea.DumpGetName: string;
begin
  Result := 'textarea';
end;

end.
