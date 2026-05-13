unit Pixie.AnimatedImage;

// Frame-store types for animated raster images (GIF in Phase 1, APNG in
// Phase 2). One TPixieAnimatedImage is the decoded result for a single
// source URL: a list of pre-composited frames plus playback metadata.
//
// Ownership of the platform image handles is shared: the originating
// canvas owns the underlying bitmaps; the holder of this object
// (TPixieNativeContainer.FAnimations) must call Canvas.FreeImage on
// every frame handle and then ClearFrames before Free. The destructor
// asserts the list has been cleared to catch misuse.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  SysUtils, Classes, Generics.Collections,
  Pixie.Types;

type
  TPixieAnimFrame = record
    Handle: PtrUInt;
    DelayMs: Integer;
  end;

  TPixieAnimFrameList = TList<TPixieAnimFrame>;

  { TPixieAnimatedImage }

  TPixieAnimatedImage = class
  private
    FFrames: TPixieAnimFrameList;
    FLoops: Integer;
    FWidth: Integer;
    FHeight: Integer;
    function GetFrameCount: Integer;
    function GetFrame(Index: Integer): TPixieAnimFrame;
    function GetTotalDurationMs: Integer;
  public
    constructor Create;
    destructor Destroy; override;

    procedure AddFrame(Handle: PtrUInt; DelayMs: Integer);
    procedure ClearFrames;

    property FrameCount: Integer read GetFrameCount;
    property Frames[Index: Integer]: TPixieAnimFrame read GetFrame;
    property Loops: Integer read FLoops write FLoops;
    property Width: Integer read FWidth write FWidth;
    property Height: Integer read FHeight write FHeight;
    property TotalDurationMs: Integer read GetTotalDurationMs;
  end;

  TPixieAnimatedImageMap = TObjectDictionary<string, TPixieAnimatedImage>;

  { TPixieAnimationCursor }
  // Per-element playback state. Owns no native handles; just iterates the
  // referenced TPixieAnimatedImage's frame list against wall-clock deadlines.
  // The view core owns the cursor list and walks it from a 30 Hz timer.

  TPixieAnimationCursor = class
  private
    FImage: TPixieAnimatedImage;
    FElement: TObject;
    FCurrentFrame: Integer;
    FNextDeadlineMs: UInt64;
    FCompletedLoops: Integer;
    FFinished: Boolean;
  public
    constructor Create(AImage: TPixieAnimatedImage; AElement: TObject;
      NowMs: UInt64);

    // Returns True if the current frame index changed this tick.
    function Tick(NowMs: UInt64): Boolean;

    function CurrentFrameHandle: PtrUInt;

    property Image: TPixieAnimatedImage read FImage;
    property Element: TObject read FElement;
    property CurrentFrame: Integer read FCurrentFrame;
    property Finished: Boolean read FFinished;
  end;

  TPixieAnimationCursorList = TObjectList<TPixieAnimationCursor>;

implementation

{ TPixieAnimatedImage }

constructor TPixieAnimatedImage.Create;
begin
  inherited Create;
  FFrames := TPixieAnimFrameList.Create;
end;

destructor TPixieAnimatedImage.Destroy;
begin
  Assert(FFrames.Count = 0,
    'TPixieAnimatedImage destroyed with live frame handles — '
    + 'holder must call ClearFrames after FreeImage on each.');
  FFrames.Free;
  inherited Destroy;
end;

procedure TPixieAnimatedImage.AddFrame(Handle: PtrUInt; DelayMs: Integer);
var
  Frame: TPixieAnimFrame;
begin
  if DelayMs < 20 then
    DelayMs := 20;
  Frame.Handle := Handle;
  Frame.DelayMs := DelayMs;
  FFrames.Add(Frame);
end;

procedure TPixieAnimatedImage.ClearFrames;
begin
  FFrames.Clear;
end;

function TPixieAnimatedImage.GetFrameCount: Integer;
begin
  Result := FFrames.Count;
end;

function TPixieAnimatedImage.GetFrame(Index: Integer): TPixieAnimFrame;
begin
  Result := FFrames[Index];
end;

function TPixieAnimatedImage.GetTotalDurationMs: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to FFrames.Count - 1 do
    Inc(Result, FFrames[I].DelayMs);
end;

{ TPixieAnimationCursor }

constructor TPixieAnimationCursor.Create(AImage: TPixieAnimatedImage;
  AElement: TObject; NowMs: UInt64);
begin
  inherited Create;
  FImage := AImage;
  FElement := AElement;
  if (FImage <> nil) and (FImage.FrameCount > 0) then
    FNextDeadlineMs := NowMs + UInt64(FImage.Frames[0].DelayMs);
end;

function TPixieAnimationCursor.Tick(NowMs: UInt64): Boolean;
var
  Frame: TPixieAnimFrame;
begin
  Result := False;
  if FFinished or (FImage = nil) or (FImage.FrameCount <= 1) then Exit;
  if NowMs < FNextDeadlineMs then Exit;

  if FCurrentFrame >= FImage.FrameCount - 1 then
  begin
    Inc(FCompletedLoops);
    // Image.Loops: 0 = infinite; N>0 = play N times then freeze on last frame
    if (FImage.Loops > 0) and (FCompletedLoops >= FImage.Loops) then
    begin
      FFinished := True;
      Exit;
    end;
    FCurrentFrame := 0;
  end
  else
    Inc(FCurrentFrame);

  Frame := FImage.Frames[FCurrentFrame];
  FNextDeadlineMs := NowMs + UInt64(Frame.DelayMs);
  Result := True;
end;

function TPixieAnimationCursor.CurrentFrameHandle: PtrUInt;
begin
  Result := 0;
  if (FImage = nil) or (FImage.FrameCount = 0) then Exit;
  if (FCurrentFrame < 0) or (FCurrentFrame >= FImage.FrameCount) then Exit;
  Result := FImage.Frames[FCurrentFrame].Handle;
end;

end.
