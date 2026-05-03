unit Pixie.MarkdownView.FMX;

// TPixieMarkdownView — Delphi FMX visual component that renders
// Markdown content. Converts Markdown to HTML via Pixie.Markdown, then
// renders through the existing HTML engine.

interface

uses
  System.Classes, System.SysUtils,
  Pixie.HtmlView.FMX.Base, Pixie.Markdown;

type
  { TPixieMarkdownView }

  TPixieMarkdownView = class(TPixieHtmlViewBase)
  private
    FMarkdown: TStringList;
    FUseDefaultStyles: Boolean;
    FBaseUrl: string;
    function GetMarkdown: TStrings;
    procedure SetMarkdown(Value: TStrings);
    procedure SetUseDefaultStyles(Value: Boolean);
    procedure DoMarkdownChange(Sender: TObject);
    procedure RebuildHtml;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    procedure LoadMarkdownFromString(const AMd: string;
      const ABaseUrl: string = '');
    procedure LoadMarkdownFromFile(const AFileName: string);
    procedure LoadMarkdownFromStream(AStream: TStream;
      const ABaseUrl: string = '');
  published
    property Markdown: TStrings read GetMarkdown write SetMarkdown;
    property UseDefaultStyles: Boolean read FUseDefaultStyles
      write SetUseDefaultStyles default True;
  end;

implementation

constructor TPixieMarkdownView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMarkdown := TStringList.Create;
  FMarkdown.OnChange := DoMarkdownChange;
  FUseDefaultStyles := True;
end;

destructor TPixieMarkdownView.Destroy;
begin
  FreeAndNil(FMarkdown);
  inherited Destroy;
end;

function TPixieMarkdownView.GetMarkdown: TStrings;
begin
  Result := FMarkdown;
end;

procedure TPixieMarkdownView.SetMarkdown(Value: TStrings);
begin
  FMarkdown.Assign(Value);
end;

procedure TPixieMarkdownView.SetUseDefaultStyles(Value: Boolean);
begin
  if FUseDefaultStyles = Value then Exit;
  FUseDefaultStyles := Value;
  RebuildHtml;
end;

procedure TPixieMarkdownView.DoMarkdownChange(Sender: TObject);
begin
  RebuildHtml;
end;

procedure TPixieMarkdownView.RebuildHtml;
begin
  LoadMarkdownFromString(FMarkdown.Text, FBaseUrl);
end;

procedure TPixieMarkdownView.LoadMarkdownFromString(const AMd: string;
  const ABaseUrl: string);
var
  Html: string;
begin
  FBaseUrl := ABaseUrl;
  Html := PixieMarkdownToHtml(AMd);
  CoreLoadFromString(Html, ABaseUrl);
end;

procedure TPixieMarkdownView.LoadMarkdownFromFile(const AFileName: string);
var
  Stream: TFileStream;
  Bytes: TBytes;
  Md: string;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Bytes, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Bytes[0], Stream.Size);
  finally
    Stream.Free;
  end;
  Md := TEncoding.UTF8.GetString(Bytes);
  if (Length(Md) > 0) and (Md[1] = #$FEFF) then
    Delete(Md, 1, 1);
  LoadMarkdownFromString(Md, ExtractFilePath(AFileName));
end;

procedure TPixieMarkdownView.LoadMarkdownFromStream(AStream: TStream;
  const ABaseUrl: string);
var
  Bytes: TBytes;
  Md: string;
  N: Int64;
begin
  N := AStream.Size - AStream.Position;
  SetLength(Bytes, N);
  if N > 0 then
    AStream.ReadBuffer(Bytes[0], N);
  Md := TEncoding.UTF8.GetString(Bytes);
  if (Length(Md) > 0) and (Md[1] = #$FEFF) then
    Delete(Md, 1, 1);
  LoadMarkdownFromString(Md, ABaseUrl);
end;

end.
