/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// `window.createWebviewEditorInset`: an editor inset, a webview laid over a
// range of a text editor (docs previews, "Run this cell" buttons).
//
// Not implemented: an inset is a webview, and this app does not host
// webviews (the goal's section 五.15), nor the editor insets built on them.
// The actor keeps the two methods of `MainThreadEditorInsetsShape`
// unsupported, which the parity report counts; the extension's
// `window.createWebviewEditorInset` then rejects in the extension host.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadEditorInsets.ts (the shape and the
// webview it creates).
//
// Deviations: nothing of the actor is implemented (documented above).

import 'package:bao_exthost/bao_exthost.dart';

/// The `mainThreadEditorInsets` customer: both its methods answer
/// `RpcUnsupported`.
RpcActor mainThreadEditorInsetsActor() =>
    MainThreadEditorInsetsActor(const MainThreadEditorInsetsUnsupported());
