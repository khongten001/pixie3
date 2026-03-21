unit Pixie.NativeContainer;

// Concrete TPixieContainer implementation that delegates all drawing
// to a TPixieCanvas instance. This contains all HTML-specific rendering
// logic (background layers, borders, list markers, etc.) written once
// and shared across all platforms.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Math, Generics.Collections,
  {$IFDEF FPC}LCLType, FPImage,{$ELSE}{$IFDEF MSWINDOWS}Windows,{$ENDIF}{$ENDIF}
  Pixie.Types, Pixie.WebColor, Pixie.Borders,
  Pixie.Background, Pixie.FontDescription, Pixie.CssLength,
  Pixie.Container, Pixie.Canvas;

type
  TPixieAnchorClickEvent = procedure(Sender: TObject;
    const Url: string) of object;
  TPixieElementClickEvent = function(Sender: TObject;
    El: TObject): Boolean of object;
  TPixieFetchUrlEvent = procedure(Sender: TObject;
    const Url: string; Stream: TStream; var Success: Boolean) of object;

  TPixieImageCacheMap = TDictionary<string, TPixieImageHandle>;

  TPixiePendingImage = record
    Data: TMemoryStream;
  end;
  TPixiePendingImageMap = TDictionary<string, TPixiePendingImage>;

  { TPixieNativeContainer }

  TPixieNativeContainer = class(TPixieContainer)
  private
    FCanvas: TPixieCanvas;
    FImages: TPixieImageCacheMap;
    FPendingImages: TPixiePendingImageMap;
    FBaseUrl: string;
    FDefaultFontSize: pixel_t;
    FDefaultFontName: string;
    FViewportWidth: pixel_t;
    FViewportHeight: pixel_t;
    FOnAnchorClick: TPixieAnchorClickEvent;
    FOnElementClick: TPixieElementClickEvent;
    FOnFetchUrl: TPixieFetchUrlEvent;
    FOnSetCaption: TNotifyEvent;
    FCaption: string;
    FCursor: string;
    FCaretVisible: Boolean;

    function ResolveUrl(const Src, ABaseUrl: string): string;
    function GetCachedImage(const Src, ABaseUrl: string): TPixieImageHandle;
    function DecodeStreamToHandle(Stream: TStream): TPixieImageHandle;
    function LoadFromResource(const ResName: string): TPixieImageHandle;
    function ResolvePendingImage(const Key: string): TPixieImageHandle;
  public
    constructor Create(ACanvas: TPixieCanvas);
    destructor Destroy; override;

    procedure RegisterImage(const Name: string; Stream: TStream);
    procedure UnregisterImage(const Name: string);

    property Canvas: TPixieCanvas read FCanvas;
    property Caption: string read FCaption;
    property Cursor: string read FCursor;
    property DefaultFontSize: pixel_t read FDefaultFontSize write FDefaultFontSize;
    property DefaultFontName: string read FDefaultFontName write FDefaultFontName;
    property ViewportWidth: pixel_t read FViewportWidth write FViewportWidth;
    property ViewportHeight: pixel_t read FViewportHeight write FViewportHeight;
    property OnAnchorClickEvent: TPixieAnchorClickEvent
      read FOnAnchorClick write FOnAnchorClick;
    property OnElementClickEvent: TPixieElementClickEvent
      read FOnElementClick write FOnElementClick;
    property OnFetchUrlEvent: TPixieFetchUrlEvent
      read FOnFetchUrl write FOnFetchUrl;
    property OnSetCaptionEvent: TNotifyEvent
      read FOnSetCaption write FOnSetCaption;
    property BaseUrl: string read FBaseUrl write FBaseUrl;
    property CaretVisible: Boolean read FCaretVisible write FCaretVisible;

    // ---- TPixieContainer overrides ----

    // Font management
    function CreateFont(const Descr: TPixieFontDescription; Doc: TObject;
      out Metrics: TPixieFontMetrics): PtrUInt; override;
    procedure DeleteFont(HFont: PtrUInt); override;
    function TextWidth(const Text: string; HFont: PtrUInt): pixel_t; override;
    procedure DrawText(Hdc: PtrUInt; const Text: string; HFont: PtrUInt;
      Color: TPixieWebColor; const Pos: TPixiePosition); override;
    function PtToPx(Pt: Single): pixel_t; override;
    function GetDefaultFontSize: pixel_t; override;
    function GetDefaultFontName: string; override;

    // Drawing
    procedure DrawListMarker(Hdc: PtrUInt;
      const Marker: TPixieListMarker); override;
    procedure LoadImage(const Src, ABaseUrl: string;
      RedrawOnReady: Boolean); override;
    procedure GetImageSize(const Src, ABaseUrl: string;
      out Sz: TPixieSize); override;
    procedure DrawImage(Hdc: PtrUInt; const Layer: TPixieBackgroundLayer;
      const Url, ABaseUrl: string); override;
    procedure DrawSolidFill(Hdc: PtrUInt; const Layer: TPixieBackgroundLayer;
      Color: TPixieWebColor); override;
    procedure DrawLinearGradient(Hdc: PtrUInt;
      const Layer: TPixieBackgroundLayer;
      const Gradient: TPixieLinearGradientLayer); override;
    procedure DrawRadialGradient(Hdc: PtrUInt;
      const Layer: TPixieBackgroundLayer;
      const Gradient: TPixieRadialGradientLayer); override;
    procedure DrawConicGradient(Hdc: PtrUInt;
      const Layer: TPixieBackgroundLayer;
      const Gradient: TPixieConicGradientLayer); override;
    procedure DrawBorders(Hdc: PtrUInt; const Borders: TPixieBorders;
      const DrawPos: TPixiePosition; IsRoot: Boolean); override;

    // Document events
    procedure SetCaption(const ACaption: string); override;
    procedure SetBaseUrl(const ABaseUrl: string); override;
    procedure Link(Doc: TObject; El: TObject); override;
    procedure OnAnchorClick(const Url: string; El: TObject); override;
    function OnElementClick(El: TObject): Boolean; override;
    procedure OnMouseEvent(El: TObject; Event: TPixieMouseEvent); override;
    procedure SetCursor(const ACursor: string); override;

    // Text & CSS
    procedure TransformText(var Text: string;
      Tt: TPixieTextTransform); override;
    procedure ImportCss(var Text: string; const Url: string;
      var ABaseUrl: string); override;

    // Selection highlight
    procedure DrawHighlight(Hdc: PtrUInt; const Pos: TPixiePosition;
      Color: TPixieWebColor); override;

    // Opacity layers
    procedure PushOpacity(AOpacity: Single); override;
    procedure PopOpacity; override;

    // Clipping
    procedure SetClip(const Pos: TPixiePosition;
      const BdrRadius: TPixieBorderRadiuses); override;
    procedure DelClip; override;

    // Viewport & media
    procedure GetViewport(out Viewport: TPixiePosition); override;
    procedure GetMediaFeatures(out Media: TPixieMediaFeatures); override;
    procedure GetLanguage(out Language, Culture: string); override;

    // Element creation
    function CreateElement(const TagName: string; Attrs: TPixieStringMap;
      Doc: TObject): TObject; override;
  end;

