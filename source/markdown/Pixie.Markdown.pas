unit Pixie.Markdown;

// Public Markdown -> HTML conversion API. Phase 1 stub: HTML-escapes the
// input and wraps it in <pre>. Real CommonMark/GFM parsing arrives in
// Phase 3 (block) and Phase 4 (inline).

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Pixie.Markdown.Types;

type
  // Re-export so callers only need Pixie.Markdown.
  TPixieMdOption = Pixie.Markdown.Types.TPixieMdOption;
  TPixieMdOptions = Pixie.Markdown.Types.TPixieMdOptions;

function PixieMarkdownToHtml(const Md: string;
  Options: TPixieMdOptions = DefaultPixieMdOptions): string;

function PixieMarkdownToHtmlDocument(const Md: string;
  const Title: string = '';
  Options: TPixieMdOptions = DefaultPixieMdOptions): string;

implementation

uses
  SysUtils,
  Pixie.Markdown.Parser, Pixie.Markdown.InlineParser,
  Pixie.Markdown.HtmlWriter;

function HtmlEscape(const S: string): string;
var
  I, Len: Integer;
  C: Char;
  SB: string;
begin
  Len := Length(S);
  SB := '';
  for I := 1 to Len do
  begin
    C := S[I];
    case C of
      '&': SB := SB + '&amp;';
      '<': SB := SB + '&lt;';
      '>': SB := SB + '&gt;';
      '"': SB := SB + '&quot;';
    else
      SB := SB + C;
    end;
  end;
  Result := SB;
end;

function PixieMarkdownToHtml(const Md: string;
  Options: TPixieMdOptions): string;
var
  Doc: TPixieMdNode;
begin
  Doc := TPixieMdParser.ParseBlocks(Md, nil, Options);
  try
    TPixieMdInlineParser.ParseInlinesIntoBlocks(Doc, Options);
    Result := TPixieMdHtmlWriter.Write(Doc, Options);
  finally
    Doc.Free;
  end;
end;

function PixieMarkdownToHtmlDocument(const Md: string;
  const Title: string;
  Options: TPixieMdOptions): string;
var
  T: string;
begin
  if Title <> '' then
    T := '<title>' + HtmlEscape(Title) + '</title>'
  else
    T := '';
  Result :=
    '<!DOCTYPE html><html><head>' + T + '</head><body>' +
    PixieMarkdownToHtml(Md, Options) +
    '</body></html>';
end;

end.
