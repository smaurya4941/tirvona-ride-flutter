import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tirvona_ride/app/router/app_router.dart';
import 'package:tirvona_ride/app/router/app_routes.dart';
import 'package:tirvona_ride/features/auth/domain/app_user.dart';
import 'package:tirvona_ride/features/auth/presentation/session_controller.dart';
import 'package:tirvona_ride/features/driver/account/data/driver_account_repository.dart';
import 'package:tirvona_ride/features/driver/account/domain/driver_change.dart';
import 'package:tirvona_ride/features/driver/account/presentation/driver_details_screen.dart';
import 'package:tirvona_ride/features/driver/account/presentation/driver_documents_screen.dart';
import 'package:tirvona_ride/features/driver/account/presentation/driver_reviews_screen.dart';
import 'package:tirvona_ride/features/driver/account/presentation/driver_vehicle_screen.dart';
import 'package:tirvona_ride/features/driver/data/driver_repository.dart';
import 'package:tirvona_ride/features/driver/data/vehicle_repository.dart';
import 'package:tirvona_ride/features/driver/domain/driver_models.dart';
import 'package:tirvona_ride/features/driver/ratings/driver_ratings.dart';

final _profile = DriverProfile(
  id: 'd1',
  driverCode: 'DRX1',
  driverStatus: DriverStatus.approved,
  licenseNumber: 'UP3220210012345',
  licenseExpiry: DateTime.utc(DateTime.now().year + 3, 6, 30),
  dateOfBirth: DateTime.utc(1990, 1, 31),
  address: 'Sector 62, Noida',
);

const _vehicle = Vehicle(
  id: 'v1',
  vehicleType: VehicleType.auto,
  registrationNumber: 'UP85CC0001',
  isActive: true,
  make: 'Bajaj',
  model: 'RE',
  color: 'Green',
);

DriverChangeRequest _request({
  String id = 'c1',
  DriverChangeKind kind = DriverChangeKind.driverProfile,
  DriverChangeStatus status = DriverChangeStatus.pending,
  String? documentType,
  String? vehicleId,
  Map<String, dynamic> changes = const {},
  String? reviewNote,
}) => DriverChangeRequest(
  id: id,
  kind: kind,
  label: 'Update',
  status: status,
  changes: changes,
  previous: const {},
  hasFile: false,
  submittedAt: DateTime(2026, 9, 30),
  documentType: documentType,
  vehicleId: vehicleId,
  reviewNote: reviewNote,
);

class _FakeAccount extends DriverAccountRepository {
  _FakeAccount() : super(Dio());

  DriverChangesOverview overview = const DriverChangesOverview();
  final profileRequests = <Map<String, Object?>>[];
  final vehicleRequests = <Map<String, dynamic>>[];
  final addresses = <String>[];
  final withdrawn = <String>[];
  final reviewCalls = <Map<String, Object?>>[];
  List<DriverReview> allReviews = [
    for (var index = 0; index < 45; index++)
      DriverReview(
        key: 'k$index',
        rating: 5 - index % 5,
        comment: index.isEven ? 'Comment $index' : null,
        ratedOn: DateTime(2026, 9, 1 + index % 28),
      ),
  ];

  @override
  Future<DriverChangesOverview> changes() async => overview;

  @override
  Future<DriverProfile> updateAddress(String address) async {
    addresses.add(address);
    return _profile;
  }

  @override
  Future<DriverChangeRequest> requestProfileChange({
    String? licenseNumber,
    DateTime? licenseExpiry,
    DateTime? dateOfBirth,
  }) async {
    profileRequests.add({
      'licenseNumber': licenseNumber,
      'licenseExpiry': licenseExpiry,
      'dateOfBirth': dateOfBirth,
    });
    return _request(changes: {'licenseNumber': licenseNumber});
  }

  @override
  Future<DriverChangeRequest> requestVehicleChange(
    String vehicleId,
    VehicleChange change,
  ) async {
    vehicleRequests.add({'vehicleId': vehicleId, ...change.toJson()});
    return _request(kind: DriverChangeKind.vehicle, vehicleId: vehicleId);
  }

  @override
  Future<DriverChangeRequest> withdraw(String id) async {
    withdrawn.add(id);
    return _request(id: id, status: DriverChangeStatus.withdrawn);
  }

  @override
  Future<List<VehicleDocumentRecord>> vehicleDocuments(
    String vehicleId,
  ) async => [
    VehicleDocumentRecord(
      id: 'vd1',
      documentType: VehicleDocumentType.insurance,
      status: DocumentStatus.verified,
      documentNumber: 'INS-9',
      expiryDate: DateTime.now().add(const Duration(days: 10)),
    ),
  ];

