#!/usr/bin/env python3
"""Check the Salah design tokens in this folder.

Run from anywhere with Python 3.9 or later; it needs no packages:

    python3 Design/tokens/check_tokens.py

It verifies that:
- the folder holds exactly the token files listed in FILES below, each valid JSON without repeated
  keys, in the Design Tokens Format Module 2025.10 shape this folder uses;
- every color's hex matches its sRGB components;
- every reference, in a value, inside a composite value or in $extensions, is well formed, resolves
  without a cycle and points at a token of the type its position needs;
- the files of one collection (one file per mode) define the same tokens, with the same types and
  the same $extensions;
- each Phase file points every slot at the same slot of its own prayer period in the color files;
- each typography token matches its own type-scale entry at the default size. A token that is a
  text style has that style's size and line height at every Dynamic Type size in the type-scale
  files; a size scaled with @ScaledMetric grows with its text style, within 10%, up to its
  maxDynamicTypeSize;
- type-scale sizes never shrink as the text size grows;
- the documented color pairs meet WCAG 2 contrast in light and dark: 4.5:1 for text, 3:1 for
  graphics and large text. Translucent colors are composited over their background first.

It prints a summary and exits with status 1 if any check fails.
"""
import json
import math
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
EXT = 'io.github.salah-kit'
REF = re.compile(r'^\{([^{}]+)\}$')
BRACES = re.compile(r'\{([^{}]*)\}')
TOKEN_PATH = re.compile(r'[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*')
TYPES = {'color', 'dimension', 'duration', 'number', 'fontFamily', 'fontWeight', 'typography', 'shadow'}
PHASES = ['fajr', 'dhuhr', 'asr', 'maghrib', 'isha', 'neutral']
# Collections with one file per mode, in the order of their modes. Every file of a collection must
# define the same tokens.
MODES = {
    'color': ['light', 'dark'],
    'phase': PHASES,
    'rendering': ['full-color', 'accented', 'accented-watch', 'vibrant'],
    'type-scale': ['default', 'xxxlarge', 'ax3', 'ax5'],
    'layout': ['ios', 'ipados', 'macos', 'watchos'],
    'motion': ['default', 'reduce-motion'],
}
PLATFORMS = ['ios', 'macos', 'watchos']
SINGLE = ['primitives', 'dimension', 'effects'] + [f'typography.{p}' for p in PLATFORMS]
FILES = {f'{name}.json' for name in SINGLE} | {f'{c}.{m}.json' for c, modes in MODES.items() for m in modes}
# The Dynamic Type size each type-scale file stands for, smallest first.
DYNAMIC_TYPE = {'default': 'large', 'xxxlarge': 'xxxLarge', 'ax3': 'accessibility3', 'ax5': 'accessibility5'}
DYNAMIC_TYPE_ORDER = ['xSmall', 'small', 'medium', 'large', 'xLarge', 'xxLarge', 'xxxLarge', 'accessibility1',
                      'accessibility2', 'accessibility3', 'accessibility4', 'accessibility5']
# Font.TextStyle cases and the type-scale entries that hold their sizes. On watchOS, Font.footnote is
# the style the type scale calls footnote-1.
TEXT_STYLES = {'largeTitle': 'large-title', 'title': 'title-1', 'title2': 'title-2', 'title3': 'title-3',
               'headline': 'headline', 'body': 'body', 'callout': 'callout', 'subheadline': 'subheadline',
               'footnote': 'footnote', 'caption': 'caption-1', 'caption2': 'caption-2'}
# $extensions keys that hold a color reference.
COLOR_LINKS = ('tint', 'rim', 'highlight', 'reduceTransparencyFallback')

errors = []


def fail(msg):
    errors.append(msg)


def is_num(x):
    """A finite number. Python reads a literal too large for a float, such as 1e400, as infinity."""
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        return False
    try:
        return math.isfinite(x)
    except OverflowError:  # an integer too large for a float
        return False


def is_ref(v):
    return isinstance(v, str) and REF.match(v)


def extension(node):
    ext = node.get('$extensions') if isinstance(node, dict) else None
    ext = ext.get(EXT) if isinstance(ext, dict) else None
    return ext if isinstance(ext, dict) else {}


