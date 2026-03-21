unit Pixie.SvgToPdf;

// SVG-to-PDF vector conversion.
// Inherits SVG parsing from TPixieSvgRendererBase and overrides abstract
// drawing primitives to emit PDF path operators into a Form XObject.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections,
  Pixie.Types, Pixie.WebColor, Pixie.TrueType, Pixie.PdfWriter,
  Pixie.SvgRenderer;

type
  { TPixieSvgFontInfo - font used in SVG text }

  TPixieSvgFontInfo = record
    TtFont: TPixieTrueTypeFont;
    PdfName: AnsiString;
    Type0ObjId: Integer;
    UsedGlyphs: TPixieGlyphMap;
  end;

  TPixieSvgFontInfoList = TList<TPixieSvgFontInfo>;

  { TPixieSvgRenderer - PDF SVG renderer }

  TPixieSvgRenderer = class(TPixieSvgRendererBase)
  private
    FWriter: TPixiePdfWriter;
    FFontCache: TPixieTrueTypeFontCache;
    FStream: TMemoryStream;
    FResourceExtGState: AnsiString;
    FFonts: TPixieSvgFontInfoList;
    FGsCounter: Integer;
    FFontCounter: Integer;

    procedure Emit(const S: AnsiString);
    procedure EmitLn(const S: AnsiString);
    procedure SetPdfColor(const Color: TPixieWebColor; Fill: Boolean);

    // Font helpers
    function FindOrCreateSvgFont(const Family: string;
      Weight: Integer): Integer;
    procedure BuildSvgFontObjects;
  protected
    // Override abstract drawing primitives with PDF operators
    procedure DoMoveTo(X, Y: Single); override;
    procedure DoLineTo(X, Y: Single); override;
    procedure DoCurveTo(X1, Y1, X2, Y2, X3, Y3: Single); override;
    procedure DoClosePath; override;
    procedure DoSaveState; override;
    procedure DoRestoreState; override;
    procedure DoSetTransform(const M: TPixieSvgMatrix); override;
    procedure DoFillAndStroke(const State: TPixieSvgState); override;
    procedure DoBeginOpacity(Opacity: Single); override;
    procedure DoEndOpacity; override;

    // Override text rendering for PDF font embedding
    procedure RenderText(Node: Pointer;
      const State: TPixieSvgState); override;
  public
    constructor Create(AWriter: TPixiePdfWriter;
      AFontCache: TPixieTrueTypeFontCache);
    destructor Destroy; override;

    function RenderToFormXObject(Data: Pointer; Size: Integer;
      out OutWidth, OutHeight: Single): Integer;
  end;

implementation

uses
  Math, {$IFDEF FPC}DOM, XMLRead,{$ELSE}Pixie.SimpleXml,{$ENDIF} Pixie.Utf8;

{$IFDEF FPC}
function DomToStr(const S: WideString): string; inline;
begin Result := UTF8Encode(S); end;
{$ELSE}
function DomToStr(const S: WideString): string; inline;
begin Result := S; end;
{$ENDIF}

// ===========================================================================
// Construction
// ===========================================================================

constructor TPixieSvgRenderer.Create(AWriter: TPixiePdfWriter;
  AFontCache: TPixieTrueTypeFontCache);
begin
  inherited Create;
  FWriter := AWriter;
  FFontCache := AFontCache;
  FStream := TMemoryStream.Create;
  FFonts := TPixieSvgFontInfoList.Create;
  FGsCounter := 0;
  FFontCounter := 0;
end;

destructor TPixieSvgRenderer.Destroy;
var
  I: Integer;
begin
  for I := 0 to FFonts.Count - 1 do
    FFonts[I].UsedGlyphs.Free;
  FFonts.Free;
  FStream.Free;
  inherited;
end;

// ===========================================================================
// Content stream writing
// ===========================================================================

