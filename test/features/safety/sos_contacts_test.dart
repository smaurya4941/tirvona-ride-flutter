import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/features/safety/models/safety_models.dart';
import 'package:tirvona_ride/features/safety/repository/safety_repository.dart';
import 'package:tirvona_ride/features/safety/widgets/sos_button.dart';

Map<String, dynamic> _alertJson({List<Map<String, dynamic>>? contacts}) => {
  'id': 'sos1',
  'sosCode': 'SOS-RZ4H2Y',
  'rideId': 'ride1',
  'status': 'TRIGGERED',
  'triggeredAt': '2026-10-03T07:17:00.000Z',
  'location': {'latitude': 28.6, 'longitude': 77.3, 'source': 'DEVICE'},
  'contacts': ?contacts,
};

void main() {
  group('SosAlert contacts', () {
    test('parses who was messaged on WhatsApp', () {
      final alert = SosAlert.fromJson(
        _alertJson(
          contacts: [
            {'name': 'Kushal Pandey', 'status': 'SENT'},
            {'name': 'Meera', 'status': 'FAILED'},
            {'name': 'Rohit', 'status': 'PENDING'},
          ],
        ),
      );
      expect(alert.contacts.map((c) => c.state), [
        SosContactState.sent,
        SosContactState.failed,
        SosContactState.pending,
      ]);
      expect(alert.contactsStillSending, isTrue);
    });

    test('older servers without the field still parse', () {
      final alert = SosAlert.fromJson(_alertJson());
      expect(alert.contacts, isEmpty);
      expect(alert.contactsStillSending, isFalse);
    });

    test('is done sending once nobody is pending', () {
      final alert = SosAlert.fromJson(
        _alertJson(
          contacts: [
            {'name': 'A', 'status': 'SENT'},
            {'name': 'B', 'status': 'FAILED'},
          ],
        ),
      );
      expect(alert.contactsStillSending, isFalse);
    });
  });

  group('SosActiveSheet', () {
    Future<void> pump(WidgetTester tester, SosAlert alert) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            rideSosProvider('ride1').overrideWith((ref) async => [alert]),
            emergencyContactsProvider.overrideWith(
              (ref) async => const [
                EmergencyContact(
                  id: 'c1',
                  name: 'Kushal Pandey',
                  phone: '+919005011088',
                  isPrimary: true,
                  relationship: 'Friend',
                ),
              ],
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: SosActiveSheet(rideId: 'ride1', initial: alert),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('shows each contact as sent', (tester) async {
      await pump(
        tester,
        SosAlert.fromJson(
          _alertJson(
            contacts: [
              {'name': 'Kushal Pandey', 'status': 'SENT'},
            ],
          ),
        ),
      );
      expect(find.text('Live location sent on WhatsApp'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      // Calling stays one tap away.
      expect(find.text('Call 112 (Emergency)'), findsOneWidget);
    });

    testWidgets('tells the user to call a contact that could not be messaged', (
      tester,
    ) async {
      await pump(
        tester,
        SosAlert.fromJson(
          _alertJson(
            contacts: [
              {'name': 'Kushal Pandey', 'status': 'FAILED'},
            ],
          ),
        ),
      );
      expect(find.text("Couldn't send. Call them"), findsOneWidget);
      expect(
        find.textContaining('safety team can see this too'),
        findsOneWidget,
      );
    });

    testWidgets('shows a spinner while a message is still going out', (
      tester,
    ) async {
      await pump(
        tester,
        SosAlert.fromJson(
          _alertJson(
            contacts: [
              {'name': 'Kushal Pandey', 'status': 'PENDING'},
            ],
          ),
        ),
      );
      expect(find.text('Sending…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Dispose the sheet's 3-second poll before the test ends.
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('shows no WhatsApp block when the user has no contacts', (
      tester,
    ) async {
      await pump(tester, SosAlert.fromJson(_alertJson()));
      expect(find.text('Live location sent on WhatsApp'), findsNothing);
      expect(find.text('Call 112 (Emergency)'), findsOneWidget);
    });
  });
}