# ------------------------------------------------------------------ loading
def walk(name, node, path, out):
    """Collect the tokens of file `name` (objects with $value) by dotted path."""
    if not isinstance(node, dict):
        fail(f'{name}: {".".join(path) or "the root"}: expected an object')
        return
    if '$value' in node:
        out['.'.join(path)] = node
        return
    for key, child in node.items():
        if key.startswith('$'):
            continue
        if any(c in key for c in '{}.'):
            fail(f'{name}: {".".join(path + [key])}: names may not contain braces or dots')
        walk(name, child, path + [key], out)


def load(directory):
    def unique_keys(name):
        def hook(pairs):
            seen = set()
            for key, _ in pairs:
                if key in seen:
                    fail(f'{name}: the key {key!r} appears twice in one object')
                seen.add(key)
            return dict(pairs)
        return hook

    def no_constant(word):
        raise ValueError(f'{word} is not a JSON number')

    files = {}
    present = {p.name for p in directory.glob('*.json')}
    for name in sorted(FILES - present):
        fail(f'missing {name}')
    for name in sorted(present - FILES):
        fail(f'unexpected file {name}: add it to FILES in this checker and to Design/README.md')
    for name in sorted(present & FILES):
        try:
            doc = json.loads((directory / name).read_text(encoding='utf-8'), object_pairs_hook=unique_keys(name),
                             parse_constant=no_constant)
        except UnicodeDecodeError as e:
            fail(f'{name}: not UTF-8: {e}')
            continue
        except ValueError as e:  # json.JSONDecodeError, or NaN and Infinity, which JSON doesn't allow
            fail(f'{name}: invalid JSON: {e}')
            continue
        tokens = {}
        walk(name, doc, [], tokens)
        files[name] = (doc, tokens)
    return files


# ------------------------------------------------------------------ value shapes
def check_dim(v, where, units=('px', 'rem')):
    if not (isinstance(v, dict) and is_num(v.get('value')) and v.get('unit') in units):
        fail(f'{where}: expected {{value, unit}} with unit in {units}, got {v!r}')


def check_color(v, where):
    if not isinstance(v, dict) or v.get('colorSpace') != 'srgb':
        fail(f'{where}: expected an sRGB color object')
        return
    comps, alpha, hexv = v.get('components'), v.get('alpha', 1), v.get('hex')
    if not (isinstance(comps, list) and len(comps) == 3 and all(is_num(c) and 0 <= c <= 1 for c in comps)):
        fail(f'{where}: components must be three numbers in 0...1')
        return
    if not (is_num(alpha) and 0 <= alpha <= 1):
        fail(f'{where}: alpha must be a number in 0...1')
    if hexv is not None:
        if not (isinstance(hexv, str) and re.fullmatch(r'#[0-9a-f]{6}', hexv)):
            fail(f'{where}: hex must be #rrggbb')
        elif [int(hexv[i:i + 2], 16) for i in (1, 3, 5)] != [int(c * 255 + 0.5) for c in comps]:  # half up, as CSS and Figma round
            fail(f'{where}: hex {hexv} does not match components {comps}')


def check_value(t, v, where, typed_refs):
    """Check a value of type t. References are collected with the type their position needs."""
    if is_ref(v):
        typed_refs.append((is_ref(v).group(1), t, where))
        return
    if t == 'color':
        check_color(v, where)
    elif t == 'dimension':
        check_dim(v, where)
    elif t == 'duration':
        check_dim(v, where, ('ms', 's'))
    elif t == 'number':
        if not is_num(v):
            fail(f'{where}: expected a number')
    elif t == 'fontFamily':
        if not (isinstance(v, str) or (isinstance(v, list) and all(isinstance(x, str) for x in v))):
            fail(f'{where}: expected a font family name')
    elif t == 'fontWeight':
        if not (is_num(v) and 1 <= v <= 1000) and not isinstance(v, str):
            fail(f'{where}: expected a weight in 1...1000')
    elif t == 'typography':
        need = {'fontFamily': 'fontFamily', 'fontSize': 'dimension', 'fontWeight': 'fontWeight',
                'letterSpacing': 'dimension', 'lineHeight': 'number'}
        if not (isinstance(v, dict) and need.keys() <= v.keys()):
            fail(f'{where}: typography needs {sorted(need)}')
            return
        for key, kt in need.items():
            check_value(kt, v[key], f'{where}.{key}', typed_refs)
    elif t == 'shadow':
        for i, s in enumerate(v if isinstance(v, list) else [v]):
            w = f'{where}[{i}]'
            if not (isinstance(s, dict) and {'color', 'offsetX', 'offsetY', 'blur', 'spread'} <= s.keys()):
                fail(f'{w}: shadow needs color, offsetX, offsetY, blur and spread')
                continue
            check_value('color', s['color'], w + '.color', typed_refs)
            for k in ('offsetX', 'offsetY', 'blur', 'spread'):
                check_value('dimension', s[k], f'{w}.{k}', typed_refs)