procedure TPixieSvgRenderer.Emit(const S: AnsiString);
begin
  if Length(S) > 0 then
    FStream.Write(S[1], Length(S));
end;

procedure TPixieSvgRenderer.EmitLn(const S: AnsiString);
begin
  Emit(S + #10);
end;

procedure TPixieSvgRenderer.SetPdfColor(const Color: TPixieWebColor;
  Fill: Boolean);
var
  R, G, B: Single;
begin
  R := Color.Red / 255.0;
  G := Color.Green / 255.0;
  B := Color.Blue / 255.0;
  if Fill then
    EmitLn(PdfFloat(R) + ' ' + PdfFloat(G) + ' ' + PdfFloat(B) + ' rg')
  else
    EmitLn(PdfFloat(R) + ' ' + PdfFloat(G) + ' ' + PdfFloat(B) + ' RG');
end;

// ===========================================================================
// Abstract drawing primitive overrides — PDF operators
// ===========================================================================

procedure TPixieSvgRenderer.DoMoveTo(X, Y: Single);
begin
  EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' m');
end;

procedure TPixieSvgRenderer.DoLineTo(X, Y: Single);
begin
  EmitLn(PdfFloat(X) + ' ' + PdfFloat(Y) + ' l');
end;

procedure TPixieSvgRenderer.DoCurveTo(X1, Y1, X2, Y2, X3, Y3: Single);
begin
  EmitLn(PdfFloat(X1) + ' ' + PdfFloat(Y1) + ' ' +
         PdfFloat(X2) + ' ' + PdfFloat(Y2) + ' ' +
         PdfFloat(X3) + ' ' + PdfFloat(Y3) + ' c');
end;

procedure TPixieSvgRenderer.DoClosePath;
begin
  EmitLn('h');
end;

procedure TPixieSvgRenderer.DoSaveState;
begin
  EmitLn('q');
end;

procedure TPixieSvgRenderer.DoRestoreState;
begin
  EmitLn('Q');
end;

procedure TPixieSvgRenderer.DoSetTransform(const M: TPixieSvgMatrix);
begin
  EmitLn(PdfFloat(M.A) + ' ' + PdfFloat(M.B) + ' ' +
         PdfFloat(M.C) + ' ' + PdfFloat(M.D) + ' ' +
         PdfFloat(M.E) + ' ' + PdfFloat(M.F) + ' cm');
end;

procedure TPixieSvgRenderer.DoFillAndStroke(const State: TPixieSvgState);
begin
  if State.HasFill and State.HasStroke then
  begin
    SetPdfColor(State.FillColor, True);
    SetPdfColor(State.StrokeColor, False);
    EmitLn(PdfFloat(State.StrokeWidth) + ' w');
    EmitLn('B');
  end
  else if State.HasFill then
  begin
    SetPdfColor(State.FillColor, True);
    EmitLn('f');
  end
  else if State.HasStroke then
  begin
    SetPdfColor(State.StrokeColor, False);
    EmitLn(PdfFloat(State.StrokeWidth) + ' w');
    EmitLn('S');
  end
  else
    EmitLn('n');
end;

procedure TPixieSvgRenderer.DoBeginOpacity(Opacity: Single);
var
  GsObj: TPixiePdfObject;
  GsName: AnsiString;
begin
  GsObj := FWriter.AllocObject;
  GsObj.AddEntry('Type', '/ExtGState');
  GsObj.AddEntry('ca', PdfFloat(Opacity));
  GsObj.AddEntry('CA', PdfFloat(Opacity));

  Inc(FGsCounter);
  GsName := 'SvgGS' + AnsiString(IntToStr(FGsCounter));
  FResourceExtGState := FResourceExtGState + '/' + GsName + ' ' +
    PdfRef(GsObj.Id) + ' ';

  EmitLn('/' + GsName + ' gs');
end;

procedure TPixieSvgRenderer.DoEndOpacity;
begin
  // No-op for PDF — restore handled by q/Q
end;

