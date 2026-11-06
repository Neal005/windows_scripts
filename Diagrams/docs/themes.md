# Themes

Colour is chosen by the theme, never by the JSON (`"theme": "mono"|"accent"`, or `--theme`). Every style is
written explicitly (font colour, stroke, fill, label background, `fontFamily=Arial`, size, arrows with fill,
swimlane `startSize=30`, dashing), so draw.io defaults never leak in. Pages carry `background="#FFFFFF"` and
`adaptiveColors="none"` so dark mode does not invert the colours (effect UNVERIFIED).

## mono (default)

Text `#000000`, outlines `#404040`, connectors `#000000`, page `#FFFFFF`. Three grays carry meaning:
`#FFFFFF`, `#E0E0E0`, `#BDBDBD` (lightness steps of about 10 or more, so they stay distinguishable in print).
`#F2F2F2` is decoration only (container fill). Every colour has R=G=B.

## accent

mono plus exactly one colour, `#1F4E79`, used for container outlines and for the outline of `new` tables;
every such element also gets `strokeWidth=2`, so the meaning survives black-and-white printing.

## Meaning without colour

| What | How it differs |
|------|----------------|
| table variant | title prefix `[NEW] ` / `[EXTEND] ` / `[REUSE] ` (none for `plain`), plus gray #FFFFFF / #E0E0E0 / #BDBDBD |
| vertex role | `box` plain; `container` bold title, top-left; `text` and `title` no frame (title bold 16); `note` italic on #E0E0E0 |
| row role | `pk` bold, `fk` italic, `note` underlined, `separator` a line shape |
| edge role | `line` solid, `dependency` dashed (`6 4`), `return` dotted (`2 4`); `line:` overrides |

Table borders are never dashed (dashes are reserved for dependency/optional meaning).

## Contrast

Text on every fill used is at least 4.5:1 (black on the darkest gray is above 10:1).

## Limits

`style_raw` can override a theme (for example a non-gray colour in `mono`, or a different `strokeWidth` on an
accent element); the tool only warns. Table rows are laid out by draw.io's stack layout, which ignores child
stroke widths (`borderCollapse`), so row styling cannot shift the rows.