def refs_in(obj, where):
    """Every {reference} inside a value or an $extensions block. Malformed ones fail."""
    if isinstance(obj, str):
        if '{' not in obj and '}' not in obj:
            return []
        found = BRACES.findall(obj)
        good = [r for r in found if TOKEN_PATH.fullmatch(r)]
        if len(good) != len(found) or '{' in BRACES.sub('', obj) or '}' in BRACES.sub('', obj):
            fail(f'{where}: malformed reference in {obj!r}')
        return good
    if isinstance(obj, dict):
        return [r for v in obj.values() for r in refs_in(v, where)]
    if isinstance(obj, list):
        return [r for v in obj for r in refs_in(v, where)]
    return []


def extensions_in(node, path, out):
    if isinstance(node, dict):
        if '$extensions' in node:
            out.append(('.'.join(path), node['$extensions']))
        for k, v in node.items():
            if not k.startswith('$'):
                extensions_in(v, path + [k], out)


# ------------------------------------------------------------------ color math
def resolve(path, pool, seen=()):
    if path in seen:
        raise ValueError('cycle: ' + ' -> '.join(seen + (path,)))
    tok = pool.get(path)
    if tok is None:
        raise KeyError(path)
    v = tok['$value']
    m = is_ref(v)
    return resolve(m.group(1), pool, seen + (path,)) if m else v


def rgba(c):
    return tuple(c['components']) + (c.get('alpha', 1),)


def over(fg, bg):
    """Composite an RGBA color over an opaque RGB background, rounded to 8-bit like a display."""
    a = fg[3]
    return tuple(round((a * f + (1 - a) * b) * 255) / 255 for f, b in zip(fg[:3], bg[:3]))


def luminance(rgb):
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


SKIES = [f'phase-{p}/{f}' for p in PHASES for f in ('sky-top', 'sky-bottom')]
# Text on a translucent chip: (text, chip fill, the backgrounds the chip sits on in the designs).
CHIPS = [
    ('label/primary', 'fill/tertiary', SKIES + ['bg/grouped', 'bg/primary', 'bg/elevated']),
    ('label/secondary', 'fill/tertiary', SKIES + ['bg/grouped', 'bg/primary']),
    ('status/warning', 'fill/tertiary', SKIES),
    ('accent/text', 'fill/secondary', SKIES + ['bg/window']),
    ('label/primary', 'accent/subtle', SKIES + ['bg/elevated', 'bg/grouped-secondary']),
    ('label/secondary', 'accent/subtle', ['bg/grouped-secondary']),
    ('accent/text', 'accent/subtle', SKIES + ['bg/elevated', 'bg/grouped-secondary']),
]


def contrast_checks(files):
    prims = files['primitives.json'][1]
    rows = []
    for mode in ('light', 'dark'):
        pool = {**prims, **files[f'color.{mode}.json'][1]}
        col = lambda name: rgba(resolve('color.' + name.replace('/', '.'), pool))

        def surface(name, base='bg/grouped-secondary'):
            c = col(name)
            return over(c, col(base)) if c[3] < 1 else c[:3]

        surfaces = {s: surface(s) for s in ['bg/primary', 'bg/secondary', 'bg/tertiary', 'bg/grouped',
                                             'bg/grouped-secondary', 'bg/grouped-tertiary', 'bg/elevated',
                                             'bg/window', 'bg/content', 'accent/subtle']}
        for p in PHASES:
            for f in ('sky-top', 'sky-bottom', 'tint-subtle'):
                surfaces[f'phase-{p}/{f}'] = surface(f'phase-{p}/{f}')

        def check(fg, bg, need):
            ratio = contrast(over(col(fg), surfaces[bg]), surfaces[bg])
            rows.append((mode, fg, bg, ratio, need))

        for fg, need in [('label/primary', 4.5), ('label/secondary', 4.5), ('label/tertiary', 3.0),
                         ('accent/text', 4.5), ('accent/default', 3.0)]:
            for bg in list(surfaces):
                check(fg, bg, need)
        for p in PHASES:
            for bg in (f'phase-{p}/sky-top', f'phase-{p}/sky-bottom', f'phase-{p}/tint-subtle', 'bg/primary', 'bg/grouped-secondary'):
                check(f'phase-{p}/text', bg, 4.5)
                check(f'phase-{p}/tint', bg, 3.0)
        for fg in ('status/error', 'status/warning', 'status/success', 'status/info'):
            for bg in ('bg/primary', 'bg/secondary', 'bg/grouped-secondary', 'bg/elevated', 'bg/content', 'bg/window'):
                check(fg, bg, 4.5)
        for fg, chip, bases in CHIPS:
            for base in bases:
                name = f'{chip} over {base}'
                surfaces[name] = over(col(chip), surfaces[base])
                check(fg, name, 4.5)
        surfaces['accent/fill'] = surface('accent/fill')
        check('label/on-accent', 'accent/fill', 4.5)
    return rows


