// Basic Flutter widget test for LiLoRa GPS app

import 'package:flutter_test/flutter_test.dart';

import 'package:lilora_mobile/main.dart';

void main() {
  testWidgets('App loads and shows title', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LiLoRaApp());

    // Verify that the app title is displayed
    expect(find.text('LiLoRa GPS'), findsOneWidget);

    // Verify permission card exists
    expect(find.text('Permissions'), findsOneWidget);
  });
}