// ===========================================================================
// Font helpers
// ===========================================================================

function TPixieSvgRenderer.FindOrCreateSvgFont(const Family: string;
  Weight: Integer): Integer;
var
  I: Integer;
  FilePath: string;
  TtFont: TPixieTrueTypeFont;
  Key: string;
  Info: TPixieSvgFontInfo;
begin
  // Check existing
  for I := 0 to FFonts.Count - 1 do
  begin
    if (FFonts[I].TtFont <> nil) and
       (LowerCase(FFonts[I].TtFont.FamilyName) = LowerCase(Family)) then
    begin
      Result := I;
      Exit;
    end;
  end;

  // Find font file
  Key := LowerCase(Family) + ':' + IntToStr(Weight) + ':0';
  if not FFontCache.TryGetValue(Key, TtFont) then
  begin
    FilePath := PixieFindFontFile(Family, Weight, False);
    if FilePath = '' then
    begin
      // Try fallbacks
      {$IFDEF MSWINDOWS}
      FilePath := PixieFindFontFile('Segoe UI', Weight, False);
      if FilePath = '' then
        FilePath := PixieFindFontFile('Arial', Weight, False);
      {$ENDIF}
      {$IFDEF LINUX}
      FilePath := PixieFindFontFile('DejaVu Sans', Weight, False);
      {$ENDIF}
      {$IFDEF DARWIN}
      FilePath := PixieFindFontFile('Helvetica', Weight, False);
      {$ENDIF}
    end;

    TtFont := TPixieTrueTypeFont.Create;
    if (FilePath <> '') and TtFont.LoadFromFile(FilePath) then
      FFontCache.Add(Key, TtFont)
    else
    begin
      TtFont.Free;
      Result := -1;
      Exit;
    end;
  end;

  Inc(FFontCounter);
  Info.TtFont := TtFont;
  Info.PdfName := 'SvgF' + AnsiString(IntToStr(FFontCounter));
  Info.Type0ObjId := 0;
  Info.UsedGlyphs := TPixieGlyphMap.Create;
  FFonts.Add(Info);
  Result := FFonts.Count - 1;
end;

procedure TPixieSvgRenderer.BuildSvgFontObjects;
var
  I, J, K, ChunkSize: Integer;
  Info: TPixieSvgFontInfo;
  Scale: Single;
  FontFile, Descriptor, CidFont, Type0, ToUnicode: TPixiePdfObject;
  FontData: TBytes;
  WArray, CmapStr: AnsiString;
  SortedGlyphs: TList<UInt16>;
  Pair: TPair<UInt16, UInt32>;
  GlyphId, AdvWidth: UInt16;
  Flags: Integer;
  Asc, Desc: Single;
