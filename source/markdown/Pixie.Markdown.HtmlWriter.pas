unit Pixie.Markdown.HtmlWriter;

// Walks an AST produced by the Markdown parser and emits HTML to a
// string buffer. Handles HTML escaping, GitHub-flavoured heading slugs
// with dedup, tight vs loose list <p> wrapping, task-list checkboxes,
// table alignment styles, and raw-HTML passthrough.

{$IFDEF FPC}{$MODE DELPHI}{$ENDIF}

interface

uses
  Classes, SysUtils, Generics.Collections,
  Pixie.Markdown.Types;

type
  TPixieMdSlugMap = TDictionary<string, Integer>;

  TPixieMdHtmlWriter = class
  public
    class function Write(Doc: TPixieMdNode;
      Options: TPixieMdOptions = DefaultPixieMdOptions): string;
  end;

// Helpers exposed for parser/tests.
function PixieMdHtmlEscape(const S: string): string;
function PixieMdHtmlEscapeAttr(const S: string): string;
function PixieMdSlug(const S: string): string;
function PixieMdInlineText(Node: TPixieMdNode): string;

implementation

// ---------------------------------------------------------------------------
// Escaping helpers
// ---------------------------------------------------------------------------

function PixieMdHtmlEscape(const S: string): string;
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
    else
      SB := SB + C;
    end;
  end;
  Result := SB;
end;

function PixieMdHtmlEscapeAttr(const S: string): string;
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

// GitHub-compatible slug: lowercase, runs of whitespace -> '-', strip
// everything except [a-z0-9_-]. Hyphen runs are NOT collapsed (matches
// GitHub's behaviour: "foo--bar" stays "foo--bar").
function PixieMdSlug(const S: string): string;
var
  I, Len: Integer;
  C: Char;
  SB: string;
  PrevWasSpace: Boolean;
begin
  Len := Length(S);
  SB := '';
  PrevWasSpace := False;
  for I := 1 to Len do
  begin
    C := S[I];
    case C of
      'A'..'Z':
        begin
          SB := SB + Chr(Ord(C) + 32);
          PrevWasSpace := False;
        end;
      'a'..'z', '0'..'9', '_', '-':
        begin
          SB := SB + C;
          PrevWasSpace := False;
        end;
      ' ', #9, #10, #13:
        begin
          if not PrevWasSpace then
            SB := SB + '-';
          PrevWasSpace := True;
        end;
    end;
  end;
  Result := SB;
end;

// Walks an inline subtree and returns the concatenated plain-text
// content. Used for slug generation and image alt text fallback.
function PixieMdInlineText(Node: TPixieMdNode): string;
var
  I: Integer;
  Buf: string;
begin
  if Node = nil then Exit('');
  case Node.Kind of
    mnText, mnCodeSpan, mnRawHtml: Result := Node.Literal;
    mnLineBreak, mnSoftBreak: Result := ' ';
  else
    Buf := '';
    if Node.HasChildren then
      for I := 0 to Node.ChildCount - 1 do
        Buf := Buf + PixieMdInlineText(Node.Children[I]);
    Result := Buf;
  end;
end;

// ---------------------------------------------------------------------------
// Writer state
// ---------------------------------------------------------------------------

type
  TWriterCtx = record
    Buf: string;
    Slugs: TPixieMdSlugMap;
    Options: TPixieMdOptions;
  end;
  PWriterCtx = ^TWriterCtx;

procedure WriteNode(Ctx: PWriterCtx; Node: TPixieMdNode); forward;

procedure WriteChildren(Ctx: PWriterCtx; Node: TPixieMdNode);
var
  I: Integer;
begin
  if not Node.HasChildren then Exit;
  for I := 0 to Node.ChildCount - 1 do
    WriteNode(Ctx, Node.Children[I]);
end;

// Walks list-item children. For tight lists, peels paragraph wrappers
// so list item text is rendered as bare children.
procedure WriteListItemContent(Ctx: PWriterCtx; Item: TPixieMdNode;
  Tight: Boolean);
var
  I: Integer;
  Child: TPixieMdNode;
  J: Integer;
