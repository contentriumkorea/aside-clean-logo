import struct
import hashlib
import json
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

from PIL import Image, ImageChops

ASSETS = Path(__file__).resolve().parents[1] / 'assets'


class IconAssets(unittest.TestCase):
    def test_official_bezier_coordinates_are_preserved(self):
        source = json.loads((ASSETS / 'source-path.json').read_text(encoding='utf-8'))
        self.assertEqual(hashlib.sha256(source['path'].encode()).hexdigest(), source['path_sha256'])
        for color in ('black', 'white'):
            tree = ET.parse(ASSETS / (color + '.svg'))
            original = tree.find('.//{http://www.w3.org/2000/svg}path[@id="original-bezier"]')
            self.assertEqual(original.attrib['d'], source['path'])

    def test_central_star_pixels_stay_exact(self):
        fixture = Path(__file__).parent / 'fixtures'
        original = Image.open(fixture / 'original-mark.png').convert('RGBA').getchannel('A')
        edited = Image.open(ASSETS / 'black.png').convert('RGBA').getchannel('A')
        protected = Image.open(fixture / 'star-lock.png').convert('RGBA').getchannel('A').point(lambda v: 255 if v == 255 else 0)
        self.assertIsNone(ImageChops.multiply(ImageChops.difference(original, edited), protected).getbbox())

    def test_thinning_never_adds_pixels_outside_original(self):
        original = Image.open(Path(__file__).parent / 'fixtures/original-mark.png').convert('RGBA').getchannel('A')
        edited = Image.open(ASSETS / 'black.png').convert('RGBA').getchannel('A')
        self.assertIsNone(ImageChops.subtract(edited, original).getbbox())

    def test_color_variants_keep_identical_geometry(self):
        black = Image.open(ASSETS / 'black.png').convert('RGBA')
        white = Image.open(ASSETS / 'white.png').convert('RGBA')
        self.assertEqual(black.size, white.size)
        self.assertEqual(black.width, black.height)
        self.assertIsNone(ImageChops.difference(black.getchannel('A'), white.getchannel('A')).getbbox())

    def test_background_is_transparent_and_framing_is_tight(self):
        im = Image.open(ASSETS / 'black.png').convert('RGBA')
        alpha = im.getchannel('A')
        self.assertEqual(alpha.getextrema(), (0, 255))
        bounds = alpha.point(lambda v: 255 if v >= 128 else 0).getbbox()
        for margin in (bounds[0], bounds[1], im.width - bounds[2], im.height - bounds[3]):
            self.assertLessEqual(margin, im.width * 0.02)

    def test_both_variants_are_flat_monochrome(self):
        for name, value in [('black', 0), ('white', 255)]:
            with self.subTest(color=name):
                im = Image.open(ASSETS / (name + '.png')).convert('RGBA')
                for band in im.split()[:3]:
                    self.assertEqual(band.getextrema(), (value, value))

    def test_windows_icons_have_expected_native_sizes_and_dib_frames(self):
        for name in ('black', 'white'):
            with self.subTest(color=name):
                path = ASSETS / (name + '.ico')
                with Image.open(path) as im:
                    self.assertTrue({(16, 16), (32, 32), (48, 48), (256, 256)}.issubset(im.ico.sizes()))
                    self.assertEqual(im.ico.getimage((32, 32)).getchannel('A').getextrema(), (0, 255))
                data = path.read_bytes()
                reserved, kind, count = struct.unpack_from('<HHH', data)
                self.assertEqual((reserved, kind), (0, 1))
                for i in range(count):
                    entry = struct.unpack_from('<BBBBHHII', data, 6 + 16 * i)
                    self.assertEqual(entry[4], 1)
                    self.assertEqual(entry[5], 32)
                    self.assertEqual(struct.unpack_from('<I', data, entry[7])[0], 40)


if __name__ == '__main__':
    unittest.main()
