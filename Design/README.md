# Design

Salah's design system: one visual language for the macOS app and for future iPhone, iPad
and Apple Watch apps, their widgets and the system surfaces they appear on.

The look is calm and follows the time of day. Five time-of-day phases, from dawn at Fajr
to night at Isha, tint the sky behind the next prayer, its marks and its widgets; a
neutral sky stands in when the user turns that off. Everything else is native: system backgrounds,
labels and materials, plus one gold accent.

| Folder | What it holds |
| --- | --- |
| [`tokens/`](tokens) | The design tokens, in the W3C Design Tokens format, and a checker with its tests |
| [`Icons/`](Icons) | Custom symbols for the prayers, as SF Symbols templates |
| [`AppIcon/`](AppIcon) | The app icon as an Icon Composer document, and its layer sources |
| [`Previews/`](Previews) | Rendered images of key screens |

## The Figma library

The source of truth is a Figma library. The file is private to the maintainers' team, so
it is described here rather than linked. The tokens in this folder mirror its variables
and styles; if you need something from the file, ask in an
[issue](https://github.com/salah-kit/Salah/issues).

Pages:

- **Cover** and **Read me**.
- **Foundations:** Color, Typography, Layout, Materials & Elevation, Motion, Iconography,
  App Icon.
- **Components:** System references, Components · Prayer, Components · Settings & States,
  Components · Widgets & Surfaces, Patterns.
- **Screens:** iPhone, iPad, macOS, watchOS, Widgets & System Surfaces.
- **Accessibility.**

Variable collections and their modes:

| Collection | Modes | Holds |
| --- | --- | --- |
| Primitives | one | The raw palette: a gold ramp, six time-of-day ramps and Apple's system grays |
| Color | Light, Dark, Light · Increased contrast, Dark · Increased contrast | Semantic colors, plus one color set per time of day |
| Phase | Fajr, Dhuhr, Asr, Maghrib, Isha, Neutral | The sky, tint and text of the current time of day |
| Rendering | Full color, Accented, Accented · watch, Vibrant | Widget colors under each WidgetKit rendering mode |
| Typeface | Latin, Arabic, Latin · SF fonts, Arabic · SF fonts | Font families for the Figma drawings |
| Type scale | Default (Large), xxxLarge, AX3, AX5 | Font sizes and line heights at four Dynamic Type sizes |
| Layout | iOS, iPadOS, macOS, watchOS | Margins, padding, row and control heights, radii |
| Dimension | one | Spacing, radius, symbol size and stroke scales |
| Motion | Default, Reduce Motion | Animation durations |

The phase is the prayer period you're in: Fajr until sunrise, Dhuhr from sunrise until
Asr (sunrise is only a marker), then Asr, Maghrib, and Isha until the next Fajr. Neutral
turns time-of-day color off and keeps the gold accent.

## Tokens

The files follow the [Design Tokens Format Module 2025.10](https://www.designtokens.org/tr/2025.10/format/),
the first stable version of the W3C community group's format. Each token has a `$type`, a
`$value` and a `$description`; references use `{group.token}`; colors are sRGB objects with
`components`, `alpha` and `hex`.

There is one file per collection and mode. Files of the same collection define the same
tokens, so you pick one file per collection:

| Files | Root group | Pick |
| --- | --- | --- |
| `primitives.json` | `primitives` | Always |
| `color.light.json`, `color.dark.json`, `color.light-increased-contrast.json`, `color.dark-increased-contrast.json` | `color` | The appearance and the Increase Contrast setting |
| `phase.fajr.json` … `phase.neutral.json` | `phase` | The current prayer period |
| `rendering.full-color.json`, `.accented`, `.accented-watch`, `.vibrant` | `rendering` | The widget rendering mode |
| `typography.ios.json`, `.macos`, `.watchos` | `typography` | One per platform; they can be combined |
| `type-scale.default.json`, `.xxxlarge`, `.ax3`, `.ax5` | `type-scale` | The Dynamic Type size |
| `layout.ios.json`, `.ipados`, `.macos`, `.watchos` | `layout` | The platform |
| `dimension.json` | `dimension` | Always |
| `motion.default.json`, `motion.reduce-motion.json` | `motion` | The Reduce Motion setting |
| `effects.json` | `effects` | Always |

References cross files: semantic colors point at primitives, phase tokens point at the
phase sets in the color files, and shadows point at color tokens. Load the files a token
needs together.

Units:

- Sizes are Apple points. The format only allows `px` and `rem`, so `1px` in these files
  means 1 pt, the density-independent unit that Figma and SwiftUI both use.
- Durations are in milliseconds.
- A typography token's `lineHeight` is a ratio of its font size, as the format requires.
  The line height in points is in its `$extensions`.

Each token's `$extensions` entry under `io.github.salah-kit` carries what code needs and the
format can't express:

- `swift`: how SwiftUI writes the token. Most are names in a Salah namespace, such as
  `SalahColor.labelSecondary` or `SalahSpace.s16`; some are a system API, such as
  `.thinMaterial` or `Capsule()`. Where a widget rendering token needs different code in
  accented and vibrant rendering, it follows the full-color code after ` / ` (see
  [Widgets](#widgets)).
- On a typography token, how code sizes the style: `textStyle`, the `Font.TextStyle` it uses;
  `scaledRelativeTo`, the text style a custom size scales with through `@ScaledMetric`, plus
  `maxDynamicTypeSize` where it stops growing; or `fixedSize`, on macOS. Alongside are
  `design`, `weight`, `monospacedDigit`, the line height in points, the Arabic font, and
  `typeScale`, the type-scale tokens the style follows at every text size.
- On materials and Liquid Glass: `tint`, `rim` and `highlight`, the colors drawn with them;
  `reduceTransparencyFallback`, the opaque color that replaces them under Reduce
  Transparency; and `figmaGlass`, the settings of the Figma glass effect.
- `figmaStyle`: the Figma style the token mirrors.

Typography and shadow tokens have no `swift` entry. A text style is described by the keys
above, and a shadow's value is the shadow itself, with the SwiftUI modifier in its
description. Materials are dimension tokens holding the blur radius of the Figma drawing.
Liquid Glass has no token type, so each glass style is a group described only by
`$description` and `$extensions`.

## Using the tokens in SwiftUI

### Color

Use a system color wherever one matches, so the app follows the platform, Increase Contrast
and future appearance changes. Every color token's `swift` entry names it in a `SalahColor`
namespace that mirrors the color files. For the tokens in this table, define that name as
the system color or style shown; give the others the token's values from the color files,
for example with an asset catalog color set (see [Increase Contrast](#increase-contrast)).

| Token | SwiftUI |
| --- | --- |
| `label/primary` | `.primary` |
| `bg/primary`, `bg/secondary`, `bg/tertiary` | `Color(.systemBackground)`, `Color(.secondarySystemBackground)`, `Color(.tertiarySystemBackground)` (iOS) |
| `bg/grouped`, `bg/grouped-secondary`, `bg/grouped-tertiary` | `Color(.systemGroupedBackground)` and its secondary and tertiary variants (iOS) |
| `bg/window`, `bg/content` | `Color(nsColor: .windowBackgroundColor)`, `Color(nsColor: .controlBackgroundColor)` (macOS) |
| `separator/default` | `.separator` |
| `separator/opaque` | `Color(.opaqueSeparator)` (iOS) |
| `fill/primary` … `fill/quaternary` | `.fill`, `.fill.secondary`, `.fill.tertiary`, `.fill.quaternary` |
| `accent/default` | `Color.accentColor`, with the asset catalog's accent color set to these values |
| Everything else | `SalahColor`, for example `SalahColor.labelSecondary` |

`label/secondary` is deliberately stronger than the system's secondary label so body text
keeps 4.5:1 on every surface; don't swap in `.secondary` for body text.

`fill/form-group` and `separator/form-row` are a macOS grouped `Form`'s section and the line
between its rows. On macOS 27 the window and its content share one color, so `Form` with
`.formStyle(.grouped)` sets each section apart with a faint fill. It draws both of these
itself, so a form needs neither; the Figma screens use them to draw Settings. Use them only
for a section you draw yourself.

The time-of-day colors come from the current prayer period. The color files hold one set
per period (`phase-fajr` … `phase-neutral`), each with the same five slots: `sky-top`,
`sky-bottom`, `tint`, `text` and `tint-subtle`. Code picks the set for the period and
reads the slots; the Phase files name the slots so a design can switch periods without
rebinding. Draw the sky as a top-to-bottom gradient from `sky-top` to `sky-bottom`.

### Increase Contrast

When Increase Contrast is on, the colors come from the Increased contrast files:
`color.light-increased-contrast.json` in the light appearance and
`color.dark-increased-contrast.json` in the dark one. In them, text reaches 7:1 against the
surfaces it's used on, and graphics and large text reach 4.5:1. Fills, glass and the scrim are
more opaque, except `fill/form-group`, which stays at 3% as `Form` draws it; the row line
between its rows rises from 5% to 15%. A few pairs keep the standard 4.5:1: secondary text on translucent chips, where
7:1 would make it as dark as primary text, and the warning color, which turns brown at 7:1.
`CONTRAST_EXCEPTIONS` in `tokens/check_tokens.py` lists each pair with its ratio. The checker
fails when a listed ratio changes or a listed pair reaches its target, so the list stays true.

- **System colors need nothing.** The tokens the table above maps to system colors (all but
  `accent/default`) adapt because the system colors do. In the Increased contrast files they
  change where the system's colors change under Increase Contrast, as measured on iOS 27 and
  macOS 27, so the Figma drawings match.
- **Asset catalog colors.** In each color set, the accent color included, turn on High
  Contrast in the Attributes inspector, and fill the High Contrast slots from the Increased
  contrast files. `Color("…")` and `Color.accentColor` then pick the variant themselves.
- **Colors defined in code.** Give the token all four values, and pick one with
  `colorScheme` and `colorSchemeContrast`:

```swift
extension SalahColor {
  // accent/text in the four color files
  static func accentText(_ scheme: ColorScheme, _ contrast: ColorSchemeContrast) -> Color {
    switch (scheme == .dark, contrast == .increased) {
    case (false, false): SalahPalette.gold700
    case (false, true): SalahPalette.gold850
    case (true, false): SalahPalette.gold300
    case (true, true): SalahPalette.gold100
    }
  }
}

struct NextPrayerTime: View {
  let time: String
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.colorSchemeContrast) private var contrast

  var body: some View {
    Text(time).foregroundStyle(SalahColor.accentText(colorScheme, contrast))
  }
}
```

### Type

Text styles map to `Font.TextStyle`, so they scale with Dynamic Type on iOS and watchOS.
The typography files give each style at the default size; the type-scale files give the
sizes at larger settings for design review. Code doesn't read them, because the system
scales the text styles itself.

```swift
Text(prayer.name).font(.headline)
Text(prayer.time, style: .time).font(.body.monospacedDigit())
Text(countdown).font(.title.weight(.semibold).monospacedDigit()).fontDesign(.rounded)
```

Numeric display styles have sizes no text style provides. They scale with
`@ScaledMetric(relativeTo:)` from the `scaledRelativeTo` style in `$extensions`. Countdowns
never wrap: give each `.lineLimit(1)` and a `.minimumScaleFactor`, so a long one, such as one
with two-digit hours, shrinks to fit. The hero countdowns need `.minimumScaleFactor(0.5)`:
at that factor they fit at every text size, on a 40 mm watch and on an iPhone with Display
Zoom. The iPhone hero countdown also stops growing at AX3, its `maxDynamicTypeSize`:

```swift
struct HeroCountdown: View {
  let countdown: String
  @ScaledMetric(relativeTo: .largeTitle) private var size = 64.0

  var body: some View {
    Text(countdown)
      .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
      .lineLimit(1)
      .minimumScaleFactor(0.5)
  }
}

HeroCountdown(countdown: countdown)
  .dynamicTypeSize(...DynamicTypeSize.accessibility3)
```

The type-scale files hold the sizes this code produces at each text size, rounded to the
pixels of a 3x iPhone and a 2x watch as the system rounds them, so a design at a large size
matches the app. On watchOS, `Font.footnote` is the type scale's Footnote 1, so Footnote 2
is 12 pt scaled relative to `.footnote` the same way. macOS has no Dynamic Type, so its
styles are fixed and the dropdown countdown is `Font.system(size: 30)`. Every countdown and
time uses `.monospacedDigit()` so digits don't shift as they change.

A watch's default text size depends on its size: Large on 40 to 42 mm watches, xLarge on 44
to 49 mm. A text size gives a text style the same point size on every watch, so the type
scale's text styles hold everywhere. `@ScaledMetric` is different: it returns its base value
at the watch's own default. The type scale's scaled watch sizes (the countdown display and
Footnote 2) are those of a 40 to 42 mm watch; on a larger watch they reach their base size
at xLarge instead, a step later.

At the accessibility sizes (AX1 to AX5), switch layouts rather than shrink text; countdowns
are the exception above. In a prayer row the time moves under the name, in a settings row
the value moves under the title, the date header stacks its place under the dates, and the
sun arc steps aside because the list already carries every time. Read
`dynamicTypeSize.isAccessibilitySize` to choose the layout. System bars keep their size;
iOS shows their labels in the large content viewer. In widgets, keep each name in the
schedule on one line with `.lineLimit(1)` and `.minimumScaleFactor(0.85)`, so long names
such as the French "Lever du soleil" shrink slightly before they truncate.

### Layout and spacing

Spacing, radii and sizes become constants: `SalahSpace`, `SalahRadius`, `SalahSize`,
`SalahStroke`, and `SalahLayout` for the per-platform metrics, named as in each token's
`swift` entry. Use continuous corners, `RoundedRectangle(cornerRadius:style: .continuous)`,
and `Capsule()` for `radius/capsule`.

### Motion

Read `accessibilityReduceMotion` from the environment and use the Reduce Motion value when
it's on. A value of 0 means no animation: show the end state, or cross-fade.

| Token | Default | Reduce Motion |
| --- | --- | --- |
| `countdown-tick/duration` | 350 ms | 200 ms |
| `prayer-change/duration` | 500 ms | 250 ms |
| `phase-change/duration` | 1200 ms | 400 ms |
| `adhan/pulse-period` | 1600 ms | 0 (static) |
| `approaching/breath-period` | 2400 ms | 0 (none) |
| `press/duration` | 120 ms | 120 ms |
| `spring/response` | 350 ms | 0 (cross-fade) |

### Materials, glass and elevation

`effects.json` maps materials to `.thinMaterial`, `.regularMaterial` and `.thickMaterial`,
and Liquid Glass to `.glassEffect(.regular)`, `.glassEffect(.clear)` and a tinted regular
glass. Each names its opaque fallback for Reduce Transparency. Native surfaces draw their
own shadows; the elevation tokens are for custom floating views only.

### Widgets

The Appearance preview uses normal desktop reference bounds measured on Mac14,10 with
macOS 27.0.1 (26A434). The native widget takes its actual bounds from WidgetKit, so it can
adapt to other hosts and presentation states. The [measurements report](https://github.com/salah-kit/Salah/issues/28#issuecomment-6288113668)
records the captures, content and display configuration:

| Mac reference surface and state | Size, pt |
| --- | --- |
| Desktop Small, normal | 164 × 164 |
| Desktop Medium, normal | 344 × 164 |
| Desktop Large, normal | 344 × 344 |
| Temporary Dhuhr notification banner, unexpanded | 344 × 58 |
| Banner icon image-element frame, including internal padding | 39 × 39 |

The expanded Medium host boundary measured 352 × 172 pt in a separate state; it does not
replace the normal reference. Notification height can vary with content. These measurements
exclude exterior shadows and describe the observed host, OS and state, rather than universal
system dimensions. Phone and watch references are independent. StandBy's 330 × 330 pt
reference remains an estimate pending the physical iPhone measurement in
[#28](https://github.com/salah-kit/Salah/issues/28).

The Rendering tokens simulate WidgetKit's rendering modes in Figma. In code, put the sky in
`containerBackground(for: .widget)` so the system can remove it, and mark the one accent
element `.widgetAccentable()`. On watch faces, the time-of-day marks are accentable too: they
keep their full-color tint and take the face color (see the `mark` token).

In full color, use the colors the Rendering tokens point to, such as
`SalahColor.labelSecondary`: on the lighter skies the system's `.secondary` and `.tertiary`
fall to about 3.2:1 and 1.7:1. In accented rendering the system recolors the content and
keeps its opacity; in vibrant rendering it turns the content into a monochrome tint by its
brightness. Either way, hierarchy comes from `.primary`, `.secondary` and `.tertiary`, so
use them there. Where the code differs, a Rendering token's `swift` entry gives both, full
color first:

```swift
@Environment(\.widgetRenderingMode) private var renderingMode

private var secondary: AnyShapeStyle {
  renderingMode == .fullColor ? AnyShapeStyle(SalahColor.labelSecondary) : AnyShapeStyle(.secondary)
}
```

The macOS app draws these tokens through `SalahPalette` and `SalahPhase`
(`Shared/WidgetUI/SalahPalette.swift`): the widgets, their Settings → Appearance preview,
the dropdown and Today. The sky is the phase's pair, top to bottom, or Neutral when the
user turns off Follow the time of day or the day's times aren't known. In the dropdown, the
prayer one is in carries the phase's mark on its glyph and `Phase/text` on its text, since
the mark holds only 3:1. The widgets follow the widget components instead: its row, its
count-up and the medium and large faces' Now eyebrow take the mark itself, at 3:1. The next
prayer carries the accent on its wash.

`PaletteContrastTests` in SalahTests holds the tokens to their promises in light and dark,
with and without Increase Contrast: primary, secondary and accent text and each phase's
text at 4.5:1, and tertiary text (passed prayers), the accent mark and each phase's tint at
3:1, on both ends of every sky, on the dropdown's and the window's surfaces and on the
washes under the current and next rows, and the on-accent label at 4.5:1 on the gold fill.

## Symbols

`Icons/` holds eight custom symbols as SF Symbols templates: `salah.fajr`,
`salah.sunrise`, `salah.dhuhr`, `salah.asr`, `salah.maghrib`, `salah.isha`,
`salah.jumuah` and `salah.iqama`. For any other symbol, use SF Symbols.

To use one, drag its SVG into an asset catalog in Xcode. Xcode makes a Symbol Image Set
with the same name. Then use it like a system symbol:

```swift
Image("salah.fajr")
  .symbolRenderingMode(.hierarchical)
  .foregroundStyle(SalahColor.Phase.fajr.tint)

Label("Fajr", image: "salah.fajr")
```

The symbols scale with the surrounding font and support monochrome and hierarchical
rendering. To edit one, open it in the SF Symbols app and export the template again.

## App icon

`AppIcon/Salah.icon` is an Icon Composer document: a square icon for iOS, iPadOS and macOS,
with light, dark, tinted and clear appearances, and a round icon for watchOS. Open it in Icon
Composer to view or edit it.

To use it in an app target, add `Salah.icon` to the target and set the target's app icon
name (`ASSETCATALOG_COMPILER_APPICON_NAME`) to `Salah`. Xcode compiles the icon and
generates flat images for older system versions.

`AppIcon/Layers/` holds the source SVG of each layer, with dark variants. The document
keeps its own copies in `Salah.icon/Assets/`, so after editing a layer, replace it in Icon
Composer as well.

The canvas is 1024 × 1024 pt, but watchOS's circle reaches about 3% past the canvas at the
middle of each side. So the layers that fill the icon (`background`, `background-dark` and
`texture`) are 1152 pt square, 64 pt past the canvas on every side. If one of them stopped at
the canvas, the icon's own fill would show as a band at the circle's left and right edges.
Squares clip at the canvas, so the extra doesn't show on iOS, iPadOS or macOS.

To check the icon before a change lands, compile it with `actool` from the repository root,
once per platform (`iphoneos`, `macosx` and `watchos`, each with its minimum version):

```sh
out=$(mktemp -d)
xcrun actool --compile "$out" --app-icon Salah --include-all-app-icons \
  --platform macosx --minimum-deployment-target 14.0 \
  --output-partial-info-plist "$out/partial.plist" Design/AppIcon/Salah.icon
```

To check the symbols, put each SVG in a symbol set of a scratch asset catalog and compile
that:

```sh
cat=$(mktemp -d)/Symbols.xcassets
mkdir "$cat" && echo '{"info":{"author":"xcode","version":1}}' > "$cat/Contents.json"
for svg in Design/Icons/*.svg; do
  name=$(basename "$svg" .svg)
  mkdir "$cat/$name.symbolset" && cp "$svg" "$cat/$name.symbolset/"
  echo "{\"info\":{\"author\":\"xcode\",\"version\":1},\"symbols\":[{\"filename\":\"$name.svg\",\"idiom\":\"universal\"}]}" \
    > "$cat/$name.symbolset/Contents.json"
done
xcrun actool --compile "$(mktemp -d)" --platform iphoneos --minimum-deployment-target 17.0 "$cat"
```

`actool` prints a property list that lists any errors and warnings, and exits with a nonzero
status when compiling fails.

## Updating tokens

1. Change the variable or style in the Figma library. If you can't edit the library, change
   the JSON and say so in the pull request, so a maintainer can make the same change in
   Figma.
2. In the same change, update the matching JSON here, in every mode file of that
   collection, and keep the `$description` in step.
3. Run the checker and its tests:

   ```sh
   python3 Design/tokens/check_tokens.py
   python3 -B -m unittest discover -s Design/tokens
   ```

   They need only Python 3.9 or later; `-B` keeps Python from writing a `__pycache__`
   folder into the repository. The checker verifies that the folder holds the expected
   files, every file has the expected shape, every reference resolves to a token of the
   right type, the mode files of a collection define the same tokens, each text style
   matches its type-scale entry and the code that sizes it, and the documented color pairs
   meet WCAG 2 contrast in every color mode (in light and dark, 4.5:1 for text and 3:1 for
   graphics and large text; in the Increased contrast modes, 7:1 and 4.5:1, apart from the
   pairs in its `CONTRAST_EXCEPTIONS`), and that no color in an Increased contrast file is
   weaker than in the standard file. It exits with an error if anything fails.

A new color pair that carries text or meaning needs its contrast checked too: add it to the
checker's lists. A new token file goes in its `FILES`.

## Right to left

Arabic layouts mirror: rows, headers, toolbars, timelines, the sun arc, chevrons,
switches and sliders all run right to left, which SwiftUI does for you when the layout
direction is right to left. A few things never mirror: the prayer symbols, the Qibla
dial (it points at a real bearing), media controls and the app icon. Arabic text uses
Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩); the macOS app sets them when you choose Arabic in its
settings. Some Arabic-speaking regions use Western digits, so no layout depends on which
digits it shows.

## Fonts in the Figma file

Salah's own text styles store stand-in fonts, so they render on any machine: Inter for SF
Pro and SF Compact, Nunito for the rounded designs, and Noto Sans Arabic for Arabic. The
file's Typeface collection switches every style to Apple's fonts (SF Pro, SF Pro Rounded,
SF Compact, SF Compact Rounded, SF Arabic and SF Arabic Rounded) when they're installed.

The system controls and bars on the screens (status bars, tab and navigation bars,
toggles, buttons, alerts, the menu bar and the rest of the System references page) are
Apple's own components, from Apple's iOS and iPadOS, macOS and watchOS design resources.
They always draw in Apple's fonts, so open the file in Figma's desktop app on a Mac with
SF Pro, SF Compact and SF Arabic installed to see them as designed.

Code always uses the system font, so the stand-ins never ship. The typography tokens name
the Apple fonts. Arabic text renders in SF Arabic and SF Arabic Rounded, which the system
picks; there's no separate Arabic token file.

## Previews

`Previews/` holds a few rendered screens, for reading this folder without Figma. They show
Apple's system components. Most are rendered in Apple's fonts, with the Typeface collection
in its SF modes; `macos-dropdown.png` and `macos-settings-notifications-dark.png` are
renders of the macOS page, in its stand-in fonts. They use real times: Makkah on 2 June 2026
with Umm al-Qura, unless the image shows otherwise.

- `cover.png`: the cover of the library.
- `iphone-today.png`: Today on iPhone, in English and Arabic, light and dark.
- `iphone-phases.png`: Today through the five prayer periods, light and dark.
- `ipad-today.png`: Today on iPad in landscape.
- `macos-dropdown.png`: the menu-bar dropdown, in English and Arabic, light and dark.
- `macos-settings-notifications-dark.png`: the Notifications pane of Salah's window, in dark.
- `macos-desktop-widgets.png`: the desktop widgets, with the Stop face.
- `watchos.png`: the watch app, in English and Arabic.
- `ios-home-screen-widgets.png`: Home Screen widgets in light, dark, tinted and Arabic.
- `ios-lock-screen.png`: Lock Screen accessories and the Live Activity.
- `app-icon.png`: the app icon at 256 px, for the README.

`app-icon.png` is the icon's 256 px rendition. After changing the icon, compile it as
[App icon](#app-icon) shows, then extract that rendition:

```sh
iconutil -c iconset "$out/Salah.icns" -o "$out/Salah.iconset"
cp "$out/Salah.iconset/icon_128x128@2x.png" Design/Previews/app-icon.png
```
