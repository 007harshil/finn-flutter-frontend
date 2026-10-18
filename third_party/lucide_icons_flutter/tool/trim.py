"""Regenerates lib/lucide_icons.dart from an upstream lucide_icons_flutter release,
keeping only the base `Lucide` family (no weight variants, no SVG doc previews).

Usage: python -I tool/trim.py <path to upstream lucide_icons_flutter>/lib/lucide_icons.dart
"""
import re, sys, pathlib

src = pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')
entry = re.compile(
    r"static const IconData (\w+) = const IconData\((\d+),\s*fontFamily: '(Lucide\d*)',\s*"
    r"fontPackage: 'lucide_icons_flutter'(,\s*matchTextDirection: true)?\);")
out = []
for name, code, family, rtl in entry.findall(src):
    if family != 'Lucide':
        continue
    extra = ', matchTextDirection: true' if rtl else ''
    out.append(f"  static const IconData {name} = IconData({code}, fontFamily: _f, fontPackage: _p{extra});")
assert len(out) > 1000, len(out)
header = '''// Trimmed from lucide_icons_flutter (MIT, see LICENSE) by tool/trim.py.
// Only the base `Lucide` font is kept: the upstream package also bundles six
// untree-shakeable weight fonts (~2.9 MB) that FiNN never uses.
// ignore_for_file: constant_identifier_names
library;

import 'package:flutter/widgets.dart';

/// Lucide Icons
@staticIconProvider
class LucideIcons {
  const LucideIcons._();

  static const _f = 'Lucide';
  static const _p = 'lucide_icons_flutter';

'''
pathlib.Path(__file__).resolve().parent.parent.joinpath('lib', 'lucide_icons.dart').write_text(
    header + '\n'.join(out) + '\n}\n', encoding='utf-8')
print(len(out), 'icons')
