# Composition format

Screenshotty stores a style as JSON. The same format can be loaded with
`Screenshotty render --settings style.json` and is intended to be shared by a future Windows version.

## Units

Lengths are in **layout units**. One unit is 1/1000 of the screenshot's longest side, after trimming.
A `padding` of 90 on a 2000 px wide screenshot is 180 px.

## Settings

```json
{
  "background": { "type": "linearGradient", "angle": 135,
                  "stops": [ { "color": "#667EEA", "location": 0 }, { "color": "#764BA2", "location": 1 } ] },
  "aspectRatio": "16:9",
  "padding": 90,
  "cornerRadius": 12,
  "shadow": "medium",
  "windowChrome": "none",
  "frame": "none",
  "autoTrim": true,
  "innerPadding": 40
}
```

Every key is optional. Missing keys use the defaults shown above.

| Key | Values |
| --- | --- |
| `aspectRatio` | `auto`, `1:1`, `4:5`, `4:3`, `3:2`, `16:9`, `1.91:1`, `9:16` |
| `padding` | 0 to 300 units |
| `cornerRadius` | 0 to 60 units, clamped to half the shortest side. Capped at 24 while `windowChrome` is not `none`. |
| `shadow` | `none`, `soft`, `medium`, `strong` |
| `windowChrome` | `none`, `light`, `dark`, `browser-light`, `browser-dark` |
| `browserURL` | Text shown in the browser address bar, with a padlock. Empty draws an empty bar. |
| `device` | `none`, `macbook`, `iphone`. A device replaces the corner radius and `frame`. |
| `exportWidth` | Optional exact width of the exported image in pixels. With a fixed `aspectRatio` the height is exact too (1920 at `16:9` is 1920×1080). |
| `frame` | `none`, `hairline`, `glass` |
| `autoTrim` | `true` or `false` |
| `smartBackground` | Optional: `vibrant`, `mesh`, `pastel` or `dark`. When set, `background` is regenerated from each screenshot's colours (see below). |
| `innerPadding` | 0 to 150 units of the trimmed content. Only used when a plain background is detected. |

Colours are hex strings: `#RRGGBB` or `#RRGGBBAA`.

## Backgrounds