begin
  for I := 0 to FFonts.Count - 1 do
  begin
    Info := FFonts[I];
    if (Info.TtFont = nil) or (Info.UsedGlyphs.Count = 0) then Continue;

    Scale := 1000.0 / Info.TtFont.UnitsPerEm;

    // FontFile2
    FontFile := FWriter.AllocObject;
    FontData := Info.TtFont.BuildSubsetFont(Info.UsedGlyphs);
    FontFile.AddEntry('Length1', AnsiString(IntToStr(Length(FontData))));
    FontFile.SetStream(FontData, True);

    // FontDescriptor
    Descriptor := FWriter.AllocObject;
    Flags := 32;
    if Info.TtFont.ItalicAngle <> 0 then
      Flags := Flags or 64;
    if Info.TtFont.WeightClass >= 700 then
      Flags := Flags or (1 shl 18);

    Asc := Info.TtFont.Ascent * Scale;
    Desc := Info.TtFont.Descent * Scale;

    Descriptor.AddEntry('Type', '/FontDescriptor');
    Descriptor.AddEntry('FontName', '/' + Info.PdfName + 'TT');
    Descriptor.AddEntry('Flags', AnsiString(IntToStr(Flags)));
    Descriptor.AddEntry('FontBBox', PdfRect(
      Info.TtFont.BBoxXMin * Scale, Info.TtFont.BBoxYMin * Scale,
      Info.TtFont.BBoxXMax * Scale, Info.TtFont.BBoxYMax * Scale));
    Descriptor.AddEntry('ItalicAngle', PdfFloat(Info.TtFont.ItalicAngle));
    Descriptor.AddEntry('Ascent', PdfFloat(Asc));
    Descriptor.AddEntry('Descent', PdfFloat(Desc));
    Descriptor.AddEntry('CapHeight', PdfFloat(Info.TtFont.CapHeight * Scale));
    Descriptor.AddEntry('StemV', '80');
    Descriptor.AddEntry('FontFile2', PdfRef(FontFile.Id));

    // W array
    SortedGlyphs := TList<UInt16>.Create;
    try
      for Pair in Info.UsedGlyphs do
        SortedGlyphs.Add(Pair.Key);
      SortedGlyphs.Sort;

      WArray := '[';
      for J := 0 to SortedGlyphs.Count - 1 do
      begin
        GlyphId := SortedGlyphs[J];
        AdvWidth := Info.TtFont.GetGlyphWidth(GlyphId);
        WArray := WArray + AnsiString(IntToStr(GlyphId)) + ' [' +
          PdfFloat(AdvWidth * Scale) + '] ';
      end;
      WArray := WArray + ']';
    finally
      SortedGlyphs.Free;
    end;

    // CIDFontType2
    CidFont := FWriter.AllocObject;
    CidFont.AddEntry('Type', '/Font');
    CidFont.AddEntry('Subtype', '/CIDFontType2');
    CidFont.AddEntry('BaseFont', '/' + Info.PdfName + 'TT');
    CidFont.AddEntry('CIDSystemInfo',
      '<< /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>');
    CidFont.AddEntry('FontDescriptor', PdfRef(Descriptor.Id));
    CidFont.AddEntry('W', WArray);
    CidFont.AddEntry('DW', '1000');

    // ToUnicode CMap
    ToUnicode := FWriter.AllocObject;
    CmapStr :=
      '/CIDInit /ProcSet findresource begin'#10 +
      '12 dict begin'#10 +
      'begincmap'#10 +
      '/CIDSystemInfo'#10 +
      '<< /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def'#10 +
      '/CMapName /Adobe-Identity-UCS def'#10 +
      '/CMapType 2 def'#10 +
      '1 begincodespacerange'#10 +
      '<0000> <FFFF>'#10 +
      'endcodespacerange'#10;

    SortedGlyphs := TList<UInt16>.Create;
    try
      for Pair in Info.UsedGlyphs do
        SortedGlyphs.Add(Pair.Key);
      SortedGlyphs.Sort;

      if SortedGlyphs.Count > 0 then
      begin
        J := 0;
        while J < SortedGlyphs.Count do
        begin
          ChunkSize := SortedGlyphs.Count - J;
          if ChunkSize > 100 then ChunkSize := 100;
          CmapStr := CmapStr +
            AnsiString(IntToStr(ChunkSize)) + ' beginbfchar'#10;
          for K := J to J + ChunkSize - 1 do
          begin
            GlyphId := SortedGlyphs[K];
            CmapStr := CmapStr +
              '<' + AnsiString(LowerCase(IntToHex(GlyphId, 4))) + '> ' +
              '<' + AnsiString(LowerCase(IntToHex(
                Info.UsedGlyphs[GlyphId], 4))) + '>'#10;
          end;
          CmapStr := CmapStr + 'endbfchar'#10;
          Inc(J, ChunkSize);
        end;
      end;
    finally
      SortedGlyphs.Free;
    end;

    CmapStr := CmapStr +
      'endcmap'#10 +
      'CMapName currentdict /CMap defineresource pop'#10 +
      'end'#10 +
      'end'#10;
    ToUnicode.SetStream(TEncoding.ASCII.GetBytes(string(CmapStr)), True);

    // Type0
    Type0 := FWriter.AllocObject;
    Type0.AddEntry('Type', '/Font');
    Type0.AddEntry('Subtype', '/Type0');
    Type0.AddEntry('BaseFont', '/' + Info.PdfName + 'TT');
    Type0.AddEntry('Encoding', '/Identity-H');
    Type0.AddEntry('DescendantFonts', '[' + PdfRef(CidFont.Id) + ']');
    Type0.AddEntry('ToUnicode', PdfRef(ToUnicode.Id));

    // Update info with object ID
    Info.Type0ObjId := Type0.Id;
    FFonts[I] := Info;
  end;