implementation

uses
  {$IFDEF FPC}FPReadPNG, FPReadJPEG, FPReadBMP, FPReadGIF,{$ENDIF}
  Pixie.Url;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function IsHttpUrl(const Url: string): Boolean;
begin
  Result := (Length(Url) > 7) and
    ((Copy(Url, 1, 7) = 'http://') or (Copy(Url, 1, 8) = 'https://'));
end;

function TPixieNativeContainer.ResolveUrl(
  const Src, ABaseUrl: string): string;
var
  Base: string;
begin
  // Already a full URL — return as-is
  if Pos('://', Src) > 0 then
  begin
    Result := Src;
    Exit;
  end;

  // Determine effective base
  if ABaseUrl <> '' then
    Base := ABaseUrl
  else
    Base := FBaseUrl;

  // HTTP base — use RFC 3986 URL resolution for all references
  // (root-relative /path, protocol-relative //host, and relative paths)
  if IsHttpUrl(Base) then
  begin
    Result := PixieResolveUrl(TPixieUrl.Create(Base),
      TPixieUrl.Create(Src)).Str;
    Exit;
  end;

  // Local filesystem: absolute path — return as-is
  if (Length(Src) > 0) and
     ((Src[1] = '/') or (Src[1] = '\') or
      ((Length(Src) > 1) and (Src[2] = ':'))) then
  begin
    Result := Src;
    Exit;
  end;

  if Base = '' then
    Result := Src
  else
    Result := IncludeTrailingPathDelimiter(Base) + Src;
end;

function TPixieNativeContainer.GetCachedImage(
  const Src, ABaseUrl: string): TPixieImageHandle;
var
  Key: string;
  FetchStream: TMemoryStream;
  Success: Boolean;
begin
  // #name — pre-registered image
  if (Length(Src) > 1) and (Src[1] = '#') then
  begin
    if FImages.TryGetValue(Src, Result) then
      Exit;
    Result := ResolvePendingImage(Src);
    Exit;
  end;

  // @resname — load from Lazarus resource
  if (Length(Src) > 1) and (Src[1] = '@') then
  begin
    if FImages.TryGetValue(Src, Result) then
      Exit;
    Result := LoadFromResource(Copy(Src, 2, MaxInt));
    if Result <> 0 then
      FImages.Add(Src, Result);
    Exit;
  end;

  // Normal URL or file path
  Key := ResolveUrl(Src, ABaseUrl);
  if FImages.TryGetValue(Key, Result) then
    Exit;

  // HTTP URL — fetch via event callback
  if IsHttpUrl(Key) then
  begin
    Result := 0;
    if Assigned(FOnFetchUrl) then
    begin
      FetchStream := TMemoryStream.Create;
      try
        Success := False;
        FOnFetchUrl(Self, Key, FetchStream, Success);
        if Success and (FetchStream.Size > 0) then
        begin
          FetchStream.Position := 0;
          Result := DecodeStreamToHandle(FetchStream);
        end;
      finally
        FetchStream.Free;
      end;
    end;
    if Result <> 0 then
      FImages.Add(Key, Result);
    Exit;
  end;

  // Local file
  Result := FCanvas.LoadImage(Key);
  if Result <> 0 then
    FImages.Add(Key, Result);
end;

// ---------------------------------------------------------------------------
// Image format detection and stream decoding
// ---------------------------------------------------------------------------

type
  TPixieStreamImageType = (sitUnknown, sitPng, sitJpeg, sitBmp, sitGif, sitSvg);

function DetectImageType(Stream: TStream): TPixieStreamImageType;
var
  Header: array[0..7] of Byte;
  SavePos: Int64;
  BytesRead: Integer;
begin
  Result := sitUnknown;
  SavePos := Stream.Position;
  try
    FillChar(Header, SizeOf(Header), 0);
    BytesRead := Stream.Read(Header, SizeOf(Header));
    if BytesRead < 4 then Exit;

    // PNG: 89 50 4E 47
    if (Header[0] = $89) and (Header[1] = $50) and
       (Header[2] = $4E) and (Header[3] = $47) then
    begin
      Result := sitPng;
      Exit;
    end;

    // JPEG: FF D8 FF
    if (Header[0] = $FF) and (Header[1] = $D8) and
       (Header[2] = $FF) then
    begin
      Result := sitJpeg;
      Exit;
    end;

    // BMP: 42 4D
    if (Header[0] = $42) and (Header[1] = $4D) then
    begin
      Result := sitBmp;
      Exit;
    end;

    // GIF: 47 49 46 38
    if (Header[0] = $47) and (Header[1] = $49) and
       (Header[2] = $46) and (Header[3] = $38) then
    begin
      Result := sitGif;
      Exit;
    end;

    // SVG: look for '<svg' or '<?xml' in text content
    if (Header[0] = Ord('<')) then
    begin
      if (Header[1] = Ord('s')) and (Header[2] = Ord('v')) and
         (Header[3] = Ord('g')) then
      begin
        Result := sitSvg;
        Exit;
      end;
      if (Header[1] = Ord('?')) and (Header[2] = Ord('x')) and
         (Header[3] = Ord('m')) then
      begin
        Result := sitSvg;
        Exit;
      end;
    end;

    // SVG with UTF-8 BOM: EF BB BF 3C
    if (Header[0] = $EF) and (Header[1] = $BB) and
       (Header[2] = $BF) and (Header[3] = Ord('<')) then
    begin
      Result := sitSvg;
      Exit;
    end;
  finally
    Stream.Position := SavePos;
  end;
end;

function TPixieNativeContainer.DecodeStreamToHandle(
  Stream: TStream): TPixieImageHandle;
var
  SvgBuf: TMemoryStream;
{$IFDEF FPC}
  Img: TFPMemoryImage;
  Pixels: PByte;
  Pitch, X, Y, W, H: Integer;
  Colour: TFPColor;
  Dst: PByte;
  A, R, G, B: Byte;
{$ENDIF}
begin
  Result := 0;
  if (FCanvas = nil) or (Stream = nil) or (Stream.Size = 0) then Exit;

  // SVG — route to canvas for native rendering (librsvg on Linux, D2D on Windows)
  if DetectImageType(Stream) = sitSvg then
  begin
    if Stream is TCustomMemoryStream then
      Result := FCanvas.LoadSvgFromData(
        TCustomMemoryStream(Stream).Memory,
        Stream.Size)
    else
    begin
      SvgBuf := TMemoryStream.Create;
      try
        SvgBuf.CopyFrom(Stream, 0);
        Result := FCanvas.LoadSvgFromData(SvgBuf.Memory, SvgBuf.Size);
      finally
        SvgBuf.Free;
      end;
    end;
    Exit;
  end;

  // Try canvas-native stream loading (D2D/WIC, FMX)
  Stream.Position := 0;
  Result := FCanvas.LoadImageFromStream(Stream);
  if Result <> 0 then Exit;

{$IFDEF FPC}
  // FPC: load via FPImage readers directly — bypasses platform bitmap handles
  // and preserves alpha (GTK2's TBitmap.Canvas.Draw composites against
  // black, destroying transparency)
  Img := TFPMemoryImage.Create(0, 0);
  try
    try
      Stream.Position := 0;
      Img.LoadFromStream(Stream);
    except
      Exit;
    end;

    W := Img.Width;
    H := Img.Height;
    if (W <= 0) or (H <= 0) then Exit;

    Pitch := W * 4;
    GetMem(Pixels, Pitch * H);
    try
      // Copy pixels as top-down BGRA (premultiplied)
      for Y := 0 to H - 1 do
      begin
        Dst := Pixels + Y * Pitch;
        for X := 0 to W - 1 do
        begin
          Colour := Img.Colors[X, Y];
          A := Colour.Alpha shr 8;
          if A = 0 then
          begin
            Dst^ := 0; Inc(Dst);
            Dst^ := 0; Inc(Dst);
            Dst^ := 0; Inc(Dst);
            Dst^ := 0; Inc(Dst);
          end
          else if A = 255 then
          begin
            Dst^ := Colour.Blue shr 8; Inc(Dst);
            Dst^ := Colour.Green shr 8; Inc(Dst);
            Dst^ := Colour.Red shr 8; Inc(Dst);
            Dst^ := A; Inc(Dst);
          end
          else
          begin
            // Premultiply alpha
            R := Colour.Red shr 8;
            G := Colour.Green shr 8;
            B := Colour.Blue shr 8;
            Dst^ := B * A div 255; Inc(Dst);
            Dst^ := G * A div 255; Inc(Dst);
            Dst^ := R * A div 255; Inc(Dst);
            Dst^ := A; Inc(Dst);
          end;
        end;
      end;

      Result := FCanvas.LoadImageFromPixels(W, H, Pixels, Pitch);
    finally
      FreeMem(Pixels);
    end;
  finally
    Img.Free;
  end;
{$ENDIF}
end;

function TPixieNativeContainer.LoadFromResource(
  const ResName: string): TPixieImageHandle;
{$IF DEFINED(FPC) OR DEFINED(MSWINDOWS)}
var
  Stream: TResourceStream;
begin
  try
    Stream := TResourceStream.Create(HInstance, ResName, RT_RCDATA);
    try
      Result := DecodeStreamToHandle(Stream);
    finally
      Stream.Free;
    end;
  except
    Result := 0;
  end;
end;
{$ELSE}
begin
  Result := 0;
end;
{$ENDIF}

function TPixieNativeContainer.ResolvePendingImage(
  const Key: string): TPixieImageHandle;
var
  Pending: TPixiePendingImage;
begin
  Result := 0;
  if FPendingImages.TryGetValue(Key, Pending) then
  begin
    Pending.Data.Position := 0;
    Result := DecodeStreamToHandle(Pending.Data);
    Pending.Data.Free;
    FPendingImages.Remove(Key);
    if Result <> 0 then
      FImages.Add(Key, Result);
  end;
end;

procedure TPixieNativeContainer.RegisterImage(const Name: string;
  Stream: TStream);
var
  Key: string;
  Pending: TPixiePendingImage;
begin
  Key := '#' + Name;

  // If already cached, free old handle first
  UnregisterImage(Name);

  // Copy stream data for deferred decoding
  Pending.Data := TMemoryStream.Create;
  Pending.Data.CopyFrom(Stream, 0);
  Pending.Data.Position := 0;
  FPendingImages.Add(Key, Pending);
end;

procedure TPixieNativeContainer.UnregisterImage(const Name: string);
var
  Key: string;
  Handle: TPixieImageHandle;
  Pending: TPixiePendingImage;
begin
  Key := '#' + Name;

  if FImages.TryGetValue(Key, Handle) then
  begin
    FCanvas.FreeImage(Handle);
    FImages.Remove(Key);
  end;

  if FPendingImages.TryGetValue(Key, Pending) then
  begin
    Pending.Data.Free;
    FPendingImages.Remove(Key);
  end;
end;

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

constructor TPixieNativeContainer.Create(ACanvas: TPixieCanvas);
begin
  inherited Create;
  FCanvas := ACanvas;
  FImages := TPixieImageCacheMap.Create;
  FPendingImages := TPixiePendingImageMap.Create;
  FDefaultFontSize := 16;
  FDefaultFontName := 'Segoe UI';
  FViewportWidth := 1024;
  FViewportHeight := 768;
end;

destructor TPixieNativeContainer.Destroy;
var
  Pair: TPair<string, TPixieImageHandle>;
  PendingPair: TPair<string, TPixiePendingImage>;
begin
  for Pair in FImages do
    FCanvas.FreeImage(Pair.Value);
  FImages.Free;
  for PendingPair in FPendingImages do
    PendingPair.Value.Data.Free;
  FPendingImages.Free;
  inherited Destroy;
end;

// ---------------------------------------------------------------------------
// Font management
// ---------------------------------------------------------------------------

function TPixieNativeContainer.CreateFont(
  const Descr: TPixieFontDescription; Doc: TObject;
  out Metrics: TPixieFontMetrics): PtrUInt;
begin
  Result := PtrUInt(FCanvas.CreateFont(Descr, Metrics));
end;

procedure TPixieNativeContainer.DeleteFont(HFont: PtrUInt);
begin
  FCanvas.DeleteFont(TPixieFontHandle(HFont));
end;

function TPixieNativeContainer.TextWidth(const Text: string;
  HFont: PtrUInt): pixel_t;
begin
  Result := FCanvas.MeasureText(Text, TPixieFontHandle(HFont));
end;

procedure TPixieNativeContainer.DrawText(Hdc: PtrUInt;
  const Text: string; HFont: PtrUInt; Color: TPixieWebColor;
  const Pos: TPixiePosition);
begin
  FCanvas.DrawText(Text, TPixieFontHandle(HFont), Color,
    Pos.X, Pos.Y, Pos.Width, Pos.Height);
end;

function TPixieNativeContainer.PtToPx(Pt: Single): pixel_t;
begin
  Result := FCanvas.PtToPx(Pt);
end;

function TPixieNativeContainer.GetDefaultFontSize: pixel_t;
begin
  Result := FDefaultFontSize;
end;

function TPixieNativeContainer.GetDefaultFontName: string;
begin
  Result := FDefaultFontName;
end;

// ---------------------------------------------------------------------------
// Drawing
// ---------------------------------------------------------------------------

procedure TPixieNativeContainer.DrawListMarker(Hdc: PtrUInt;
  const Marker: TPixieListMarker);
var
  Sz: Single;
begin
  Sz := Min(Marker.Pos.Width, Marker.Pos.Height);
  case Marker.MarkerType of
    lstDisc:
      FCanvas.FillEllipse(Marker.Pos.X, Marker.Pos.Y, Sz, Sz,
        Marker.Color);
    lstCircle:
      FCanvas.DrawEllipse(Marker.Pos.X, Marker.Pos.Y, Sz, Sz,
        Marker.Color, 1.0);
    lstSquare:
      FCanvas.FillRect(Marker.Pos.X, Marker.Pos.Y, Sz, Sz,
        Marker.Color);
  else
    // Numbered markers: draw as text using the marker's font
    if Marker.Font <> 0 then
      FCanvas.DrawText(IntToStr(Marker.Index) + '.',
        TPixieFontHandle(Marker.Font), Marker.Color,
        Marker.Pos.X, Marker.Pos.Y,
        Marker.Pos.Width, Marker.Pos.Height);
  end;
end;

procedure TPixieNativeContainer.LoadImage(const Src, ABaseUrl: string;
  RedrawOnReady: Boolean);
begin
  // Pre-cache the image (synchronous for local files)
  GetCachedImage(Src, ABaseUrl);
end;

procedure TPixieNativeContainer.GetImageSize(const Src, ABaseUrl: string;
  out Sz: TPixieSize);
var
  Handle: TPixieImageHandle;
  W, H: Single;
begin
  Sz.Width := 0;
  Sz.Height := 0;
  Handle := GetCachedImage(Src, ABaseUrl);
  if Handle <> 0 then
  begin
    FCanvas.GetImageSize(Handle, W, H);
    Sz.Width := W;
    Sz.Height := H;
  end;
end;

procedure TPixieNativeContainer.DrawImage(Hdc: PtrUInt;
  const Layer: TPixieBackgroundLayer; const Url, ABaseUrl: string);
var
  Handle: TPixieImageHandle;
  R: TPixieBorderRadiuses;
begin
  Handle := GetCachedImage(Url, ABaseUrl);
  if Handle = 0 then Exit;

  R := Layer.BorderRadius;
  FCanvas.SaveState;
  try
    FCanvas.SetClipRect(Layer.ClipBox, R);
    FCanvas.DrawImage(Handle,
      Layer.OriginBox.X, Layer.OriginBox.Y,
      Layer.OriginBox.Width, Layer.OriginBox.Height);
  finally
    FCanvas.RestoreState;
  end;
end;

procedure TPixieNativeContainer.DrawSolidFill(Hdc: PtrUInt;
  const Layer: TPixieBackgroundLayer; Color: TPixieWebColor);
begin
  if Color.Alpha = 0 then Exit;

  FCanvas.SaveState;
  try
    FCanvas.SetClipRect(Layer.ClipBox, Layer.BorderRadius);
    FCanvas.FillRoundedRect(
      Layer.BorderBox.X, Layer.BorderBox.Y,
      Layer.BorderBox.Width, Layer.BorderBox.Height,
      Layer.BorderRadius, Color);
  finally
    FCanvas.RestoreState;
  end;
end;

procedure TPixieNativeContainer.DrawLinearGradient(Hdc: PtrUInt;
  const Layer: TPixieBackgroundLayer;
  const Gradient: TPixieLinearGradientLayer);
begin
  FCanvas.SaveState;
  try
    FCanvas.SetClipRect(Layer.ClipBox, Layer.BorderRadius);
    FCanvas.FillLinearGradient(
      Layer.OriginBox.X, Layer.OriginBox.Y,
      Layer.OriginBox.Width, Layer.OriginBox.Height,
      Layer.BorderRadius, Gradient);
  finally
    FCanvas.RestoreState;
  end;
end;

procedure TPixieNativeContainer.DrawRadialGradient(Hdc: PtrUInt;
  const Layer: TPixieBackgroundLayer;
  const Gradient: TPixieRadialGradientLayer);
begin
  FCanvas.SaveState;
  try
    FCanvas.SetClipRect(Layer.ClipBox, Layer.BorderRadius);
    FCanvas.FillRadialGradient(
      Layer.OriginBox.X, Layer.OriginBox.Y,
      Layer.OriginBox.Width, Layer.OriginBox.Height,
      Layer.BorderRadius, Gradient);
  finally
    FCanvas.RestoreState;
  end;
end;

procedure TPixieNativeContainer.DrawConicGradient(Hdc: PtrUInt;
  const Layer: TPixieBackgroundLayer;
  const Gradient: TPixieConicGradientLayer);
begin
  FCanvas.SaveState;
  try
    FCanvas.SetClipRect(Layer.ClipBox, Layer.BorderRadius);
    FCanvas.FillConicGradient(
      Layer.OriginBox.X, Layer.OriginBox.Y,
      Layer.OriginBox.Width, Layer.OriginBox.Height,
      Layer.BorderRadius, Gradient);
  finally
    FCanvas.RestoreState;
  end;
end;

procedure TPixieNativeContainer.DrawBorders(Hdc: PtrUInt;
  const Borders: TPixieBorders; const DrawPos: TPixiePosition;
  IsRoot: Boolean);
begin
  FCanvas.DrawBorders(Borders, DrawPos, IsRoot);
end;

// ---------------------------------------------------------------------------
// Document events
// ---------------------------------------------------------------------------

procedure TPixieNativeContainer.SetCaption(const ACaption: string);
begin
  FCaption := ACaption;
  if Assigned(FOnSetCaption) then
    FOnSetCaption(Self);
end;

procedure TPixieNativeContainer.SetBaseUrl(const ABaseUrl: string);
begin
  FBaseUrl := ABaseUrl;
end;

procedure TPixieNativeContainer.Link(Doc: TObject; El: TObject);
begin
  // No-op: stylesheet link loading not yet implemented
end;

procedure TPixieNativeContainer.OnAnchorClick(const Url: string;
  El: TObject);
begin
  if Assigned(FOnAnchorClick) then
    FOnAnchorClick(Self, Url);
end;

function TPixieNativeContainer.OnElementClick(El: TObject): Boolean;
begin
  if Assigned(FOnElementClick) then
    Result := FOnElementClick(Self, El)
  else
    Result := False;
end;

procedure TPixieNativeContainer.OnMouseEvent(El: TObject;
  Event: TPixieMouseEvent);
begin
  // No-op by default
end;

procedure TPixieNativeContainer.SetCursor(const ACursor: string);
begin
  FCursor := ACursor;
end;

// ---------------------------------------------------------------------------
// Text & CSS
// ---------------------------------------------------------------------------

procedure TPixieNativeContainer.TransformText(var Text: string;
  Tt: TPixieTextTransform);
var
  I: Integer;
  PrevSpace: Boolean;
begin
  case Tt of
    ttUppercase:
      Text := UpperCase(Text);
    ttLowercase:
      Text := LowerCase(Text);
    ttCapitalize:
    begin
      PrevSpace := True;
      for I := 1 to Length(Text) do
      begin
        if PrevSpace and ({$IFDEF FPC}Text[I] in ['a'..'z']{$ELSE}CharInSet(Text[I], ['a'..'z']){$ENDIF}) then
          Text[I] := UpCase(Text[I]);
        PrevSpace := {$IFDEF FPC}Text[I] in [' ', #9, #10, #13, #12]{$ELSE}CharInSet(Text[I], [' ', #9, #10, #13, #12]){$ENDIF};
      end;
    end;
  end;
end;

procedure TPixieNativeContainer.ImportCss(var Text: string;
  const Url: string; var ABaseUrl: string);
var
  FullPath: string;
  Sl: TStringList;
  FetchStream: TMemoryStream;
  Success: Boolean;
  ParsedUrl: TPixieUrl;
begin
  FullPath := ResolveUrl(Url, ABaseUrl);

  // HTTP URL — fetch via event callback
  if IsHttpUrl(FullPath) and Assigned(FOnFetchUrl) then
  begin
    FetchStream := TMemoryStream.Create;
    try
      Success := False;
      FOnFetchUrl(Self, FullPath, FetchStream, Success);
      if Success and (FetchStream.Size > 0) then
      begin
        FetchStream.Position := 0;
        Sl := TStringList.Create;
        try
          Sl.LoadFromStream(FetchStream);
          Text := Sl.Text;
        finally
          Sl.Free;
        end;
        ParsedUrl := TPixieUrl.Create(FullPath);
        ABaseUrl := TPixieUrl.Create(ParsedUrl.Scheme, ParsedUrl.Authority,
          PixieUrlPathDirectoryName(ParsedUrl.Path), '', '').Str;
      end
      else
        Text := '';
    finally
      FetchStream.Free;
    end;
    Exit;
  end;

  // Local file
  if FileExists(FullPath) then
  begin
    Sl := TStringList.Create;
    try
      Sl.LoadFromFile(FullPath);
      Text := Sl.Text;
      ABaseUrl := ExtractFilePath(FullPath);
    finally
      Sl.Free;
    end;
  end
  else
    Text := '';
end;

// ---------------------------------------------------------------------------
// Selection highlight
// ---------------------------------------------------------------------------

procedure TPixieNativeContainer.DrawHighlight(Hdc: PtrUInt;
  const Pos: TPixiePosition; Color: TPixieWebColor);
begin
  FCanvas.FillRect(Pos.X, Pos.Y, Pos.Width, Pos.Height, Color);
end;

// ---------------------------------------------------------------------------
// Clipping
// ---------------------------------------------------------------------------

procedure TPixieNativeContainer.PushOpacity(AOpacity: Single);
begin
  FCanvas.PushOpacity(AOpacity);
end;

procedure TPixieNativeContainer.PopOpacity;
begin
  FCanvas.PopOpacity;
end;

procedure TPixieNativeContainer.SetClip(const Pos: TPixiePosition;
  const BdrRadius: TPixieBorderRadiuses);
begin
  FCanvas.SaveState;
  FCanvas.SetClipRect(Pos, BdrRadius);
end;

procedure TPixieNativeContainer.DelClip;
begin
  FCanvas.RestoreState;
end;

// ---------------------------------------------------------------------------
// Viewport & media
// ---------------------------------------------------------------------------

procedure TPixieNativeContainer.GetViewport(
  out Viewport: TPixiePosition);
begin
  Viewport.X := 0;
  Viewport.Y := 0;
  Viewport.Width := FViewportWidth;
  Viewport.Height := FViewportHeight;
end;

procedure TPixieNativeContainer.GetMediaFeatures(
  out Media: TPixieMediaFeatures);
begin
  Media.MediaType := mtScreen;
  Media.Width := FViewportWidth;
  Media.Height := FViewportHeight;
  Media.DeviceWidth := FViewportWidth;
  Media.DeviceHeight := FViewportHeight;
  Media.Color := 8;
  Media.ColorIndex := 0;
  Media.Monochrome := 0;
  Media.Resolution := 96;
end;

procedure TPixieNativeContainer.GetLanguage(
  out Language, Culture: string);
begin
  Language := 'en';
  Culture := '';
end;

// ---------------------------------------------------------------------------
// Element creation
// ---------------------------------------------------------------------------

function TPixieNativeContainer.CreateElement(const TagName: string;
  Attrs: TPixieStringMap; Doc: TObject): TObject;
begin
  // Return nil — let the document create default elements
  Result := nil;
end;

end.
