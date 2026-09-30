/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/base/common/jsonErrorMessages.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. The English messages stand in
// for `nls.localize`.

import 'json.dart';

String getParseErrorMessage(int errorCode) {
  switch (errorCode) {
    case ParseErrorCode.invalidSymbol:
      return 'Invalid symbol';
    case ParseErrorCode.invalidNumberFormat:
      return 'Invalid number format';
    case ParseErrorCode.propertyNameExpected:
      return 'Property name expected';
    case ParseErrorCode.valueExpected:
      return 'Value expected';
    case ParseErrorCode.colonExpected:
      return 'Colon expected';
    case ParseErrorCode.commaExpected:
      return 'Comma expected';
    case ParseErrorCode.closeBraceExpected:
      return 'Closing brace expected';
    case ParseErrorCode.closeBracketExpected:
      return 'Closing bracket expected';
    case ParseErrorCode.endOfFileExpected:
      return 'End of file expected';
    default:
      return '';
  }
}