begin
  if not Item.HasChildren then Exit;
  for I := 0 to Item.ChildCount - 1 do
  begin
    Child := Item.Children[I];
    if Tight and (Child.Kind = mnParagraph) then
    begin
      // Skip <p> wrapper: emit paragraph children inline.
      if Child.HasChildren then
        for J := 0 to Child.ChildCount - 1 do
          WriteNode(Ctx, Child.Children[J]);
    end
    else
      WriteNode(Ctx, Child);
  end;
end;

function ResolveSlug(Ctx: PWriterCtx; const Base: string): string;
var
  Count: Integer;
  Candidate: string;
begin
  Candidate := Base;
  if Candidate = '' then Exit('');
  if not Ctx^.Slugs.TryGetValue(Candidate, Count) then
  begin
    Ctx^.Slugs.Add(Candidate, 0);
    Result := Candidate;
    Exit;
  end;
  // Already used: append -N counter.
  repeat
    Inc(Count);
    Candidate := Base + '-' + IntToStr(Count);
  until not Ctx^.Slugs.ContainsKey(Candidate);
  Ctx^.Slugs[Base] := Count;
  Ctx^.Slugs.Add(Candidate, 0);
  Result := Candidate;
end;

// ---------------------------------------------------------------------------
// Per-node emitters
// ---------------------------------------------------------------------------

procedure WriteHeading(Ctx: PWriterCtx; Node: TPixieMdNode);
var
  Tag: string;
  Id: string;
  Level: Integer;
begin
  Level := Node.HeadingLevel;
  if Level < 1 then Level := 1;
  if Level > 6 then Level := 6;
  Tag := 'h' + IntToStr(Level);

  Id := Node.HeadingId;
  if (Id = '') and (moAutoHeadingIds in Ctx^.Options) then
    Id := ResolveSlug(Ctx, PixieMdSlug(PixieMdInlineText(Node)));

  if Id <> '' then
    Ctx^.Buf := Ctx^.Buf + '<' + Tag + ' id="' + PixieMdHtmlEscapeAttr(Id) + '">'
  else
    Ctx^.Buf := Ctx^.Buf + '<' + Tag + '>';
  WriteChildren(Ctx, Node);
  Ctx^.Buf := Ctx^.Buf + '</' + Tag + '>' + sLineBreak;
end;

procedure WriteParagraph(Ctx: PWriterCtx; Node: TPixieMdNode);
begin
  Ctx^.Buf := Ctx^.Buf + '<p>';
  WriteChildren(Ctx, Node);
  Ctx^.Buf := Ctx^.Buf + '</p>' + sLineBreak;
end;

procedure WriteBlockQuote(Ctx: PWriterCtx; Node: TPixieMdNode);
begin
  Ctx^.Buf := Ctx^.Buf + '<blockquote>' + sLineBreak;
  WriteChildren(Ctx, Node);
  Ctx^.Buf := Ctx^.Buf + '</blockquote>' + sLineBreak;
end;

procedure WriteList(Ctx: PWriterCtx; Node: TPixieMdNode);
var
  Tag: string;
  I: Integer;
  Item: TPixieMdNode;
begin
  if Node.ListOrdered then
  begin
    Tag := 'ol';
    if Node.ListStart <> 1 then
      Ctx^.Buf := Ctx^.Buf + '<ol start="' + IntToStr(Node.ListStart) + '">'
    else
      Ctx^.Buf := Ctx^.Buf + '<ol>';
  end
  else
  begin
    Tag := 'ul';
    Ctx^.Buf := Ctx^.Buf + '<ul>';
  end;
  Ctx^.Buf := Ctx^.Buf + sLineBreak;

  if Node.HasChildren then
    for I := 0 to Node.ChildCount - 1 do
    begin
      Item := Node.Children[I];
      if Item.Kind <> mnListItem then
      begin
        WriteNode(Ctx, Item);
        Continue;
      end;
      if Item.IsTaskItem then
      begin
        Ctx^.Buf := Ctx^.Buf + '<li class="task-list-item">';
        if Item.TaskChecked then
          Ctx^.Buf := Ctx^.Buf +
            '<input type="checkbox" disabled checked> '
        else
          Ctx^.Buf := Ctx^.Buf +
            '<input type="checkbox" disabled> ';
      end
      else
        Ctx^.Buf := Ctx^.Buf + '<li>';
      WriteListItemContent(Ctx, Item, Node.ListTight);
      Ctx^.Buf := Ctx^.Buf + '</li>' + sLineBreak;
    end;

  Ctx^.Buf := Ctx^.Buf + '</' + Tag + '>' + sLineBreak;
