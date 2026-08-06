import 'package:flutter_test/flutter_test.dart';
import 'package:kalsubai_farms/models/farmer_daily_task.dart';
import 'package:kalsubai_farms/models/marketplace_listing.dart';

void main() {
  group('MarketplaceListing', () {
    test('loads legacy marketplace rows without losing price or ownership', () {
      final listing = MarketplaceListing.fromJson({
        'id': 'listing-1',
        'owner_id': 'farmer-user-1',
        'lot_id': 'lot-1',
        'title': 'Finger Millet',
        'asking_price_per_kg': '32.50',
        'buyer_city': 'Pune',
        'status': 'listed',
      });

      expect(listing.farmerUserId, 'farmer-user-1');
      expect(listing.displayProductName, 'Finger Millet');
      expect(listing.askingPricePerUnit, 32.5);
      expect(listing.locationLabel, 'Pune');
      expect(listing.isActive, isTrue);
    });

    test('loads inventory-linked listing detail and interest state', () {
      final listing = MarketplaceListing.fromJson({
        'id': 'listing-2',
        'inventory_item_id': 'inventory-1',
        'farmer_user_id': 'farmer-user-2',
        'farm_id': 'farm-1',
        'farm_name': 'North Farm',
        'product_name': 'Pearl Millet',
        'quantity': 12,
        'unit': 'quintal',
        'grade': 'A',
        'moisture_percent': 11.8,
        'asking_price_per_unit': 2790,
        'price_unit': 'quintal',
        'image_paths': ['inventory/farmer-user-2/lot.jpg'],
        'interest_count': 3,
        'interested_by_me': true,
        'interest_status': 'requested',
        'status': 'paused',
      });

      expect(listing.inventoryItemId, 'inventory-1');
      expect(listing.moisturePercent, 11.8);
      expect(listing.priceUnit, 'quintal');
      expect(listing.imagePaths, hasLength(1));
      expect(listing.interestCount, 3);
      expect(listing.interestedByMe, isTrue);
      expect(listing.isPaused, isTrue);
    });

    test('loads FPC-exclusive crop-program price protection', () {
      final listing = MarketplaceListing.fromJson({
        'id': 'listing-3',
        'farmer_user_id': 'farmer-user-3',
        'crop_program_enrollment_id': 'enrollment-1',
        'exclusive_fpc_id': 'fpc-1',
        'sale_channel': 'fpc_exclusive',
        'protected_floor_rate': '44.50',
        'status': 'listed',
      });

      expect(listing.isFpcExclusive, isTrue);
      expect(listing.protectedFloorRate, 44.5);
    });
  });

  group('Marketplace negotiation and order', () {
    test('parses the current whole-lot offer and role', () {
      final negotiation = MarketplaceNegotiation.fromJson({
        'id': 'request-1',
        'current_offer_id': 'offer-2',
        'status': 'countered',
        'listing': {
          'id': 'listing-1',
          'product_name': 'Finger Millet',
          'quantity': 850,
          'unit': 'kg',
        },
        'offers': [
          {
            'id': 'offer-2',
            'request_id': 'request-1',
            'offered_by_role': 'farmer',
            'quantity': 850,
            'unit': 'kg',
            'price_per_unit': 41.5,
            'status': 'open',
          },
        ],
      });

      expect(negotiation.listing.quantity, 850);
      expect(negotiation.currentOffer?.offeredByRole, 'farmer');
      expect(negotiation.currentOffer?.pricePerUnit, 41.5);
      expect(negotiation.isOpen, isTrue);
    });

    test('parses quarantine and final-rate workflow state', () {
      final order = MarketplaceOrder.fromJson({
        'id': 'order-1',
        'order_number': 'MKT-20260727-1234',
        'listing_id': 'listing-1',
        'status': 'final_rate_pending',
        'quantity': 850,
        'unit': 'kg',
        'provisional_rate': 40,
        'provisional_amount': 34000,
        'arrival_quantity_kg': 825,
        'arrival_grade': 'A',
        'arrival_moisture_percent': 11.2,
        'final_rate': 42,
        'final_amount': 34650,
        'qr_payload': {'type': 'grainright_marketplace_order'},
        'listing': {'id': 'listing-1', 'product_name': 'Finger Millet'},
      });

      expect(order.needsFarmerConfirmation, isTrue);
      expect(order.canReceive, isFalse);
      expect(order.finalAmount, 34650);
      expect(order.qrPayload['type'], 'grainright_marketplace_order');
    });
  });

  group('FarmerDailyTask', () {
    test(
      'parses persisted task fields and can clear transition timestamps',
      () {
        final task = FarmerDailyTask.fromJson({
          'id': 'task-1',
          'farm_id': 'farm-1',
          'task_date': '2026-07-20',
          'task_key': 'water-stress',
          'task_type': 'irrigation',
          'title_key': 'todo_irrigation_title',
          'description_key': 'todo_irrigation_description',
          'priority': 'high',
          'status': 'snoozed',
          'source_type': 'satellite_signal',
          'snoozed_until': '2026-07-20T12:00:00Z',
        });

        final pending = task.copyWith(
          status: 'pending',
          clearCompletedAt: true,
          clearSnoozedUntil: true,
        );

        expect(task.snoozedUntil, isNotNull);
        expect(pending.status, 'pending');
        expect(pending.completedAt, isNull);
        expect(pending.snoozedUntil, isNull);
      },
    );
  });
}
