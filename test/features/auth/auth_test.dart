import 'package:finn/app/router/routes.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:finn/features/auth/application/auth_controller.dart';
import 'package:finn/features/auth/data/mock_auth_service.dart';
import 'package:finn/features/auth/domain/auth_session.dart';
import 'package:finn/features/auth/presentation/login_screen.dart';
import 'package:finn/features/auth/presentation/verify_otp_screen.dart';
import 'package:finn/features/profile/presentation/profile_avatar.dart';
import 'package:finn/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/test_app.dart';

/// Pumps [initial] inside a minimal router holding only the auth and
/// profile routes, with an instant mock auth service.
Future<ProviderContainer> _pumpRouted(WidgetTester tester, TestEnv env, String initial) async {
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (_, s) => LoginScreen(initialEmail: s.uri.queryParameters['email']),
        routes: [
          GoRoute(path: 'verify', builder: (_, s) => VerifyOtpScreen(email: s.uri.queryParameters['email']!)),
        ],
      ),
      GoRoute(path: AppRoutes.account, builder: (_, _) => const ProfileScreen()),
      GoRoute(path: AppRoutes.profile, builder: (_, _) => const Scaffold(body: Text('edit sheet'))),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      ...env.overrides,
      authServiceProvider.overrideWithValue(MockAuthService(clock: env.clock, latency: Duration.zero)),
    ],
    child: MaterialApp.router(
      theme: FinnTheme.light(),
      routerConfig: router,
      builder: (context, child) => MotionScope(reduceMotion: true, child: child!),
    ),
  ));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(Navigator).first));
}

