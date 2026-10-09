/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// VS Code's notifications: toasts at the bottom right, the status bar's
// bell, and the notification center.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/common/notifications.ts (stickiness, expansion, the
// message limit, replacing a same notification),
// src/vs/workbench/browser/parts/notifications/{notificationsToasts,
// notificationsViewer,notificationsCenter,notificationsStatus,
// notificationsActions}.ts with media/{notificationsToasts,notificationsList,
// notificationsCenter}.css, the Modern UI's
// contrib/modernUI/browser/media/notificationsDialogs.css, and the color
// theme's `notification*` colors (common/theme.ts).
//
// Progress (`INotificationProgress`: infinite, or worked of a total) is
// drawn as notificationsViewer.ts draws it: a 2px bar along the bottom of
// the notification.
//
// Deviations: no Do Not Disturb, no positions but the bottom
// right, and toasts are not limited to 3 per 800 ms (only to 3 shown).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/codicons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import 'ide_button.dart';
import 'ide_hover.dart';
import 'ide_menu.dart';
import 'ide_status_bar.dart';

/// The color theme's `notification*` colors.
abstract final class IdeNotificationColors {
  static Color get background => themeColors['notifications.background'];
  static Color get foreground => themeColors['notifications.foreground'];

  /// Between the center's notifications.
  static Color get border => themeColors['notifications.border'];

  /// Around a toast, where the theme has one.
  static Color? get toastBorder => themeColors.get('notificationToast.border');

  /// Around the center: `editorWidget.border` where the theme has none.
  static Color get centerBorder =>
      themeColors.get('notificationCenter.border') ??
      themeColors['editorWidget.border'];
  static Color get centerHeaderBackground =>
      themeColors['notificationCenterHeader.background'];

  /// The workbench's `foreground` where the theme has none.
  static Color get centerHeaderForeground =>
      themeColors.get('notificationCenterHeader.foreground') ??
      themeColors['foreground'];
  static Color get link => themeColors['notificationLink.foreground'];
  static Color get infoIcon => themeColors['notificationsInfoIcon.foreground'];
  static Color get warningIcon =>
      themeColors['notificationsWarningIcon.foreground'];
  static Color get errorIcon =>
      themeColors['notificationsErrorIcon.foreground'];

  /// The source (Modern UI).
  static Color get description => themeColors['descriptionForeground'];
}

enum IdeSeverity { info, warning, error }

/// A button of a notification; [menu] makes it a split button.
class IdeNotificationAction {
  const IdeNotificationAction(this.label, this.run, {this.menu});

  final String label;
  final VoidCallback run;
  final List<IdeNotificationAction>? menu;
}

/// A notification's progress (`INotificationProgressProperties`): infinite,
/// or [worked] of [total].
class IdeNotificationProgress {
  const IdeNotificationProgress.infinite() : total = null, worked = 0;
  const IdeNotificationProgress(this.worked, {this.total = 100});

  /// Null for an infinite one.
  final double? total;
  final double worked;

  bool get infinite => total == null;
}

/// One notification, shown as a toast and kept in the center until closed.
class IdeNotification {
  IdeNotification._(
    this.severity,
    String message, {
    this.source,
    this.primary = const [],
    this.secondary = const [],
    this.onClose,
    this.stayOpen = false,
    this.progress,
  }) : _message = _limit(message),
       expanded = primary.isNotEmpty;

  static const _maxMessageLength = 1000;

  static String _limit(String message) => message.length > _maxMessageLength
      ? '${message.substring(0, _maxMessageLength)}...'
      : message;

  final IdeSeverity severity;
  String _message;
  String get message => _message;

  /// Its progress bar; null for none ([IdeNotifications.update] sets it).
  IdeNotificationProgress? progress;

  /// Who sent it (`Source: …`).
  final String? source;

  /// Its buttons, the first the primary one.
  final List<IdeNotificationAction> primary;

  /// Under its gear (More Actions...).
  final List<IdeNotificationAction> secondary;

  /// Called once it is closed, whether by an action or the user.
  final VoidCallback? onClose;

  /// Asked to stay as a toast until closed.
  final bool stayOpen;

  /// Whether its message wraps and its buttons show.
  bool expanded;

  bool get hasActions => primary.isNotEmpty || secondary.isNotEmpty;