end;

// ===========================================================================
// Text rendering (PDF — uses glyph-based font embedding)
// ===========================================================================

procedure TPixieSvgRenderer.RenderText(Node: Pointer;
  const State: TPixieSvgState);
var
  X, Y: Single;
  TextContent: string;
  FontIdx: Integer;
  Info: TPixieSvgFontInfo;
  PtSize, Scale: Single;
  I, Len: Integer;
  Codepoint: UInt32;
  GlyphId: UInt16;
  HexStr: AnsiString;
  NeedRestore: Boolean;
  Child: TDOMNode;
  TotalWidth, GlyphW: Single;
begin
  X := ParseSvgFloat(GetAttr(Node, 'x', '0'));
  Y := ParseSvgFloat(GetAttr(Node, 'y', '0'));

  // Collect text from child text nodes
  TextContent := '';
  Child := TDOMNode(Node).FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = TEXT_NODE then
      TextContent := TextContent + DomToStr(Child.NodeValue);
    Child := Child.NextSibling;
  end;

  TextContent := Trim(TextContent);
  if TextContent = '' then Exit;

  FontIdx := FindOrCreateSvgFont(State.FontFamily, State.FontWeight);
  if FontIdx < 0 then Exit;

  Info := FFonts[FontIdx];
  if Info.TtFont = nil then Exit;

  PtSize := State.FontSize;
  Scale := PtSize / Info.TtFont.UnitsPerEm;

  DoSaveState;
  ApplyNodeTransform(Node);
  ApplyOpacity(State, NeedRestore);

  SetPdfColor(State.FillColor, True);

  // Handle text-anchor
  if GetAttr(Node, 'text-anchor') = 'middle' then
  begin
    TotalWidth := 0;
    I := 1;
    Len := Length(TextContent);
    while I <= Len do
    begin
      Codepoint := ReadUtf8Char(TextContent, I);
      if Codepoint = 0 then Break;
      GlyphId := Info.TtFont.CharToGlyph(Codepoint);
      TotalWidth := TotalWidth + Info.TtFont.GetGlyphWidth(GlyphId) * Scale;
      if State.LetterSpacing > 0 then
        TotalWidth := TotalWidth + State.LetterSpacing;
    end;
    X := X - TotalWidth / 2;
  end;

  EmitLn('BT');
  EmitLn('/' + Info.PdfName + ' ' + PdfFloat(PtSize) + ' Tf');
  EmitLn('1 0 0 -1 ' + PdfFloat(X) + ' ' + PdfFloat(Y) + ' Tm');

  if (State.LetterSpacing > 0) then
  begin
    I := 1;
    Len := Length(TextContent);
    while I <= Len do
    begin
      Codepoint := ReadUtf8Char(TextContent, I);
      if Codepoint = 0 then Break;
      GlyphId := Info.TtFont.CharToGlyph(Codepoint);
      if not Info.UsedGlyphs.ContainsKey(GlyphId) then
        Info.UsedGlyphs.Add(GlyphId, Codepoint);

      HexStr := '<' + AnsiString(LowerCase(IntToHex(GlyphId, 4))) + '>';
      GlyphW := Info.TtFont.GetGlyphWidth(GlyphId) * Scale + State.LetterSpacing;
      EmitLn(HexStr + ' Tj');
      EmitLn(PdfFloat(GlyphW) + ' 0 Td');
    end;
    FFonts[FontIdx] := Info;
  end
  else
  begin
    HexStr := '<';
    I := 1;
    Len := Length(TextContent);
    while I <= Len do
    begin
      Codepoint := ReadUtf8Char(TextContent, I);
      if Codepoint = 0 then Break;
      GlyphId := Info.TtFont.CharToGlyph(Codepoint);
      if not Info.UsedGlyphs.ContainsKey(GlyphId) then
        Info.UsedGlyphs.Add(GlyphId, Codepoint);
      HexStr := HexStr + AnsiString(LowerCase(IntToHex(GlyphId, 4)));
    end;
    HexStr := HexStr + '>';
    EmitLn(HexStr + ' Tj');
    FFonts[FontIdx] := Info;
  end;

  EmitLn('ET');
  if NeedRestore then DoEndOpacity;
  DoRestoreState;
