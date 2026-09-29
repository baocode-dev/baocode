/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Source: textModelEditSource.ts at 6a598d4a13031703d483d103c1d934a36ad27971.
// Only sources emitted by this subset are represented; AI/cursor metadata, key
// serialization and EditDeltaInfo are not implemented.
class TextModelEditSource {
  const TextModelEditSource(this.source);
  final String source;

  @override
  String toString() => source;
}

abstract final class EditSources {
  static const setValue = TextModelEditSource('setValue');
  static const eolChange = TextModelEditSource('eolChange');
  static const applyEdits = TextModelEditSource('applyEdits');
}
