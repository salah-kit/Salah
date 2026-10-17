"""Tests for check_tokens.py: each one breaks a copy of the tokens and expects the checker to say so.

Run from the repository root (-B keeps Python from writing a __pycache__ folder here):

    python3 -B -m unittest discover -s Design/tokens
"""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent


class CheckTokensTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        for path in [HERE / 'check_tokens.py', *HERE.glob('*.json')]:
            shutil.copy(path, self.dir)

    def run_checker(self):
        result = subprocess.run([sys.executable, '-B', '-I', str(self.dir / 'check_tokens.py')],
                                capture_output=True, text=True)
        return result.returncode, result.stdout + result.stderr

    def edit(self, name, change):
        path = self.dir / name
        doc = json.loads(path.read_text(encoding='utf-8'))
        change(doc)
        path.write_text(json.dumps(doc, indent=2, ensure_ascii=False), encoding='utf-8')

    def edit_typography(self, platform, path, change):
        def apply(doc):
            node = doc['typography'][platform]
            for key in path.split('.'):
                node = node[key]
            change(node, node['$extensions']['io.github.salah-kit'])
        self.edit(f'typography.{platform}.json', apply)

    def assert_fails(self, *expected):
        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.assertNotIn('Traceback', output)
        for text in expected:
            self.assertIn(text, output)

    def test_shipped_tokens_pass(self):
        code, output = self.run_checker()
        self.assertEqual(code, 0, output)
        self.assertEqual(output.splitlines()[-1], 'OK')

    # Typography against the type scale
    def test_style_with_another_styles_size_fails(self):
        def large_title_size(doc):
            body = doc['typography']['ios']['body']
            body['$value']['fontSize']['value'] = 34
            body['$value']['lineHeight'] = round(41 / 34, 4)
            body['$extensions']['io.github.salah-kit']['lineHeight']['value'] = 41
        self.edit('typography.ios.json', large_title_size)
        self.assert_fails('font size 34 differs from type-scale.ios.body.size')

    def test_line_height_must_match_the_type_scale(self):
        def taller(doc):
            body = doc['typography']['ios']['body']
            body['$value']['lineHeight'] = round(24 / 17, 4)
            body['$extensions']['io.github.salah-kit']['lineHeight']['value'] = 24
        self.edit('typography.ios.json', taller)
        self.assert_fails('line height 24 differs from type-scale.ios.body.line-height')

    def test_text_style_must_give_the_styles_size(self):
        # The watch countdown is 28 pt, the size of .title2; .title is 34 pt.
        def title(doc):
            doc['typography']['watchos']['numeric']['countdown']['$extensions']['io.github.salah-kit']['textStyle'] = 'title'
        self.edit('typography.watchos.json', title)
        self.assert_fails('Font.TextStyle.title gives 34 in type-scale.default.json')

    def test_text_style_must_scale_like_the_style(self):
        self.edit('type-scale.ax5.json', lambda doc: doc['type-scale']['watchos']['countdown']['size']['$value'].update(value=40))
        self.assert_fails('Font.TextStyle.title2 gives 36 in type-scale.ax5.json')

    def test_type_scale_code_must_match_the_style(self):
        def scaled(doc):
            for mode_file_entry in ('size', 'line-height'):
                entry = doc['type-scale']['watchos']['countdown'][mode_file_entry]
                entry['$extensions']['io.github.salah-kit']['swift'] = '@ScaledMetric(relativeTo: .title2)'
        for mode in ('default', 'xxxlarge', 'ax3', 'ax5'):
            self.edit(f'type-scale.{mode}.json', scaled)
        self.assert_fails("has swift '@ScaledMetric(relativeTo: .title2)'; the style needs 'Font.TextStyle.title2'")

    def test_capped_style_must_stop_growing(self):
        self.edit('type-scale.ax5.json', lambda doc: doc['type-scale']['ios']['countdown-display']['size']['$value'].update(value=109.33))
        self.assert_fails('stops growing at accessibility3')

    def test_type_scale_must_not_shrink(self):
        self.edit('type-scale.ax5.json', lambda doc: doc['type-scale']['ios']['body']['size']['$value'].update(value=30))
        self.assert_fails('type-scale.ios.body.size: shrinks as the text size grows')

    # The file inventory
    def test_missing_mode_file_fails(self):
        (self.dir / 'layout.watchos.json').unlink()
        self.assert_fails('missing layout.watchos.json')

    def test_missing_typography_file_fails(self):
        (self.dir / 'typography.watchos.json').unlink()
        self.assert_fails('missing typography.watchos.json')

    def test_unexpected_file_fails(self):
        shutil.copy(self.dir / 'layout.ios.json', self.dir / 'layout.visionos.json')
        self.assert_fails('unexpected file layout.visionos.json')

    # References and file shape
    def test_repeated_key_fails(self):
        path = self.dir / 'motion.default.json'
        text = path.read_text(encoding='utf-8')
        path.write_text(text.replace('"$type": "duration"', '"$type": "duration", "$type": "duration"', 1), encoding='utf-8')
        self.assert_fails("motion.default.json: the key '$type' appears twice")

    def test_reference_inside_a_composite_needs_the_right_type(self):
        def dimension_color(doc):
            doc['effects']['elevation']['raised']['$value'][0]['color'] = '{dimension.space.2}'
        self.edit('effects.json', dimension_color)
        self.assert_fails('needs a color but references dimension.space.2 (dimension)')

    def test_phase_slot_must_match(self):
        self.edit('phase.isha.json', lambda doc: doc['phase'].update(tint={**doc['phase']['tint'], '$value': '{color.phase-isha.sky-top}'}))
        self.assert_fails('phase.isha.json: phase.tint should reference {color.phase-isha.tint}')

    def test_malformed_extension_reference_fails(self):
        def bad(doc):
            doc['effects']['material']['thin']['$extensions']['io.github.salah-kit']['tint'] = '{color.glass fill}'
        self.edit('effects.json', bad)
        self.assert_fails("malformed reference in '{color.glass fill}'")

    def test_extensions_must_match_across_modes(self):
        def rename(doc):
            doc['color']['bg']['primary']['$extensions']['io.github.salah-kit']['swift'] = 'SalahColor.oops'
        self.edit('color.dark.json', rename)
        self.assert_fails('color.dark.json differs from color.light.json', "$extensions changes ['color.bg.primary']")

    def test_malformed_values_are_reported(self):
        self.edit('primitives.json', lambda doc: doc['primitives']['gold']['400']['$value'].update(alpha='0.5'))
        self.edit('typography.ios.json', lambda doc: doc['typography']['ios']['body']['$value'].update(fontSize='{type-scale.ios.body.size}'))
        self.assert_fails('alpha must be a number in 0...1', 'fontSize and lineHeight must be literal values')

    def test_text_style_line_height_follows_the_style(self):
        self.edit('type-scale.ax5.json', lambda doc: doc['type-scale']['ios']['countdown']['line-height']['$value'].update(value=90))
        self.assert_fails('Font.TextStyle.title gives 68 in type-scale.ax5.json (type-scale.ios.title-1.line-height)')

    def test_scaled_size_grows_with_its_text_style(self):
        self.edit('type-scale.xxxlarge.json', lambda doc: doc['type-scale']['ios']['countdown-large']['size']['$value'].update(value=45))
        self.assert_fails('type-scale.ios.countdown-large.size is 45 in type-scale.xxxlarge.json; scaling with .largeTitle gives about 51.8')

    def test_macos_sizes_never_change(self):
        self.edit('type-scale.ax5.json', lambda doc: doc['type-scale']['macos']['body']['size']['$value'].update(value=15))
        self.assert_fails('type-scale.macos.body.size: macOS has no Dynamic Type')

    def test_one_way_of_sizing(self):
        self.edit_typography('ios', 'body', lambda tok, ext: ext.update(scaledRelativeTo='body'))
        self.assert_fails("needs exactly one of textStyle, scaledRelativeTo and fixedSize, has ['textStyle', 'scaledRelativeTo']")

    def test_fixed_size_is_for_macos(self):
        def fixed(tok, ext):
            del ext['textStyle']
            ext['fixedSize'] = True
        self.edit_typography('ios', 'body', fixed)
        self.assert_fails('typography.ios.body: fixedSize is for macOS')

    def test_sizing_must_name_a_text_style(self):
        self.edit_typography('ios', 'numeric.countdown-display', lambda tok, ext: ext.update(scaledRelativeTo='hugeTitle'))
        self.edit_typography('ios', 'body', lambda tok, ext: ext.update(textStyle=['body']))
        self.assert_fails("scaledRelativeTo 'hugeTitle' is not a Font.TextStyle in the ios type scale",
                          "textStyle ['body'] is not a Font.TextStyle in the ios type scale")

    def test_size_limit_must_be_a_larger_dynamic_type_size(self):
        self.edit_typography('ios', 'numeric.countdown-display', lambda tok, ext: ext.update(maxDynamicTypeSize='medium'))
        self.edit_typography('ios', 'numeric.countdown-large', lambda tok, ext: ext.update(maxDynamicTypeSize='huge'))
        self.assert_fails('maxDynamicTypeSize medium is below the default text size',
                          "maxDynamicTypeSize 'huge' is not a DynamicTypeSize")

    def test_size_limit_is_only_for_scaled_sizes(self):
        self.edit_typography('ios', 'body', lambda tok, ext: ext.update(maxDynamicTypeSize='xLarge'))
        self.assert_fails('typography.ios.body: maxDynamicTypeSize applies only to a scaledRelativeTo size')

    def test_type_scale_link_must_name_one_style(self):
        self.edit_typography('ios', 'body', lambda tok, ext: ext['typeScale'].update(lineHeight='{type-scale.ios.callout.line-height}'))
        self.assert_fails("typography.ios.body: typeScale must name type-scale.ios.<style>.size and the same style's line-height")

    def test_typography_needs_its_figma_style_and_point_line_height(self):
        def strip(tok, ext):
            del ext['figmaStyle']
            tok['$value']['lineHeight'] = 1.5
        self.edit_typography('ios', 'body', strip)
        self.assert_fails('typography.ios.body has no figmaStyle', 'typography.ios.body: lineHeight ratio does not match 22 pt')

    def test_stand_in_fonts_never_ship(self):
        self.edit_typography('ios', 'body', lambda tok, ext: tok['$value'].update(fontFamily='Inter'))
        self.assert_fails('typography.ios.body uses the Figma stand-in font Inter')

    def test_color_link_must_be_a_color(self):
        def link(doc):
            doc['effects']['material']['thin']['$extensions']['io.github.salah-kit']['reduceTransparencyFallback'] = '{dimension.space.2}'
        self.edit('effects.json', link)
        self.assert_fails('reduceTransparencyFallback of effects.material.thin must reference a color, not dimension.space.2')

    def test_types_and_descriptions_are_required(self):
        def strip(doc):
            doc['dimension']['space']['2']['$type'] = 'size'
            del doc['dimension']['space']['4']['$description']
        self.edit('dimension.json', strip)
        self.assert_fails("dimension.json: dimension.space.2: unknown $type 'size'", 'dimension.json: dimension.space.4: $description must be text, got None')

    def test_hex_must_match_its_components(self):
        self.edit('primitives.json', lambda doc: doc['primitives']['gold']['50']['$value'].update(hex='#000000'))
        self.assert_fails('primitives.json: primitives.gold.50: hex #000000 does not match components')

    def test_hex_rounds_halves_up(self):
        # 0.3 × 255 = 76.5, which Figma and CSS write as 4d.
        self.edit('primitives.json', lambda doc: doc['primitives']['gold']['50']['$value'].update(components=[0.3, 0.3, 0.3], hex='#4d4d4d'))
        code, output = self.run_checker()
        self.assertEqual(code, 0, output)

    def test_references_must_resolve_without_cycles(self):
        def loop(doc):
            doc['color']['label']['primary']['$value'] = '{color.label.secondary}'
            doc['color']['label']['secondary']['$value'] = '{color.label.primary}'
            doc['color']['label']['tertiary']['$value'] = '{primitives.nope}'
        self.edit('color.light.json', loop)
        self.assert_fails('color.light.json: color.label.primary does not resolve: cycle',
                          'color.light.json: color.label.tertiary references missing {primitives.nope}')

    def test_a_token_is_defined_once(self):
        def again(doc):
            doc['color'] = {'bg': {'primary': {'$type': 'dimension', '$value': {'value': 1, 'unit': 'px'}, '$description': 'Twice.'}}}
        self.edit('dimension.json', again)
        self.assert_fails('dimension.json: color.bg.primary is also defined in color.light.json')

    def test_names_have_no_dots_or_braces(self):
        def names(doc):
            space = doc['dimension']['space']
            space['x.y'] = space['2']
            space['{z}'] = space['4']
        self.edit('dimension.json', names)
        self.assert_fails('dimension.json: dimension.space.x.y: names may not contain braces or dots',
                          'dimension.json: dimension.space.{z}: names may not contain braces or dots')

    def test_unreadable_files_are_reported(self):
        (self.dir / 'motion.default.json').write_bytes(b'\xff\xfe{}')
        (self.dir / 'motion.reduce-motion.json').write_text('[]', encoding='utf-8')
        (self.dir / 'layout.ios.json').write_text('{"layout": ', encoding='utf-8')
        self.assert_fails('motion.default.json: not UTF-8', 'motion.reduce-motion.json: the root: expected an object',
                          'layout.ios.json: invalid JSON')

    def test_size_limit_between_type_scale_files(self):
        # No file stands for accessibility4, so the AX5 file only has to keep growing.
        self.edit_typography('ios', 'numeric.countdown-large', lambda tok, ext: ext.update(maxDynamicTypeSize='accessibility4'))
        code, output = self.run_checker()
        self.assertEqual(code, 0, output)
        # Held at xLarge, the xxxLarge, AX3 and AX5 files all draw at one size.
        self.edit_typography('ios', 'numeric.countdown-large', lambda tok, ext: ext.update(maxDynamicTypeSize='xLarge'))
        self.assert_fails('stops growing at xLarge, so type-scale.ios.countdown-large.size in type-scale.ax3.json must equal type-scale.xxxlarge.json')

    def test_scaled_line_height_grows_with_its_text_style(self):
        self.edit('type-scale.ax3.json', lambda doc: doc['type-scale']['ios']['countdown-display']['line-height']['$value'].update(value=120))
        self.assert_fails('type-scale.ios.countdown-display.line-height is 120 in type-scale.ax3.json; scaling with .largeTitle gives about 104.0')

    def test_line_height_code_ends_in_leading(self):
        def drop(doc):
            doc['type-scale']['ios']['body']['line-height']['$extensions']['io.github.salah-kit']['swift'] = 'Font.TextStyle.body'
        for mode in ('default', 'xxxlarge', 'ax3', 'ax5'):
            self.edit(f'type-scale.{mode}.json', drop)
        self.assert_fails("type-scale.ios.body.line-height has swift 'Font.TextStyle.body'; the style needs 'Font.TextStyle.body (leading)'")

    def test_fixed_size_code_names_its_size(self):
        def decimal(doc):
            for entry in ('size', 'line-height'):
                doc['type-scale']['macos']['countdown-large'][entry]['$extensions']['io.github.salah-kit']['swift'] = 'Font.system(size: 30.0)'
        for mode in ('default', 'xxxlarge', 'ax3', 'ax5'):
            self.edit(f'type-scale.{mode}.json', decimal)
        self.edit_typography('macos', 'numeric.countdown-large', lambda tok, ext: ext.update(fixedSize='yes'))
        self.assert_fails("type-scale.macos.countdown-large.size has swift 'Font.system(size: 30.0)'; the style needs 'Font.system(size: 30)'",
                          "typography.macos.numeric.countdown-large: fixedSize must be true, got 'yes'")

    def test_fixed_size_code_ignores_a_trailing_zero(self):
        self.edit_typography('macos', 'numeric.countdown-large', lambda tok, ext: tok['$value']['fontSize'].update(value=30.0))
        code, output = self.run_checker()
        self.assertEqual(code, 0, output)

    def test_mode_files_define_the_same_tokens(self):
        self.edit('layout.watchos.json', lambda doc: doc['layout']['margin'].pop('screen'))
        self.edit('motion.reduce-motion.json', lambda doc: doc['motion']['press']['duration'].update({'$type': 'number', '$value': 120}))
        self.assert_fails("layout.watchos.json differs from layout.ios.json: missing ['layout.margin.screen']",
                          "motion.reduce-motion.json differs from motion.default.json: missing [] extra [] type changes ['motion.press.duration']")

    def test_value_shapes(self):
        self.edit('dimension.json', lambda doc: doc['dimension']['space']['2']['$value'].update(unit='pt'))
        self.edit('motion.default.json', lambda doc: doc['motion']['press']['duration']['$value'].update(unit='min'))
        def colors(doc):
            doc['primitives']['neutral']['white']['$value'].update(components=[1, 1])
            doc['primitives']['gold']['50']['$value'].update(hex=doc['primitives']['gold']['50']['$value']['hex'].upper())
        self.edit('primitives.json', colors)
        self.assert_fails("dimension.json: dimension.space.2: expected {value, unit} with unit in ('px', 'rem')",
                          "motion.default.json: motion.press.duration: expected {value, unit} with unit in ('ms', 's')",
                          'primitives.json: primitives.neutral.white: components must be three numbers in 0...1',
                          'primitives.json: primitives.gold.50: hex must be #rrggbb', 'contrast checks could not run')
        self.assertNotIn('the checker stopped', self.run_checker()[1])

    def test_typography_and_shadow_shapes(self):
        def fonts(tok, ext):
            tok['$value'].update(fontFamily=12, fontWeight=0)
        self.edit_typography('ios', 'body', fonts)
        self.edit_typography('ios', 'headline', lambda tok, ext: tok['$value'].pop('letterSpacing'))
        self.edit_typography('ios', 'callout', lambda tok, ext: tok['$value'].update(lineHeight='tall'))
        self.edit('effects.json', lambda doc: doc['effects']['elevation']['raised']['$value'][0].pop('blur'))
        self.assert_fails('typography.ios.body.fontFamily: expected a font family name',
                          'typography.ios.body.fontWeight: expected a weight in 1...1000',
                          "typography.ios.headline: typography needs ['fontFamily', 'fontSize', 'fontWeight', 'letterSpacing', 'lineHeight']",
                          'typography.ios.callout.lineHeight: expected a number',
                          'effects.elevation.raised[0]: shadow needs color, offsetX, offsetY, blur and spread')

    def test_extension_references_must_resolve(self):
        self.edit('effects.json', lambda doc: doc['effects']['material']['thin']['$extensions']['io.github.salah-kit'].update(tint='{color.glass.nope}'))
        self.assert_fails('effects.json: $extensions of effects.material.thin reference missing {color.glass.nope}')

    def test_one_report_per_wrongly_typed_alias(self):
        self.edit('color.light.json', lambda doc: doc['color']['label']['primary'].update({'$value': '{dimension.space.2}'}))
        code, output = self.run_checker()
        self.assertEqual(code, 1, output)
        self.assertEqual(output.count('color.label.primary needs a color but references dimension.space.2'), 1, output)

    def test_type_must_be_a_name(self):
        self.edit('dimension.json', lambda doc: doc['dimension']['space']['2'].update({'$type': ['dimension']}))
        self.assert_fails("dimension.json: dimension.space.2: unknown $type ['dimension']")

    def test_description_must_be_text(self):
        def describe(doc):
            doc['dimension']['space']['2']['$description'] = ['Two points.']
            doc['dimension']['space']['4']['$description'] = '   '
        self.edit('dimension.json', describe)
        self.assert_fails("dimension.json: dimension.space.2: $description must be text, got ['Two points.']",
                          "dimension.json: dimension.space.4: $description must be text, got '   '")

    def test_numbers_must_be_finite(self):
        # json.loads reads 1e400 as infinity without complaint.
        def huge(doc):
            doc['dimension']['space']['2']['$value']['value'] = 0.123456789
        self.edit('dimension.json', huge)
        path = self.dir / 'dimension.json'
        path.write_text(path.read_text(encoding='utf-8').replace('0.123456789', '1e400'), encoding='utf-8')
        self.assert_fails("dimension.json: dimension.space.2: expected {value, unit} with unit in ('px', 'rem'), got {'value': inf")

    def test_impossible_colors_do_not_stop_the_contrast_check(self):
        # A component of -0.646 gives a luminance of -0.05, which would divide the contrast ratio by zero.
        self.edit('primitives.json', lambda doc: doc['primitives']['neutral']['white']['$value'].update(components=[-0.646, -0.646, -0.646]))
        self.assert_fails('primitives.json: primitives.neutral.white: components must be three numbers in 0...1',
                          'contrast checks could not run')
        self.assertNotIn('the checker stopped', self.run_checker()[1])

    def test_nan_is_not_json(self):
        path = self.dir / 'dimension.json'
        text = path.read_text(encoding='utf-8')
        doc = json.loads(text)
        doc['dimension']['space']['2']['$value']['value'] = float('nan')
        path.write_text(json.dumps(doc), encoding='utf-8')  # json.dumps writes NaN, which JSON doesn't allow
        self.assert_fails('dimension.json: invalid JSON: NaN is not a JSON number')

    # Contrast
    def test_low_contrast_text_fails(self):
        self.edit('color.light.json', lambda doc: doc['color']['label'].update(secondary={**doc['color']['label']['secondary'], '$value': '{primitives.ink.light-18}'}))
        self.assert_fails('contrast light: label/secondary on bg/primary')

    def test_status_and_on_accent_pairs_are_checked(self):
        def faint(doc):
            doc['color']['status']['error']['$value'] = '{primitives.gold.100}'
            doc['color']['label']['on-accent']['$value'] = '{primitives.neutral.white}'
        self.edit('color.light.json', faint)
        self.assert_fails('contrast light: status/error on bg/primary', 'contrast light: label/on-accent on accent/fill')

    def test_phase_tint_and_accent_marks_are_checked(self):
        def faint(doc):
            doc['color']['phase-isha']['tint']['$value'] = '{primitives.night.50}'
            doc['color']['accent']['default']['$value'] = '{primitives.gold.50}'
        self.edit('color.light.json', faint)
        self.assert_fails('contrast light: phase-isha/tint on', 'contrast light: accent/default on')

    def test_text_on_a_chip_is_checked(self):
        self.edit('color.light.json', lambda doc: doc['color']['fill'].update(tertiary={**doc['color']['fill']['tertiary'], '$value': '{primitives.fill.light-20}'}))
        self.assert_fails('contrast light: status/warning on fill/tertiary over phase-maghrib/sky-bottom')

    # Increase Contrast
    def edit_increased(self, mode, group, name, value):
        self.edit(f'color.{mode}-increased-contrast.json', lambda doc: doc['color'][group][name].update({'$value': value}))

    def test_increased_contrast_text_needs_7_to_1(self):
        # gold.700 is the standard accent text: 4.5:1 or more on every surface, but under 7:1 on white.
        self.edit_increased('light', 'accent', 'text', '{primitives.gold.700}')
        self.assert_fails('contrast light-increased-contrast: accent/text on bg/primary is 6.', 'needs 7.0:1')

    def test_increased_contrast_graphics_need_4_5_to_1(self):
        self.edit_increased('light', 'accent', 'default', '{primitives.gold.600}')
        self.assert_fails('contrast light-increased-contrast: accent/default on bg/secondary is 3.83:1, needs 4.5:1')

    def test_dark_increased_contrast_is_checked(self):
        self.edit_increased('dark', 'status', 'info', '{primitives.system.blue.dark}')
        # 5.47:1 meets the standard target, so only the Increase Contrast one fails it.
        self.assert_fails('contrast dark-increased-contrast: status/info on bg/secondary is 5.47:1, needs 7.0:1')

    def test_exception_must_give_its_recorded_ratio(self):
        self.edit_increased('light', 'status', 'warning', '{primitives.system.orange.light}')
        self.assert_fails('contrast light-increased-contrast: the exception for status/warning on bg/secondary records 6.54:1, but the pair is')

    def test_exception_keeps_the_standard_target(self):
        self.edit_increased('light', 'label', 'secondary', '{primitives.ink.light-62}')
        self.assert_fails('contrast light-increased-contrast: label/secondary on fill/tertiary over bg/grouped is', 'needs 4.5:1')

    def test_exception_that_reaches_the_target_must_go(self):
        self.edit_increased('light', 'label', 'secondary', '{primitives.neutral.black}')
        self.assert_fails('contrast light-increased-contrast: label/secondary on fill/tertiary over bg/grouped reaches 7.0:1 now; remove its exception')

    def test_exception_must_name_a_checked_pair(self):
        path = self.dir / 'check_tokens.py'
        text = path.read_text(encoding='utf-8')
        path.write_text(text.replace('CONTRAST_EXCEPTIONS = {', "CONTRAST_EXCEPTIONS = {('dark-increased-contrast', 'label/primary', 'bg/nowhere'): 9.99,", 1), encoding='utf-8')
        self.assert_fails("contrast exception for a pair the checker does not check: ('dark-increased-contrast', 'label/primary', 'bg/nowhere')")

    def test_increased_contrast_never_weakens_a_color(self):
        # A fainter separator than the standard one, though no contrast pair covers separators.
        self.edit_increased('light', 'separator', 'default', '{primitives.ink.light-18}')
        self.assert_fails('light-increased-contrast: separator/default stands out less from bg/primary (1.37:1) than in light (1.71:1)')

    def test_increased_contrast_files_define_the_same_tokens(self):
        self.edit('color.dark-increased-contrast.json', lambda doc: doc['color']['label'].pop('quaternary'))
        self.assert_fails('color.dark-increased-contrast.json differs from color.light.json')


if __name__ == '__main__':
    unittest.main()