# ------------------------------------------------------------------ typography
def scale_style(platform, text_style, scale):
    """The type-scale entry of a Font.TextStyle on a platform, or None."""
    key = TEXT_STYLES.get(text_style)
    for candidate in ([key, key + '-1'] if key else []):
        if f'type-scale.{platform}.{candidate}.size' in scale:
            return candidate
    return None


def number(x):
    return str(int(x)) if float(x).is_integer() else str(x)


def typography_checks(files):
    scales = {m: files[f'type-scale.{m}.json'][1] for m in MODES['type-scale']}

    def value(mode, path):
        tok = scales[mode].get(path)
        v = tok['$value'] if tok else None
        return v['value'] if isinstance(v, dict) and is_num(v.get('value')) else None

    # Sizes never shrink as the text size grows; macOS has no Dynamic Type, so its sizes never change.
    for path in scales['default']:
        values = [value(m, path) for m in MODES['type-scale']]
        if None in values:
            continue
        if path.startswith('type-scale.macos.') and len(set(values)) != 1:
            fail(f'{path}: macOS has no Dynamic Type, so every type-scale file needs the same value, got {values}')
        elif any(b < a for a, b in zip(values, values[1:])):
            fail(f'{path}: shrinks as the text size grows: {values}')

    count = 0
    for platform in PLATFORMS:
        fname = f'typography.{platform}.json'
        for path, tok in files[fname][1].items():
            count += 1
            where = f'{fname}: {path}'
            v, ext = tok['$value'], extension(tok)
            if not ext.get('figmaStyle'):
                fail(f'{where} has no figmaStyle in $extensions')
            if not (isinstance(v, dict) and isinstance(v.get('fontSize'), dict) and is_num(v['fontSize'].get('value'))
                    and is_num(v.get('lineHeight'))):
                fail(f'{where}: fontSize and lineHeight must be literal values to compare with the type scale')
                continue
            size = v['fontSize']['value']
            lh = ext.get('lineHeight', {}).get('value') if isinstance(ext.get('lineHeight'), dict) else None
            if not is_num(lh) or abs(v['lineHeight'] * size - lh) > 0.01:
                fail(f'{where}: lineHeight ratio does not match {lh} pt')
            for fam in ('Inter', 'Nunito', 'Noto'):
                if fam in str(v.get('fontFamily')):
                    fail(f'{where} uses the Figma stand-in font {v["fontFamily"]}; code uses the system font')

            links = ext.get('typeScale') if isinstance(ext.get('typeScale'), dict) else {}
            size_ref, lh_ref = is_ref(links.get('fontSize')), is_ref(links.get('lineHeight'))
            own = size_ref and re.fullmatch(rf'type-scale\.{platform}\.([a-z0-9-]+)\.size', size_ref.group(1))
            if not own or not lh_ref or lh_ref.group(1) != f'type-scale.{platform}.{own.group(1)}.line-height':
                fail(f'{where}: typeScale must name type-scale.{platform}.<style>.size and the same style\'s line-height')
                continue
            size_path, lh_path = size_ref.group(1), lh_ref.group(1)
            if value('default', size_path) != size:
                fail(f'{where}: font size {size} differs from {size_path} ({value("default", size_path)}) in type-scale.default.json')
            if value('default', lh_path) != lh:
                fail(f'{where}: line height {lh} differs from {lh_path} ({value("default", lh_path)}) in type-scale.default.json')

            kinds = [k for k in ('textStyle', 'scaledRelativeTo', 'fixedSize') if k in ext]
            if len(kinds) != 1:
                fail(f'{where}: needs exactly one of textStyle, scaledRelativeTo and fixedSize, has {kinds}')
                continue
            kind = kinds[0]
            cap = ext.get('maxDynamicTypeSize')
            if cap is not None and kind != 'scaledRelativeTo':
                fail(f'{where}: maxDynamicTypeSize applies only to a scaledRelativeTo size')
            if kind in ('textStyle', 'scaledRelativeTo'):
                name = ext[kind]
                style = scale_style(platform, name, scales['default']) if isinstance(name, str) else None
                if not style:
                    fail(f'{where}: {kind} {name!r} is not a Font.TextStyle in the {platform} type scale')
                    continue
                ref = f'type-scale.{platform}.{style}'
            if kind == 'textStyle':
                # The token is the text style itself: the same size and line height at every text size.
                for mode in MODES['type-scale']:
                    for p, want in ((size_path, ref + '.size'), (lh_path, ref + '.line-height')):
                        if value(mode, p) != value(mode, want):
                            fail(f'{where}: Font.TextStyle.{name} gives {value(mode, want)} in type-scale.{mode}.json ({want}), but {p} is {value(mode, p)}')
                code = f'Font.TextStyle.{name}'
            elif kind == 'scaledRelativeTo':
                code = f'@ScaledMetric(relativeTo: .{name})'
                growing = MODES['type-scale']
                if cap is not None:
                    if not isinstance(cap, str) or cap not in DYNAMIC_TYPE_ORDER:
                        fail(f'{where}: maxDynamicTypeSize {cap!r} is not a DynamicTypeSize')
                        continue
                    growing = [m for m in growing if DYNAMIC_TYPE_ORDER.index(DYNAMIC_TYPE[m]) <= DYNAMIC_TYPE_ORDER.index(cap)]
                    if not growing:
                        fail(f'{where}: maxDynamicTypeSize {cap} is below the default text size')
                        continue
                    # Every larger text size draws at the cap's size: the value of the file that stands
                    # for the cap, or else the value the larger files share.
                    held = MODES['type-scale'][len(growing):]
                    anchor = growing[-1] if DYNAMIC_TYPE[growing[-1]] == cap else (held[0] if held else None)
                    for mode in held:
                        for p in (size_path, lh_path):
                            if value(mode, p) != value(anchor, p):
                                fail(f'{where}: stops growing at {cap}, so {p} in type-scale.{mode}.json must equal type-scale.{anchor}.json')
                # @ScaledMetric grows a value about as much as its text style grows, on a curve of its
                # own; allow 10%.
                for mode in growing:
                    ref_size, ref_default = value(mode, ref + '.size'), value('default', ref + '.size')
                    if not ref_size or not ref_default:
                        continue  # the mode files disagree, which is reported above
                    for p, base in ((size_path, size), (lh_path, lh)):
                        if not is_num(base):
                            continue
                        want, got = base * ref_size / ref_default, value(mode, p)
                        if got is None or abs(got - want) > 0.1 * want:
                            fail(f'{where}: {p} is {got} in type-scale.{mode}.json; scaling with .{name} gives about {want:.1f}')
            else:
                if platform != 'macos':
                    fail(f'{where}: fixedSize is for macOS, which has no Dynamic Type')
                elif ext['fixedSize'] is not True:
                    fail(f'{where}: fixedSize must be true, got {ext["fixedSize"]!r}')
                code = f'Font.system(size: {number(size)})'
            for p, want in ((size_path, code), (lh_path, code + ' (leading)')):
                got = extension(scales['default'].get(p, {})).get('swift')
                if got != want:
                    fail(f'{where}: {p} has swift {got!r}; the style needs {want!r}')
    return count


