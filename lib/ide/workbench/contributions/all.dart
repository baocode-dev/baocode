// The features' contributions, made as a window is: the order is the
// order their actions are tried in (of two with an id, the first runs).

import '../contributions.dart';
import '../services.dart';
import 'navigation.dart';
import 'scm.dart';
import 'terminal.dart';

List<WorkbenchContribution> createWorkbenchContributions(
  WorkbenchServices services,
) => [
  NavigationContribution(services),
  ScmContribution(services),
  TerminalContribution(services),
];