  /// Only one without actions can be collapsed again.
  bool get canCollapse => !hasActions;

  /// Kept as a toast until closed: when asked, errors with actions, and
  /// ones the user expanded.
  bool get sticky =>
      stayOpen ||
      (hasActions && severity == IdeSeverity.error) ||
      (!hasActions && expanded);

  bool _sameAs(IdeNotification other) =>
      other.severity == severity &&
      other.message == message &&
      other.source == source;
}

/// The notifications of a workbench.
class IdeNotifications extends ChangeNotifier {
  /// `PURGE_TIMEOUT`: how long a toast that is not sticky stays.
  static const purgeTimeouts = {
    IdeSeverity.info: Duration(milliseconds: 10000),
    IdeSeverity.warning: Duration(milliseconds: 12000),
    IdeSeverity.error: Duration(milliseconds: 15000),
  };

  /// `MAX_NOTIFICATIONS`: toasts shown at once.
  static const maxToasts = 3;

  final List<IdeNotification> _all = [];
  final Set<IdeNotification> _toasts = {};
  final Map<IdeNotification, Timer> _timers = {};
  final Set<IdeNotification> _hovered = {};
  int _unread = 0;
  bool _centerVisible = false;
  bool _disposed = false;

  /// Newest first.
  List<IdeNotification> get notifications => List.unmodifiable(_all);

  /// The toasts showing, newest last; none while the center is open.
  List<IdeNotification> get toasts => _centerVisible
      ? const []
      : _all.where(_toasts.contains).take(maxToasts).toList().reversed.toList();

  /// Added since the center was last open.
  int get unread => _unread;
  bool get centerVisible => _centerVisible;

  /// Shows a notification; one the same as another replaces it. A [silent]
  /// one (upstream's `NotificationPriority.SILENT`) is only in the center,
  /// counted as unread, with no toast.
  IdeNotification notify(
    IdeSeverity severity,
    String message, {
    String? source,
    List<IdeNotificationAction> primary = const [],
    List<IdeNotificationAction> secondary = const [],
    bool sticky = false,
    bool silent = false,
    VoidCallback? onClose,
    IdeNotificationProgress? progress,
  }) {
    final notification = IdeNotification._(
      severity,
      message,
      source: source,
      primary: primary,
      secondary: secondary,
      stayOpen: sticky,
      onClose: onClose,
      progress: progress,
    );
    if (_disposed) return notification;
    for (final same in _all.where(notification._sameAs).toList()) {
      _remove(same);
    }
    _all.insert(0, notification);
    if (!_centerVisible) {
      _unread++;
      if (!silent) {
        _toasts.add(notification);
        _schedulePurge(notification);
      }
    }
    notifyListeners();
    return notification;
  }

  void _schedulePurge(IdeNotification notification) {
    _timers.remove(notification)?.cancel();
    _timers[notification] = Timer(purgeTimeouts[notification.severity]!, () {
      _timers.remove(notification);
      if (!_toasts.contains(notification)) return;
      // Sticky ones, and ones under the mouse, stay.
      if (notification.sticky || _hovered.contains(notification)) {
        _schedulePurge(notification);
      } else {
        hideToast(notification);
      }
    });
  }

  /// The pointer is over [notification]'s toast.
  void hover(IdeNotification notification, bool hovered) {
    if (hovered) {
      _hovered.add(notification);
    } else {
      _hovered.remove(notification);
    }
  }

  /// Whether [notification] is still shown (as a toast or in the center).
  bool isOpen(IdeNotification notification) => _all.contains(notification);

  /// Whether [notification] shows as a toast now.
  bool isToast(IdeNotification notification) =>
      toasts.contains(notification);

  /// Changes [notification]'s message (`updateMessage`) or progress
  /// (`progress.total/worked/infinite`); [clearProgress] removes its bar.
  void update(
    IdeNotification notification, {
    String? message,
    IdeNotificationProgress? progress,
    bool clearProgress = false,
  }) {
    if (!_all.contains(notification)) return;
    if (message != null) notification._message = IdeNotification._limit(message);
    if (progress != null || clearProgress) notification.progress = progress;
    if (!_disposed) notifyListeners();
  }

  /// Hides [notification]'s toast; it stays in the center.
  void hideToast(IdeNotification notification) {
    _timers.remove(notification)?.cancel();
    if (_toasts.remove(notification) && !_disposed) notifyListeners();
  }

