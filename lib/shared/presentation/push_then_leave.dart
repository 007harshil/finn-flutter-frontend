import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Opens the sheet at [route] and, when it closes with `true` (the thing was
/// recorded), leaves the screen that opened it too. Used where recording
/// finishes the job a notification pointed at, so the user is not left on a
/// page whose "next" payment one more tap would record again.
Future<void> pushThenLeave(BuildContext context, String route) async {
  final done = await context.push<bool>(route);
  if (done == true && context.mounted && context.canPop()) context.pop();
}
