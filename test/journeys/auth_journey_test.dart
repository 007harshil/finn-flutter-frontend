import 'package:finn/features/auth/application/auth_controller.dart';
import 'package:finn/features/auth/domain/auth_session.dart';
import 'package:finn/features/auth/presentation/login_screen.dart';
import 'package:finn/features/onboarding/presentation/onboarding_screen.dart';
import 'package:finn/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first));

void main() {
  testWidgets('signed out: every route leads to login; signing in opens Home', (tester) async {
    final env = await TestEnv.create(signedIn: false);
    await env.pumpApp(tester);
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await _container(tester)
        .read(authControllerProvider.notifier)
        .signIn(AuthSession(email: 'aarav@example.com', signedInAt: testNow));
    await settle(tester);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('AVAILABLE TO SPEND'), findsOneWidget);
  });

  testWidgets('signed in but not set up: onboarding comes next', (tester) async {
    final env = await TestEnv.create(onboarded: false);
    await env.pumpApp(tester);
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('More tab opens the profile; signing out returns to login', (tester) async {
    final env = await TestEnv.create();
    await env.pumpApp(tester);
    await settle(tester);

    await tapTab(tester, 'More');
    await tester.tap(find.byKey(const ValueKey('profile-entry')));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    final signOut = find.byKey(const ValueKey('sign-out'));
    await tester.scrollUntilVisible(signOut, 200);
    await tester.ensureVisible(signOut);
    await tester.pumpAndSettle();
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out').last);
    await settle(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(_container(tester).read(authControllerProvider), isNull);
  });
}
