// Shared implementation for TPixieMarkdownView across Lazarus, VCL, and
// FMX. Included from each platform's .pas file in the implementation
// section. Declarations live in Pixie.MarkdownView.inc.

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
  if FUseDefaultStyles then
    Html := '<style>' + PixieDefaultMarkdownCss + '</style>' + Html;
  CoreLoadFromString(Html, ABaseUrl);
end;

procedure TPixieMarkdownView.LoadMarkdownFromFile(const AFileName: string);
begin
  LoadMarkdownFromString(PixieMarkdownReadFile(AFileName),
    ExtractFilePath(AFileName));
end;

procedure TPixieMarkdownView.LoadMarkdownFromStream(AStream: TStream;
  const ABaseUrl: string);
begin
  LoadMarkdownFromString(PixieMarkdownReadStream(AStream), ABaseUrl);
end;