  void _remove(IdeNotification notification) {
    _all.remove(notification);
    _toasts.remove(notification);
    _hovered.remove(notification);
    _timers.remove(notification)?.cancel();
    notification.onClose?.call();
  }

  /// Clears [notification] (its close button, or once an action ran).
  void close(IdeNotification notification) {
    if (!_all.contains(notification)) return;
    _remove(notification);
    if (!_disposed) notifyListeners();
  }

  void toggleExpanded(IdeNotification notification) {
    notification.expanded = !notification.expanded;
    notifyListeners();
  }

  void clearAll() {
    for (final notification in [..._all]) {
      _remove(notification);
    }
    notifyListeners();
  }

  void toggleCenter() {
    _centerVisible = !_centerVisible;
    if (_centerVisible) {
      _unread = 0;
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      _toasts.clear();
    }
    notifyListeners();
  }

  void hideCenter() {
    if (_centerVisible) toggleCenter();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

/// The status bar's bell: `bell-dot` with unread notifications; opens and
/// closes the center. Its tooltip is in [l10n]'s language (English when
/// null).
IdeStatusBarItem ideNotificationsStatusItem(
  IdeNotifications notifications, {
  AppLocalizations? l10n,
}) {
  final strings = l10n ?? englishLocalizations;
  final count = notifications.unread;
  return IdeStatusBarItem(
    '',
    icon: count > 0 ? Codicons.bellDot : Codicons.bell,
    tooltip: notifications.centerVisible
        ? strings.notificationsHide
        : notifications.notifications.isEmpty
        ? strings.notificationsNone
        : count == 0
        ? strings.notificationsNoNew
        : strings.notificationsNew(count),
    onTap: notifications.toggleCenter,
  );
}

/// The toasts, for the bottom right of the workbench (8px from the right,
/// 36px from the bottom in the Modern UI).
class IdeNotificationToasts extends StatelessWidget {
  const IdeNotificationToasts({super.key, required this.notifications});

  final IdeNotifications notifications;

  /// `MAX_WIDTH`.
  static const maxWidth = 450.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notifications,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final notification in notifications.toasts)
            Padding(
              key: ObjectKey(notification),
              padding: const EdgeInsets.only(top: 4),
              child: _Toast(
                width: math.min(maxWidth, constraints.maxWidth),
                child: MouseRegion(
                  onEnter: (_) => notifications.hover(notification, true),
                  onExit: (_) => notifications.hover(notification, false),
                  child: _NotificationItem(
                    notification: notification,
                    notifications: notifications,
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A toast: slides up and fades in over 300 ms, `ease-out`.
class _Toast extends StatelessWidget {
  const _Toast({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final border = IdeNotificationColors.toastBorder;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, t, child) => FractionalTranslation(
        translation: Offset(0, 1 - t),
        child: Opacity(opacity: t, child: child),
      ),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: IdeNotificationColors.background,
          border: border == null ? null : Border.all(color: border),
          borderRadius: BorderRadius.circular(4),
          boxShadow: IdeHoverColors.shadow,
        ),
        child: child,
      ),
    );
  }
}

/// The notification center: a 35px header and the notifications, newest
/// first, above the bell. Showing it takes the focus, and hiding it gives
/// the focus back (`NotificationsCenter.show`, `hide`).
class IdeNotificationsCenter extends StatefulWidget {
  const IdeNotificationsCenter({super.key, required this.notifications});

  final IdeNotifications notifications;

  @override
  State<IdeNotificationsCenter> createState() => _IdeNotificationsCenterState();
}

class _IdeNotificationsCenterState extends State<IdeNotificationsCenter> {
  final _focus = FocusNode(debugLabel: 'notifications center');
  FocusNode? _focusBefore;
  bool _visible = false;

  IdeNotifications get notifications => widget.notifications;

  @override
  void initState() {
    super.initState();
    notifications.addListener(_changed);
    _changed();
  }

  @override
  void didUpdateWidget(IdeNotificationsCenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifications == notifications) return;
    oldWidget.notifications.removeListener(_changed);
    notifications.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    notifications.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    final visible = notifications.centerVisible;
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
      _focusBefore = FocusManager.instance.primaryFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _visible) _focus.requestFocus();
      });
    } else {
      final before = _focusBefore;
      _focusBefore = null;
      if (_focus.hasFocus && before != null && before.context != null) {
        before.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: notifications,
    builder: (context, _) {
      if (!notifications.centerVisible) return const SizedBox.shrink();
      final all = notifications.notifications;
      return LayoutBuilder(
        builder: (context, constraints) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape):
                notifications.hideCenter,
          },
          child: Focus(
            focusNode: _focus,
            child: Container(
              width: math.min(
                IdeNotificationToasts.maxWidth,
                constraints.maxWidth,
              ),
              constraints: BoxConstraints(
                maxHeight: math.max(120, constraints.maxHeight),
              ),
              decoration: BoxDecoration(
                color: IdeNotificationColors.background,
                border: Border.all(color: IdeNotificationColors.centerBorder),
                borderRadius: BorderRadius.circular(4),
                boxShadow: IdeHoverColors.shadow,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      height: 35,
                      color: IdeNotificationColors.centerHeaderBackground,
                      padding: const EdgeInsets.only(left: 8, right: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              all.isEmpty
                                  ? context.l10n.notificationsCenterNoNew
                                  : context.l10n.notificationsCenterTitle,
                              style: TextStyle(
                                fontSize: 11,
                                color: IdeNotificationColors
                                    .centerHeaderForeground,
                              ),
                            ),
                          ),
                          IdeActionButton(
                            icon: Codicons.clearAll,
                            tooltip: context.l10n.notificationsClearAll,
                            onPressed: all.isEmpty
                                ? null
                                : notifications.clearAll,
                          ),
                          IdeActionButton(
                            icon: Codicons.chevronDown,
                            tooltip: context.l10n.notificationsHide,
                            onPressed: notifications.hideCenter,
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final (index, notification) in all.indexed)
                            DecoratedBox(
                              key: ObjectKey(notification),
                              decoration: BoxDecoration(
                                border: index == all.length - 1
                                    ? null
                                    : Border(
                                        bottom: BorderSide(
                                          color: IdeNotificationColors.border,
                                        ),
                                      ),
                              ),
                              child: _NotificationItem(
                                notification: notification,
                                notifications: notifications,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// `.notification-list-item` (Modern UI): `padding: 6px 2px`; the icon in
/// 16px with `margin: 0 8px 0 6px`; the 22px-high message; the toolbar on
/// hover or when expanded; then, expanded, the source and the buttons.
class _NotificationItem extends StatefulWidget {
  const _NotificationItem({
    required this.notification,
    required this.notifications,
  });

  final IdeNotification notification;
  final IdeNotifications notifications;

  @override
  State<_NotificationItem> createState() => _NotificationItemState();
}

class _NotificationItemState extends State<_NotificationItem> {
  bool _hover = false;

  static TextStyle get _messageStyle => TextStyle(
    fontSize: 13,
    height: 22 / 13,
    color: IdeNotificationColors.foreground,
  );

  IdeNotification get _notification => widget.notification;

  void _run(IdeNotificationAction action) {
    widget.notifications.close(_notification);
    action.run();
  }

  (IconData, Color) get _icon => switch (_notification.severity) {
    IdeSeverity.info => (Codicons.info, IdeNotificationColors.infoIcon),
    IdeSeverity.warning => (
      Codicons.warning,
      IdeNotificationColors.warningIcon,
    ),
    IdeSeverity.error => (Codicons.error, IdeNotificationColors.errorIcon),
  };

  @override
  Widget build(BuildContext context) {
    final notification = _notification;
    final expanded = notification.expanded;
    final (icon, color) = _icon;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final messageStyle = _messageStyle;
            final painter = TextPainter(
              text: TextSpan(text: notification.message, style: messageStyle),
              maxLines: 1,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: math.max(0, constraints.maxWidth - 30 - 66));
            final overflows = painter.didExceedMaxLines;
            painter.dispose();
            final toolbar = _hover || expanded;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 16,
                      height: 22,
                      margin: const EdgeInsets.only(left: 6, right: 8),
                      alignment: Alignment.center,
                      child: Icon(icon, size: 16, color: color),
                    ),
                    Expanded(
                      child: SelectableText(
                        notification.message,
                        maxLines: expanded ? null : 1,
                        style: messageStyle,
                      ),
                    ),
                    Visibility.maintain(
                      visible: toolbar,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (notification.canCollapse &&
                              (expanded || overflows))
                            IdeActionButton(
                              icon: expanded
                                  ? Codicons.chevronDown
                                  : Codicons.chevronUp,
                              tooltip: expanded
                                  ? context.l10n.notificationsCollapse
                                  : context.l10n.notificationsExpand,
                              onPressed: () => widget.notifications
                                  .toggleExpanded(notification),
                            ),
                          if (notification.secondary.isNotEmpty)
                            Builder(
                              builder: (context) => IdeActionButton(
                                icon: Codicons.gear,
                                tooltip: context.l10n.notificationsMoreActions,
                                onPressed: () => _secondaryMenu(context),
                              ),
                            ),
                          IdeActionButton(
                            icon: Codicons.close,
                            tooltip: context.l10n.notificationsClear,
                            onPressed: () =>
                                widget.notifications.close(notification),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (notification.progress case final progress?)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: _ProgressBar(progress),
                  ),
                if (expanded &&
                    (notification.source != null ||
                        notification.primary.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 24),
                            child: Text(
                              notification.source == null
                                  ? ''
                                  : context.l10n.notificationsSource(
                                      notification.source!,
                                    ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: IdeNotificationColors.description,
                              ),
                            ),
                          ),
                        ),
                        for (final (index, action)
                            in notification.primary.indexed)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: action.menu == null
                                ? IdeButton(
                                    label: action.label,
                                    secondary: index > 0,
                                    onPressed: () => _run(action),
                                  )
                                : _SplitButton(
                                    action: action,
                                    secondary: index > 0,
                                    onRun: _run,
                                  ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _secondaryMenu(BuildContext context) {
    final box = context.findRenderObject()! as RenderBox;
    unawaited(
      showIdeMenu(
        context,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        alignRight: true,
        entries: [
          for (final action in _notification.secondary)
            IdeMenuAction(action.label, onSelected: () => _run(action)),
        ],
      ),
    );
  }
}

/// A button with a dropdown of more actions beside a separator
/// (`.monaco-button-dropdown`).
class _SplitButton extends StatelessWidget {
  const _SplitButton({
    required this.action,
    required this.secondary,
    required this.onRun,
  });

  final IdeNotificationAction action;
  final bool secondary;
  final ValueChanged<IdeNotificationAction> onRun;

  @override
  Widget build(BuildContext context) {
    final foreground = secondary
        ? IdeButtonColors.secondaryForeground
        : IdeButtonColors.foreground;
    return Container(
      decoration: BoxDecoration(
        color: secondary
            ? IdeButtonColors.secondaryBackground
            : IdeButtonColors.background,
        border: Border.all(
          color: secondary
              ? IdeButtonColors.secondaryBorder
              : IdeButtonColors.border,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _part(
            onTap: () => onRun(action),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                action.label,
                style: TextStyle(
                  fontSize: 12,
                  height: 16 / 12,
                  color: foreground,
                ),
              ),
            ),
          ),
          Container(width: 1, height: 16, color: IdeButtonColors.separator),
          Builder(
            builder: (context) => _part(
              onTap: () {
                final box = context.findRenderObject()! as RenderBox;
                unawaited(
                  showIdeMenu(
                    context,
                    anchor: box.localToGlobal(Offset.zero) & box.size,
                    alignRight: true,
                    entries: [
                      for (final item in action.menu!)
                        IdeMenuAction(
                          item.label,
                          onSelected: () => onRun(item),
                        ),
                    ],
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(Codicons.chevronDown, size: 14, color: foreground),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _part({required VoidCallback onTap, required Widget child}) =>
      MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      );
}

/// `.monaco-progress-container`: 2px in `progressBar.background`, a moving
/// bit for an infinite progress.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar(this.progress);

  final IdeNotificationProgress progress;

  @override
  Widget build(BuildContext context) {
    final color = themeColors['progressBar.background'];
    final total = progress.total;
    return SizedBox(
      height: 2,
      child: LinearProgressIndicator(
        value: total == null || total <= 0
            ? null
            : (progress.worked / total).clamp(0.0, 1.0),
        minHeight: 2,
        color: color,
        backgroundColor: Colors.transparent,
      ),
    );
  }
}
