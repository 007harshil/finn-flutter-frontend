/// FiNN "calm ledger" kit: tokens and components shared by every screen
/// that has moved off `design_system/`. Import this barrel only.
///
/// Money display, masking, toasts and the success overlay are reused from
/// `design_system/` (they carry behaviour; their look follows the kit) and
/// re-exported here.
library;

export '../design_system/components/amount_text.dart' show AmountText, AnimatedAmount, AmountVisibility;
export '../design_system/components/layout.dart' show BottomClearanceX, MotionAnimatedSize;
export '../design_system/components/success.dart' show showSuccessOverlay;
export '../design_system/components/toast.dart' show FinnToast;
export '../design_system/components/tone.dart' show FinnTone;
export '../design_system/motion/motion.dart' show MotionX, Motion;
export 'components/controls.dart';
export 'components/data.dart';
export 'components/forms.dart';
export 'components/panel_slice.dart';
export 'components/sheets.dart';
export 'components/surfaces.dart';
export 'tokens.dart';
