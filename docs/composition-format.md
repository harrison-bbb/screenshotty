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
| `windowChrome` | `none`, `light`, `dark` |
| `frame` | `none`, `hairline`, `glass` |
| `autoTrim` | `true` or `false` |
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

1. If `autoTrim` is on, look for a plain background. The candidate is the most common colour along the image edges. It counts as the background when it covers at least 70% of all edge pixels and at least 30% of each of the four edges, within a per-channel tolerance of 2. A transparent candidate means a window capture.
2. Remove rows and columns at the edges that are entirely background.
3. If the background is a colour (not transparent), add an even inner margin of that colour around the content: `innerPadding` units, and never less than half the corner radius, so rounded corners cannot clip the content.
4. The card is the screenshot plus a 28-unit title bar when `windowChrome` is not `none`. Traffic lights are 12 units wide, 20 units apart, with the first centred 20 units from the left, moved right only if needed to stay inside the rounded corner.
5. The minimum canvas is the card plus `padding` on each side, plus a 14-unit frame when `frame` is `glass`.
6. For a fixed aspect ratio, the canvas grows along one axis until it matches.
7. Canvas width and height are rounded up so the space left on each side of the card is a whole pixel. The card is centred exactly.

Shadow parameters (blur, y-offset, opacity) are: soft (30, 8, 0.22), medium (50, 18, 0.35), strong (70, 28, 0.5).
