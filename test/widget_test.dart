import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_demo/main.dart';
import 'package:google_maps_demo/features/map/presentation/pages/map_home_screen.dart';

void main() {
  testWidgets('Map home screen smoke test', (WidgetTester tester) async {
    // Build our app under ProviderScope and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: MyApp(),
      ),
    );

    // Verify that the MapHomeScreen is present.
    expect(find.byType(MapHomeScreen), findsOneWidget);
  });
}
