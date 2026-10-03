import 'dart:async';

import 'package:flutter/widgets.dart';

/// Starts an item from a server-provided resume position.
typedef ResumeItemCallback = FutureOr<void> Function(
    BuildContext context, String itemId, Duration startPosition);
