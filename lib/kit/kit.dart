/// FiNN "calm ledger" kit: tokens and components shared by every screen
/// that has moved off `design_system/`. Import this barrel only.
///
/// Money display, masking and sheets are reused from `design_system/`
/// (they carry behaviour, not looks) and re-exported here.
library;

export '../design_system/components/amount_text.dart' show AmountText, AnimatedAmount, AmountVisibility;
export '../design_system/components/layout.dart' show BottomClearanceX, MotionAnimatedSize;
export '../design_system/components/sheets.dart';
export '../design_system/motion/motion.dart' show MotionX, Motion;
export 'components/controls.dart';
export 'components/data.dart';
export 'components/panel_slice.dart';
export 'components/surfaces.dart';
export 'tokens.dart';
