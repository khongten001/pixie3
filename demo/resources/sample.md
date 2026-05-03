# Pixie Markdown Demo

A quick tour of what `TPixieMarkdownView` renders, all the way through
the same HTML/CSS engine that powers `TPixieHtmlView`.

## Inline formatting

Plain text mixes with **strong**, *emphasis*, ***both at once***,
~~strikethrough~~, `inline code`, and a [hyperlink](https://example.com).
Soft breaks
collapse to spaces; two trailing spaces or a backslash\
force a hard break.

A bare URL like https://example.com is auto-linked too, and so is
<user@example.com>.

## Lists

Unordered — tight:

- Apples
- Pears
- Oranges, kumquats, and other citrus

Ordered — loose, with paragraphs:

1.  First step.

    A continuation paragraph in the same item.

2.  Second step, picking up where the first left off.

3.  Third step.

Nested:

- Outer
  - Inner one
  - Inner two
    - Deeper still
- Outer again

Task list:

- [x] Block-level rendering
- [x] Inline rendering
- [x] CommonMark + GFM extensions
- [ ] World peace

## Code

Inline `let x = 42;` and a fenced block:

```pascal
function PixieGreet(const Name: string): string;
begin
  Result := 'Hello, ' + Name + '!';
end;
```

## Tables

GFM tables with column alignment:

| Feature        | CommonMark | GFM      | Pixie    |
|:---------------|:----------:|:--------:|---------:|
| Headings       | yes        | yes      | yes      |
| Tables         | no         | yes      | yes      |
| Strikethrough  | no         | yes      | yes      |
| Task lists     | no         | yes      | yes      |
| Math           | no         | partial  | not yet  |

## Blockquotes

> Markdown is a plain text format for writing structured documents,
> based on conventions for indicating formatting in email and usenet
> posts.
>
> > Nested blockquotes also work — useful for replies-to-replies.

## Images

![Pixie logo](pixie-logo.svg)

## Horizontal rules

---

That's the tour. Click "Load .md file" above to render your own.