end;

procedure WriteCodeBlock(Ctx: PWriterCtx; Node: TPixieMdNode);
var
  ClsAttr: string;
begin
  if Node.CodeLang <> '' then
    ClsAttr := ' class="language-' +
      PixieMdHtmlEscapeAttr(Node.CodeLang) + '"'
  else
    ClsAttr := '';
  Ctx^.Buf := Ctx^.Buf + '<pre><code' + ClsAttr + '>' +
    PixieMdHtmlEscape(Node.Literal) + '</code></pre>' + sLineBreak;
end;

procedure WriteTable(Ctx: PWriterCtx; Node: TPixieMdNode);
var
  I, J: Integer;
  Row, Cell: TPixieMdNode;
  AlignAttr: string;
  HasHeader, HasBody, InHeaderSection, InBodySection: Boolean;
  CellTag: string;
begin
  HasHeader := False;
  HasBody := False;
  if Node.HasChildren then
    for I := 0 to Node.ChildCount - 1 do
    begin
      Row := Node.Children[I];
      if Row.Kind <> mnTableRow then Continue;
      if Row.IsHeaderRow then HasHeader := True
      else HasBody := True;
    end;

  Ctx^.Buf := Ctx^.Buf + '<table>' + sLineBreak;
  InHeaderSection := False;
  InBodySection := False;

  if Node.HasChildren then
    for I := 0 to Node.ChildCount - 1 do
    begin
      Row := Node.Children[I];
      if Row.Kind <> mnTableRow then Continue;

      if Row.IsHeaderRow then
      begin
        if not InHeaderSection then
        begin
          Ctx^.Buf := Ctx^.Buf + '<thead>' + sLineBreak;
          InHeaderSection := True;
        end;
        CellTag := 'th';
      end
      else
      begin
        if InHeaderSection then
        begin
          Ctx^.Buf := Ctx^.Buf + '</thead>' + sLineBreak;
          InHeaderSection := False;
        end;
        if not InBodySection then
        begin
          Ctx^.Buf := Ctx^.Buf + '<tbody>' + sLineBreak;
          InBodySection := True;
        end;
        CellTag := 'td';
      end;

      Ctx^.Buf := Ctx^.Buf + '<tr>';
      if Row.HasChildren then
        for J := 0 to Row.ChildCount - 1 do
        begin
          Cell := Row.Children[J];
          if Cell.Kind <> mnTableCell then Continue;
          case Cell.CellAlignment of
            maLeft:   AlignAttr := ' style="text-align:left"';
            maRight:  AlignAttr := ' style="text-align:right"';
            maCenter: AlignAttr := ' style="text-align:center"';
          else
            AlignAttr := '';
          end;
          Ctx^.Buf := Ctx^.Buf + '<' + CellTag + AlignAttr + '>';
          WriteChildren(Ctx, Cell);
          Ctx^.Buf := Ctx^.Buf + '</' + CellTag + '>';
        end;
      Ctx^.Buf := Ctx^.Buf + '</tr>' + sLineBreak;
    end;

  if InHeaderSection then
    Ctx^.Buf := Ctx^.Buf + '</thead>' + sLineBreak;
  if InBodySection then
    Ctx^.Buf := Ctx^.Buf + '</tbody>' + sLineBreak;
  if not (HasHeader or HasBody) then
    ; // empty table
  Ctx^.Buf := Ctx^.Buf + '</table>' + sLineBreak;
end;

procedure WriteLink(Ctx: PWriterCtx; Node: TPixieMdNode);
var
  Tail: string;
begin
  Tail := '';
  if Node.LinkTitle <> '' then
    Tail := ' title="' + PixieMdHtmlEscapeAttr(Node.LinkTitle) + '"';
  Ctx^.Buf := Ctx^.Buf + '<a href="' +
    PixieMdHtmlEscapeAttr(Node.LinkUrl) + '"' + Tail + '>';
  WriteChildren(Ctx, Node);
  Ctx^.Buf := Ctx^.Buf + '</a>';
