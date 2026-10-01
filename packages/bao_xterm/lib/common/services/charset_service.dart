// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/services/CharsetService.ts (c58ea36).

import '../types.dart';
import 'services.dart';

class CharsetService implements ICharsetService {
  @override
  ICharset? charset;
  @override
  int glevel = 0;

  List<ICharset?> _charsets = <ICharset?>[];

  @override
  List<ICharset?> get charsets {
    return _charsets;
  }

  @override
  void reset() {
    charset = null;
    _charsets = <ICharset?>[];
    glevel = 0;
  }

  @override
  void setgLevel(int g) {
    glevel = g;
    charset = g < _charsets.length ? _charsets[g] : null;
  }

  @override
  void setgCharset(int g, ICharset? charset) {
    // Upstream's sparse array write: slots below g read as undefined.
    while (_charsets.length <= g) {
      _charsets.add(null);
    }
    _charsets[g] = charset;
    if (glevel == g) {
      this.charset = charset;
    }
  }
}