# ------------------------------------------------------------------ main
def main(directory=HERE):
    errors.clear()
    files = load(directory)
    if errors:
        return report(files, [])

    # Shapes
    typed_refs = []
    for fname, (_, tokens) in files.items():
        for path, tok in tokens.items():
            where = f'{fname}: {path}'
            t = tok.get('$type')
            if not isinstance(t, str) or t not in TYPES:
                fail(f'{where}: unknown $type {t!r}')
                continue
            check_value(t, tok['$value'], where, typed_refs)
            description = tok.get('$description')
            if not (isinstance(description, str) and description.strip()):
                fail(f'{where}: $description must be text, got {description!r}')

    # Mode sets: identical token paths, types and $extensions
    for coll, modes in MODES.items():
        base = f'{coll}.{modes[0]}.json'
        shape = {p: (t.get('$type'), json.dumps(t.get('$extensions'), sort_keys=True)) for p, t in files[base][1].items()}
        for mode in modes[1:]:
            other = f'{coll}.{mode}.json'
            oshape = {p: (t.get('$type'), json.dumps(t.get('$extensions'), sort_keys=True)) for p, t in files[other][1].items()}
            if oshape != shape:
                missing = sorted(set(shape) - set(oshape))[:5]
                extra = sorted(set(oshape) - set(shape))[:5]
                typed = sorted(p for p in set(shape) & set(oshape) if shape[p][0] != oshape[p][0])[:5]
                exts = sorted(p for p in set(shape) & set(oshape) if shape[p][1] != oshape[p][1])[:5]
                fail(f'{other} differs from {base}: missing {missing} extra {extra} type changes {typed} $extensions changes {exts}')

    # References resolve against one file per collection plus every single file. Mode files share
    # a token set, so a reference that resolves in one member resolves in all.
    pool, owner = {}, {}
    for fname, (_, tokens) in files.items():
        parts = fname[:-5].split('.')
        if parts[0] in MODES and parts[1] != MODES[parts[0]][0]:
            continue
        for path, tok in tokens.items():
            if path in pool:
                fail(f'{fname}: {path} is also defined in {owner[path]}')
            pool[path], owner[path] = tok, fname
    ref_count = 0
    for fname, (doc, tokens) in files.items():
        for path, tok in tokens.items():
            for r in refs_in(tok['$value'], f'{fname}: {path}'):
                ref_count += 1
                if r not in pool:
                    fail(f'{fname}: {path} references missing {{{r}}}')
        exts = []
        extensions_in(doc, [], exts)
        for path, ext in exts:
            for r in refs_in(ext, f'{fname}: $extensions of {path}'):
                ref_count += 1
                if r not in pool:
                    fail(f'{fname}: $extensions of {path} reference missing {{{r}}}')
            for key in COLOR_LINKS:
                m = is_ref(ext.get(EXT, {}).get(key)) if isinstance(ext, dict) and isinstance(ext.get(EXT), dict) else None
                if m and m.group(1) in pool and pool[m.group(1)].get('$type') != 'color':
                    fail(f'{fname}: $extensions {key} of {path} must reference a color, not {m.group(1)}')
    for r, t, where in typed_refs:
        if r in pool and pool[r].get('$type') != t:
            fail(f'{where} needs a {t} but references {r} ({pool[r].get("$type")})')
    for fname, (_, tokens) in files.items():
        for path, tok in tokens.items():
            if is_ref(tok['$value']):
                try:
                    resolve(path, {**pool, **tokens})
                except (KeyError, ValueError) as e:
                    fail(f'{fname}: {path} does not resolve: {e}')

    # Each Phase file maps every slot to the same slot of its own period.
    for p in PHASES:
        for path, tok in files[f'phase.{p}.json'][1].items():
            want = f'color.phase-{p}.' + path.partition('.')[2].replace('.', '-')
            m = is_ref(tok['$value'])
            if not m or m.group(1) != want:
                fail(f'phase.{p}.json: {path} should reference {{{want}}}')

    typo_count = typography_checks(files)
    try:
        rows = contrast_checks(files)
    except (KeyError, ValueError, TypeError, IndexError, ArithmeticError) as e:  # reported above as a shape
        fail(f'contrast checks could not run: {e!r}')
        rows = []
    return report(files, rows, ref_count, typo_count)


def report(files, rows, ref_count=0, typo_count=0):
    token_count = sum(len(t) for _, t in files.values())
    print(f'{len(files)} files, {token_count} tokens, {ref_count} references, {typo_count} typography tokens')
    if rows:
        low = [r for r in rows if r[3] < r[4]]
        worst = min(rows, key=lambda r: r[3] / r[4])
        print(f'{len(rows)} contrast pairs checked (light and dark), {len(low)} below target')
        print(f'closest to its target: {worst[0]} {worst[1]} on {worst[2]} = {worst[3]:.2f}:1 (needs {worst[4]}:1)')
        for mode, fg, bg, ratio, need in low:
            fail(f'contrast {mode}: {fg} on {bg} is {ratio:.2f}:1, needs {need}:1')
    for e in errors:
        print('FAIL', e)
    print('OK' if not errors else f'{len(errors)} problem(s)')
    return 1 if errors else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as e:  # a malformed file the checks above didn't anticipate
        print(f'FAIL the checker stopped: {e!r}')
        sys.exit(1)