end;

procedure WriteImage(Ctx: PWriterCtx; Node: TPixieMdNode);
var
  Alt: string;
  Tail: string;
begin
  // Prefer ImageAlt; fall back to inline-text rendering of children.
  Alt := Node.ImageAlt;
  if (Alt = '') and Node.HasChildren then
    Alt := PixieMdInlineText(Node);
  Tail := '';
  if Node.LinkTitle <> '' then
    Tail := ' title="' + PixieMdHtmlEscapeAttr(Node.LinkTitle) + '"';
  Ctx^.Buf := Ctx^.Buf + '<img src="' +
    PixieMdHtmlEscapeAttr(Node.LinkUrl) + '" alt="' +
    PixieMdHtmlEscapeAttr(Alt) + '"' + Tail + '>';
end;

procedure WriteNode(Ctx: PWriterCtx; Node: TPixieMdNode);
begin
  case Node.Kind of
    mnDocument:
      WriteChildren(Ctx, Node);
    mnHeading:
      WriteHeading(Ctx, Node);
    mnParagraph:
      WriteParagraph(Ctx, Node);
    mnBlockQuote:
      WriteBlockQuote(Ctx, Node);
    mnList:
      WriteList(Ctx, Node);
    mnListItem:
      // Normally consumed by WriteList; if encountered standalone, emit
      // as a bare <li> with its content.
      begin
        Ctx^.Buf := Ctx^.Buf + '<li>';
        WriteChildren(Ctx, Node);
        Ctx^.Buf := Ctx^.Buf + '</li>' + sLineBreak;
      end;
    mnCodeBlock:
      WriteCodeBlock(Ctx, Node);
    mnHtmlBlock:
      Ctx^.Buf := Ctx^.Buf + Node.Literal + sLineBreak;
    mnThematicBreak:
      Ctx^.Buf := Ctx^.Buf + '<hr>' + sLineBreak;
    mnTable:
      WriteTable(Ctx, Node);
    mnTableRow, mnTableCell:
      // Only meaningful inside mnTable; emit children as fallback.
      WriteChildren(Ctx, Node);
    mnText:
      Ctx^.Buf := Ctx^.Buf + PixieMdHtmlEscape(Node.Literal);
    mnEmph:
      begin
        Ctx^.Buf := Ctx^.Buf + '<em>';
        WriteChildren(Ctx, Node);
        Ctx^.Buf := Ctx^.Buf + '</em>';
      end;
    mnStrong:
      begin
        Ctx^.Buf := Ctx^.Buf + '<strong>';
        WriteChildren(Ctx, Node);
        Ctx^.Buf := Ctx^.Buf + '</strong>';
      end;
    mnStrikethrough:
      begin
        Ctx^.Buf := Ctx^.Buf + '<del>';
        WriteChildren(Ctx, Node);
        Ctx^.Buf := Ctx^.Buf + '</del>';
      end;
    mnCodeSpan:
      Ctx^.Buf := Ctx^.Buf + '<code>' +
        PixieMdHtmlEscape(Node.Literal) + '</code>';
    mnLink:
      WriteLink(Ctx, Node);
    mnImage:
      WriteImage(Ctx, Node);
    mnLineBreak:
      Ctx^.Buf := Ctx^.Buf + '<br>' + sLineBreak;
    mnSoftBreak:
      Ctx^.Buf := Ctx^.Buf + sLineBreak;
    mnRawHtml:
      Ctx^.Buf := Ctx^.Buf + Node.Literal;
  end;
end;

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

class function TPixieMdHtmlWriter.Write(Doc: TPixieMdNode;
  Options: TPixieMdOptions): string;
var
  Ctx: TWriterCtx;
begin
  if Doc = nil then Exit('');
  Ctx.Buf := '';
  Ctx.Options := Options;
  Ctx.Slugs := TPixieMdSlugMap.Create;
  try
    WriteNode(@Ctx, Doc);
  finally
    Ctx.Slugs.Free;
  end;
  Result := Ctx.Buf;
end;

end.