end;

// ===========================================================================
// Main entry point
// ===========================================================================

function TPixieSvgRenderer.RenderToFormXObject(Data: Pointer; Size: Integer;
  out OutWidth, OutHeight: Single): Integer;
var
  FormObj: TPixiePdfObject;
  Buf: TBytes;
  MatrixStr, ResourceStr: AnsiString;
  I: Integer;
begin
  Result := 0;
  OutWidth := 0;
  OutHeight := 0;

  if not ParseSvg(Data, Size, OutWidth, OutHeight) then Exit;
  try
    // Clear stream and render
    FStream.Size := 0;
    RenderDocument;

    // Build font objects for any text rendered
    BuildSvgFontObjects;

    // Create Form XObject
    // DrawImage maps unit square [0,0,1,1] to destination rect.
    // Matrix must normalise SVG viewBox coords to [0,0,1,1] and
    // flip Y (SVG is Y-down, PDF DrawImage is Y-up).
    MatrixStr := '[' +
      PdfFloat(1.0 / FViewBoxW) + ' 0 0 ' +
      PdfFloat(-1.0 / FViewBoxH) + ' ' +
      PdfFloat(-FViewBoxX / FViewBoxW) + ' ' +
      PdfFloat((FViewBoxY + FViewBoxH) / FViewBoxH) + ']';

    // Build resource dictionary
    ResourceStr := '<< ';
    if FResourceExtGState <> '' then
      ResourceStr := ResourceStr + '/ExtGState << ' + FResourceExtGState + ' >> ';
    if FFonts.Count > 0 then
    begin
      ResourceStr := ResourceStr + '/Font << ';
      for I := 0 to FFonts.Count - 1 do
        if FFonts[I].Type0ObjId <> 0 then
          ResourceStr := ResourceStr + '/' + FFonts[I].PdfName + ' ' +
            PdfRef(FFonts[I].Type0ObjId) + ' ';
      ResourceStr := ResourceStr + '>> ';
    end;
    ResourceStr := ResourceStr + '>>';

    // Create the Form XObject
    FormObj := FWriter.AllocObject;
    FormObj.AddEntry('Type', '/XObject');
    FormObj.AddEntry('Subtype', '/Form');
    FormObj.AddEntry('BBox', '[0 0 ' + PdfFloat(FViewBoxW) + ' ' +
      PdfFloat(FViewBoxH) + ']');
    FormObj.AddEntry('Matrix', MatrixStr);
    FormObj.AddEntry('Resources', ResourceStr);

    SetLength(Buf, FStream.Size);
    if FStream.Size > 0 then
    begin
      FStream.Position := 0;
      FStream.Read(Buf[0], Length(Buf));
    end;
    FormObj.SetStream(Buf, True);

    Result := FormObj.Id;
  finally
    ClearDocument;
  end;
end;

end.