/// Lets toasts and the resend countdown finish so no timer is left pending.
Future<void> _drainTimers(WidgetTester tester) async {
  for (var i = 0; i < 35; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
}

void main() {
  group('email and code rules', () {
    test('validates and normalises emails', () {
      expect(isValidEmail(' Aarav@Example.com '), isTrue);
      expect(normaliseEmail(' Aarav@Example.com '), 'aarav@example.com');
      for (final bad in ['', 'aarav', 'aarav@', '@example.com', 'a b@example.com', 'aarav@example']) {
        expect(isValidEmail(bad), isFalse, reason: bad);
      }
    });

    test('only six digits are a well-formed code', () {
      expect(isWellFormedOtp('123456'), isTrue);
      expect(isWellFormedOtp('12345'), isFalse);
      expect(isWellFormedOtp('12345a'), isFalse);
      expect(isWellFormedOtp('1234567'), isFalse);
    });

    test('initials come from the name, else the email', () {
      expect(profileInitials('Aarav Sharma Kumar', null), 'AS');
      expect(profileInitials('  aarav ', 'x@y.com'), 'A');
      expect(profileInitials('', 'zoya@example.com'), 'Z');
      expect(profileInitials(null, null), '?');
    });
  });

  group('AuthController', () {
    test('verifying does not sign in until signIn; the session persists', () async {
      final env = await TestEnv.create(signedIn: false);
      final container = ProviderContainer(overrides: [
        ...env.overrides,
        authServiceProvider.overrideWithValue(MockAuthService(clock: env.clock, latency: Duration.zero)),
      ]);
      addTearDown(container.dispose);
      final auth = container.read(authControllerProvider.notifier);
      expect(container.read(authControllerProvider), isNull);

      final session = await auth.verifyCode(' Aarav@Example.com', '123456');
      expect(session.email, 'aarav@example.com');
      expect(container.read(authControllerProvider), isNull);

      await auth.signIn(session);
      expect(container.read(authControllerProvider), session);
      expect(env.prefs.getString(AuthController.storageKey), isNotNull);

      // A fresh container restores the session from storage.
      final restored = ProviderContainer(overrides: env.overrides);
      addTearDown(restored.dispose);
      expect(restored.read(authControllerProvider), session);

      await auth.signOut();
      expect(container.read(authControllerProvider), isNull);
      expect(env.prefs.getString(AuthController.storageKey), isNull);
    });

    test('the mock rejects the failure code and malformed input', () async {
      final service = MockAuthService(clock: (await TestEnv.create()).clock, latency: Duration.zero);
      await expectLater(service.sendCode('nope'), throwsA(isA<AuthFailure>()));
      await expectLater(service.verifyCode('a@b.co', MockAuthService.rejectedCode), throwsA(isA<AuthFailure>()));
      await expectLater(service.verifyCode('a@b.co', '12'), throwsA(isA<AuthFailure>()));
    });
  });

  group('login and verify screens', () {
    testWidgets('invalid email shows an error and sends nothing', (tester) async {
      final env = await TestEnv.create(signedIn: false);
      await _pumpRouted(tester, env, AppRoutes.login);

      await tester.enterText(find.byKey(const ValueKey('login-email')).first, 'not-an-email');
      await tester.tap(find.byKey(const ValueKey('send-code')));
      await tester.pumpAndSettle();

      expect(find.text('Invalid email address.'), findsOneWidget);
      expect(find.byType(VerifyOtpScreen), findsNothing);
    });

    testWidgets('a valid email opens the code screen; a correct code signs in', (tester) async {
      final env = await TestEnv.create(signedIn: false);
      final container = await _pumpRouted(tester, env, AppRoutes.login);

      await tester.enterText(find.byKey(const ValueKey('login-email')).first, 'Aarav@Example.com');
      await tester.tap(find.byKey(const ValueKey('send-code')));
      await tester.pumpAndSettle();

      expect(find.byType(VerifyOtpScreen), findsOneWidget);
      expect(find.textContaining('aarav@example.com', findRichText: true), findsOneWidget);
      expect(find.text('Resend code in 0:30'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('otp-field')), '424242');
      await tester.pump();
      await tester.pump();
      expect(find.text('You\'re signed in'), findsOneWidget);
      expect(container.read(authControllerProvider), isNull, reason: 'signs in after the confirmation');

      await tester.pump(const Duration(seconds: 1));
      expect(container.read(authControllerProvider)?.email, 'aarav@example.com');
      await _drainTimers(tester);
    });

    testWidgets('a rejected code shows the failure state and can retry', (tester) async {
      final env = await TestEnv.create(signedIn: false);
      final container = await _pumpRouted(tester, env, AppRoutes.verifyOtp('aarav@example.com'));

      await tester.enterText(find.byKey(const ValueKey('otp-field')), MockAuthService.rejectedCode);
      await tester.pumpAndSettle();
      expect(find.text('Verification failed'), findsOneWidget);
      expect(container.read(authControllerProvider), isNull);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Enter verification code'), findsOneWidget);
      await _drainTimers(tester);
      expect(find.text('Resend code'), findsOneWidget);
    });
  });

  group('profile screen', () {
    testWidgets('shows the person and signs out after confirming', (tester) async {
      final env = await TestEnv.create();
      final container = await _pumpRouted(tester, env, AppRoutes.account);

      expect(find.text('Aarav'), findsOneWidget);
      expect(find.text('aarav@example.com'), findsWidgets);
      expect(find.text('Opening balance'), findsOneWidget);

      final signOut = find.byKey(const ValueKey('sign-out'));
      await tester.scrollUntilVisible(signOut, 200);
      await tester.ensureVisible(signOut);
      await tester.pumpAndSettle();
      await tester.tap(signOut);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FinnButton, 'Sign out'));
      await tester.pumpAndSettle();

      expect(container.read(authControllerProvider), isNull);
      await _drainTimers(tester);
    });

    testWidgets('edit profile opens the profile sheet', (tester) async {
      final env = await TestEnv.create();
      await _pumpRouted(tester, env, AppRoutes.account);

      await tester.tap(find.byKey(const ValueKey('edit-profile')));
      await tester.pumpAndSettle();
      expect(find.text('edit sheet'), findsOneWidget);
    });
  });
}
