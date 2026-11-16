/// The single source of "now". Everything that needs the current time takes a
/// [Clock] so tests can control it; nothing else may read the system clock
/// (enforced by test/architecture).
library;

import 'package:clock/clock.dart';

export 'package:clock/clock.dart' show Clock;

const Clock systemClock = Clock();