| `type` | Fields |
| --- | --- |
| `transparent` | none |
| `solid` | `color` |
| `linearGradient` | `stops` (array of `color` and `location` 0 to 1), `angle` in degrees using the CSS convention (0 points up, 90 points right) |
| `mesh` | `base` colour, and `blobs`: each has `x`, `y` (0 to 1, from the top-left), `radius` (fraction of the canvas' longest side) and `color`. Each blob is a radial gradient from its colour, through 50% alpha at 45% of the radius, to transparent. |
| `image` | `path` to an image file, `blur` in units. The image is scaled to fill the canvas. |

## Layout rules

1. If `autoTrim` is on, first cut thin foreign slivers off each edge (a few pixels of desktop or a neighbouring window caught by a sloppy selection). A side is a candidate when its outermost line covers less than half with the colour that frames the rest of the image. Within a depth of 2% of the image size (at least 6 px, at most 16 px), find the first line that is at least 92% one colour, followed by another such line, where the outermost line has less than 60% of that colour. Everything outside that line is cut.
   Then cut content that the capture edge ran through (e.g. half a column of sidebar labels). A side qualifies when its outermost line is 50% to 99.5% background with content touching it, a gap of fully background lines at least 3% of the image size (and at least 16 px) starts within the outer 25%, the strip before the gap is at least 60% background, and the content beyond the gap spans at least twice the strip. Both steps are skipped when the user has cropped by hand.
2. Then look for a plain background. The candidate is the most common colour along the image edges. It counts as the background when it covers at least 70% of all edge pixels and at least 30% of each of the four edges, within a per-channel tolerance of 2. A transparent candidate means a window capture.
3. Remove rows and columns at the edges that are entirely background.
4. If the background is a colour (not transparent), add an even inner margin of that colour around the content: `innerPadding` units, and never less than half the corner radius, so rounded corners cannot clip the content.
5. The card is the screenshot plus a title bar: 28 units for `light` and `dark`, 46 units for the browser styles. Traffic lights are 12 units wide, 20 units apart, with the first centred 20 units from the left, moved right only if needed to stay inside the rounded corner.
6. With a `device`, the card sits on the device's screen, which keeps the real shape: 3024×1964 for the MacBook, 1179×2556 for the iPhone (turned landscape for wide shots).
   - **Full screen:** when the card's shape is within 5% (MacBook) or 6% (iPhone) of the screen's, the screen takes the card's exact size.
   - **MacBook desktop:** otherwise the card sits centred on a desktop wallpaper with a margin of 7% of its longest side, keeps its corner radius (at least 10 units) and gets a medium shadow. The notch is drawn only in this mode.
   - **iPhone app:** a portrait card that isn't phone-shaped sits below a status bar (54/393 of the screen width) with room for the home indicator (34/393), centred horizontally.
   - Gaps beside a full-screen card are filled with the most common colour of the card edge they touch.
   - MacBook bezels are 2.2% of the screen width at the sides, 3% at the top and 4.2% at the bottom, with a base 12% wider than the lid. iPhone bezels are 4% of the screen's short side, with screen corners of 14%.
   The device (including the base) is what gets padded and centred.
7. The minimum canvas is the card (or device) plus `padding` on each side, plus a 14-unit frame when `frame` is `glass`.
8. For a fixed aspect ratio, the canvas grows along one axis until it matches. With `auto`, it grows only if needed to keep the shape between 4:5 and 2:1.
9. Canvas width and height are rounded up so the space left on each side of the card is a whole pixel. The card is centred exactly.

On export, a result whose longest side is under 1600 px may be enlarged by the smallest whole factor (up to 4) that reaches it. The shot is enlarged with nearest-neighbour sampling so pixels stay sharp, then annotations and the composition are drawn at the new size.

Shadow parameters (blur, y-offset, opacity) are: soft (30, 8, 0.22), medium (50, 18, 0.35), strong (70, 28, 0.5).

## Smart backgrounds

1. Downscale the screenshot to at most 96 px on its longest side.
2. Ignore pixels that are mostly transparent, have saturation below 0.25 or brightness below 0.25.
3. Sort the rest into 36 hue bins, each pixel weighted by saturation × brightness, so the accent covering the most area wins. Smooth each bin with half of each neighbour.
4. The primary hue is the strongest bin. The secondary is the strongest bin at least 40° away with at least 20% of the primary's weight, or primary + 35°. It is then pulled to within 60° of the primary so gradients never turn muddy.
5. With almost no colourful pixels (fewer than 1 in 400), use hues 230° and 270° with saturation scaled by 0.35.

Each look is built from those two hues in HSB:

| Variant | Background |
| --- | --- |
| `vibrant` | Linear gradient at 135°: (h1, 0.60, 0.97) to (h2, 0.72, 0.82) |
| `mesh` | Base (h1, 0.55, 0.88) with four blobs around the corners |
| `pastel` | Linear gradient at 160°: (h1, 0.16, 1.0) to (h2, 0.26, 0.97) |
| `dark` | Base (h1, 0.55, 0.12) with glowing blobs (h1, 0.75, 0.55) and (h2, 0.75, 0.42) |

The exact blob positions are in `Sources/ScreenshottyCore/SmartBackground.swift`.

## Styles

A style is a name plus settings: `{ "id": "…", "name": "X post", "settings": { … } }`. Built-in styles:

| Style | Settings |
| --- | --- |
| X post | 16:9, 1600 px wide, vibrant smart background |
| LinkedIn | 1.91:1, 1200 px wide, mesh smart background |
| Instagram | 4:5, 1080 px wide, pastel smart background |
| Launch | 16:9, 1920 px wide, light browser window, strong shadow |
| Mobile app | 4:5, 1080 px wide, iPhone |
| MacBook | 16:9, 1920 px wide, MacBook, dark smart background |
| Docs | transparent, soft shadow, natural size |

## Sensitive info

Text is read on the device (Apple Vision, accurate mode, no language correction). Each line is matched
against these patterns, first match wins, with no overlaps:

- **Email:** `name@domain.tld`.
- **Token:** JSON Web Tokens (`eyJ…`.`…`.`…`).
- **API key:** well-known prefixes (`sk_`, `pk_`, `rk_`, `sk-`, `ghp_`, `github_pat_`, `AKIA`, `xoxb-`, `AIza`, `glpat-`, `whsec_` and more), or any 32+ character string mixing upper case, lower case and at least 3 digits.
- **Card number:** 13 to 19 digits that pass the Luhn check.
- **Phone number:** `(415) 555-0132`, `415-555-0132` and international `+44 20 7946 0958` forms.
- **IP address:** IPv4.

Each match's box is padded by a quarter of its height and covered with a `redact` or `blur` annotation.