  @override
  Future<DriverReviewsPage> reviews({
    String? cursor,
    int limit = 20,
    int? stars,
    bool withComment = false,
  }) async {
    reviewCalls.add({
      'cursor': cursor,
      'stars': stars,
      'withComment': withComment,
    });
    final matching = allReviews
        .where((review) => stars == null || review.rating == stars)
        .where((review) => !withComment || review.comment != null)
        .toList();
    final start = cursor == null ? 0 : int.parse(cursor);
    final end = (start + limit).clamp(0, matching.length);
    return DriverReviewsPage(
      items: matching.sublist(start, end),
      nextCursor: end < matching.length ? '$end' : null,
    );
  }
}

void main() {
  late _FakeAccount account;
  late ProviderContainer container;

  setUp(() {
    account = _FakeAccount();
    container = ProviderContainer(
      overrides: [
        driverAccountRepositoryProvider.overrideWithValue(account),
        driverProfileProvider.overrideWith((ref) async => _profile),
        myVehiclesProvider.overrideWith((ref) async => const [_vehicle]),
        driverDocumentsProvider.overrideWith(
          (ref) async => [
            KycDocument(
              id: 'k1',
              documentType: KycDocumentType.drivingLicense,
              status: DocumentStatus.verified,
              documentNumber: 'DL-1',
              expiryDate: DateTime.now().subtract(const Duration(days: 3)),
            ),
            const KycDocument(
              id: 'k2',
              documentType: KycDocumentType.aadhaar,
              status: DocumentStatus.pending,
            ),
          ],
        ),
        driverRatingSummaryProvider.overrideWith(
          (ref) async => const DriverRatingSummary(
            ratingAverage: 4.6,
            ratingCount: 45,
            totalRides: 60,
            distribution: {1: 9, 2: 9, 3: 9, 4: 9, 5: 9},
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('routing', () {
    AppUser driver(DriverStatus status) => AppUser(
      id: 'u1',
      phone: '+919812345678',
      role: UserRole.driver,
      status: UserStatus.active,
      firstName: 'Ravi',
      isPhoneVerified: true,
      driver: DriverStatusInfo(driverStatus: status),
    );

    test('approved drivers reach their account screens; others do not', () {
      final approved = SessionState.authenticated(
        driver(DriverStatus.approved),
      );
      for (final route in [
        AppRoutes.driverDetails,
        AppRoutes.driverVehicleDetails,
        AppRoutes.driverDocuments,
        AppRoutes.driverReviews,
      ]) {
        expect(resolveRedirect(approved, route), isNull, reason: route);
      }
      final pending = SessionState.authenticated(driver(DriverStatus.pending));
      expect(
        resolveRedirect(pending, AppRoutes.driverDocuments),
        AppRoutes.driverRegistration,
      );
    });
  });

  group('models', () {
    test('finds the pending and last rejected change per target', () {
      final overview = DriverChangesOverview(
        pending: [
          _request(
            id: 'p1',
            kind: DriverChangeKind.driverDocument,
            documentType: 'PAN',
          ),
        ],
        history: [
          _request(
            id: 'r1',
            kind: DriverChangeKind.driverDocument,
            documentType: 'AADHAAR',
            status: DriverChangeStatus.rejected,
            reviewNote: 'Blurred',
          ),
          _request(
            id: 'r0',
            kind: DriverChangeKind.driverDocument,
            documentType: 'PAN',
            status: DriverChangeStatus.rejected,
          ),
        ],
      );
      expect(
        overview
            .pendingFor(DriverChangeKind.driverDocument, documentType: 'PAN')
            ?.id,
        'p1',
      );
      // A newer pending request hides an old rejection.
      expect(
        overview.lastRejectedFor(
          DriverChangeKind.driverDocument,
          documentType: 'PAN',
        ),
        isNull,
      );
      expect(
        overview
            .lastRejectedFor(
              DriverChangeKind.driverDocument,
              documentType: 'AADHAAR',
            )
            ?.reviewNote,
        'Blurred',
      );
    });

    test('parses change requests and reviews from the API', () {
      final request = DriverChangeRequest.fromJson({
        'id': 'c9',
        'kind': 'VEHICLE_DOCUMENT',
        'label': 'Vehicle insurance',
        'status': 'REJECTED',
        'changes': {'expiryDate': '2027-03-31T00:00:00.000Z'},
        'previous': <String, dynamic>{},
        'hasFile': false,
        'vehicleId': 'v1',
        'documentType': 'INSURANCE',
        'reviewNote': 'Expired',
        'submittedAt': '2026-09-30T10:00:00.000Z',
        'reviewedAt': '2026-09-30T12:00:00.000Z',
      });
      expect(request.kind, DriverChangeKind.vehicleDocument);
      expect(request.status, DriverChangeStatus.rejected);
      expect(request.status.label, 'Not approved');

      final review = DriverReview.fromJson({
        'key': 'abc',
        'rating': 4,
        'ratedOn': '2026-09-02',
      });
      expect(review.ratedOn, DateTime(2026, 9, 2));
      expect(review.comment, isNull);

      expect(
        const VehicleChange(
          registrationNumber: 'up 85 zz 7777',
          color: 'Red',
        ).toJson(),
        {'registrationNumber': 'UP85ZZ7777', 'color': 'Red'},
      );
    });
  });

  group('driver details', () {
    testWidgets('shows a pending change and withdraws it', (tester) async {
      account.overview = DriverChangesOverview(
        pending: [
          _request(changes: const {'licenseNumber': 'UP3220260099999'}),
        ],
      );
      await pump(tester, const DriverDetailsScreen());
      expect(find.textContaining('Update under review'), findsOneWidget);
      expect(find.text('Licence number: UP3220260099999'), findsOneWidget);
      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      expect(account.withdrawn, ['c1']);
    });

    testWidgets('sends only the changed licence number for review', (
      tester,
    ) async {
      await pump(tester, const DriverDetailsScreen());
      await tester.tap(find.text('Request a change'));
      await tester.pumpAndSettle();

      // Unchanged: nothing is sent.
      await tester.tap(find.text('Send for review'));
      await tester.pumpAndSettle();
      expect(
        find.text('Change at least one detail to send a request.'),
        findsOneWidget,
      );
      expect(account.profileRequests, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Driving licence number'),
        'up32 2026 0099999',
      );
      await tester.tap(find.text('Send for review'));
      await tester.pumpAndSettle();
      expect(account.profileRequests.single, {
        'licenseNumber': 'UP3220260099999',
        'licenseExpiry': null,
        'dateOfBirth': null,
      });
      expect(find.text('Sent for review. We will notify you.'), findsOneWidget);
    });

    testWidgets('saves the address directly', (tester) async {
      await pump(tester, const DriverDetailsScreen());
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Sector 62, Noida'),
        'Tower B, Sector 74, Noida',
      );
      await tester.tap(find.text('Save address'));
      await tester.pumpAndSettle();
      expect(account.addresses, ['Tower B, Sector 74, Noida']);
    });
  });

  group('vehicle', () {
    testWidgets('requests only the changed colour', (tester) async {
      await pump(tester, const DriverVehicleScreen());
      expect(find.text('UP85CC0001'), findsOneWidget);
      await tester.tap(find.text('Request a change'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Colour'),
        'Yellow',
      );
      await tester.tap(find.text('Send for review'));
      await tester.pumpAndSettle();
      expect(account.vehicleRequests.single, {
        'vehicleId': 'v1',
        'color': 'Yellow',
      });
    });
  });

  group('documents', () {
    testWidgets('shows status, expiry, pending updates and rejections', (
      tester,
    ) async {
      account.overview = DriverChangesOverview(
        pending: [
          _request(
            id: 'pan-1',
            kind: DriverChangeKind.driverDocument,
            documentType: 'PAN',
          ),
        ],
        history: [
          _request(
            id: 'rc-1',
            kind: DriverChangeKind.vehicleDocument,
            documentType: 'RC',
            vehicleId: 'v1',
            status: DriverChangeStatus.rejected,
            reviewNote: 'Blurred photo',
          ),
        ],
      );
      await pump(tester, const DriverDocumentsScreen());

      expect(find.text('Verified · DL-1'), findsOneWidget);
      expect(find.textContaining('Expired'), findsOneWidget);
      expect(find.text('Profile photo'), findsOneWidget);
      expect(find.text('Missing'), findsOneWidget);
      expect(find.text('Verified · INS-9'), findsOneWidget);
      expect(find.textContaining('Expires in'), findsOneWidget);
      expect(
        find.text('Last update not approved: Blurred photo'),
        findsOneWidget,
      );
      expect(find.text('Under review'), findsOneWidget);

      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      expect(account.withdrawn, ['pan-1']);
    });
  });

  group('reviews', () {
    testWidgets('pages through reviews and filters them', (tester) async {
      await pump(tester, const DriverReviewsScreen());
      expect(find.text('4.6'), findsOneWidget);
      expect(find.text('“Comment 0”'), findsOneWidget);
      expect(account.reviewCalls, hasLength(1));

      await tester.drag(find.byType(ListView), const Offset(0, -6000));
      await tester.pumpAndSettle();
      expect(account.reviewCalls.length, greaterThanOrEqualTo(2));
      expect(account.reviewCalls[1]['cursor'], '20');

      // Back to the top, where the filters are.
      await tester.drag(find.byType(ListView), const Offset(0, 6000));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('1 ★'));
      await tester.tap(find.text('1 ★'));
      await tester.pumpAndSettle();
      expect(account.reviewCalls.last, {
        'cursor': null,
        'stars': 1,
        'withComment': false,
      });
      expect(find.byIcon(Icons.star_outline_rounded), findsWidgets);

      account.allReviews = [];
      await tester.ensureVisible(find.text('All'));
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No ratings yet'), findsOneWidget);
    });
  });
}
