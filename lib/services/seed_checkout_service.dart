import 'package:supabase_flutter/supabase_flutter.dart';

class SeedRazorpayOrder {
  final String keyId;
  final String orderId;
  final int amountSubunits;
  final String currency;
  final String environment;

  const SeedRazorpayOrder({
    required this.keyId,
    required this.orderId,
    required this.amountSubunits,
    required this.currency,
    required this.environment,
  });

  factory SeedRazorpayOrder.fromJson(Map<String, dynamic> json) {
    return SeedRazorpayOrder(
      keyId: '${json['keyId'] ?? ''}'.trim(),
      orderId: '${json['orderId'] ?? ''}'.trim(),
      amountSubunits: _integer(json['amountSubunits']),
      currency: '${json['currency'] ?? 'INR'}'.trim(),
      environment: '${json['environment'] ?? ''}'.trim(),
    );
  }

  bool get isValid =>
      keyId.startsWith('rzp_test_') &&
      orderId.isNotEmpty &&
      amountSubunits > 0 &&
      currency == 'INR' &&
      environment == 'test';
}

class SeedCheckoutService {
  SupabaseClient get _client => Supabase.instance.client;

  Future<SeedRazorpayOrder> createOrder(String seedRequestId) async {
    final data = await _invoke({
      'action': 'create_order',
      'seedRequestId': seedRequestId,
    });
    final order = SeedRazorpayOrder.fromJson(_map(data['order']));
    if (!order.isValid) {
      throw const SeedCheckoutException(
        'Razorpay Test Mode returned an invalid seed order.',
      );
    }
    return order;
  }

  Future<bool> verifyPayment({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final data = await _invoke({
      'action': 'verify_payment',
      'razorpayOrderId': razorpayOrderId,
      'razorpayPaymentId': razorpayPaymentId,
      'razorpaySignature': razorpaySignature,
    });
    return data['captured'] == true;
  }

  Future<void> refundSeedRequest(String seedRequestId) async {
    await _invoke({
      'action': 'refund_seed_request',
      'seedRequestId': seedRequestId,
    });
  }

  Future<Map<String, dynamic>> _invoke(Map<String, Object?> body) async {
    final token = _client.auth.currentSession?.accessToken ?? '';
    if (token.isEmpty) {
      throw const SeedCheckoutException('Login is required for seed payment.');
    }
    try {
      final response = await _client.functions.invoke(
        'fpc-seed-checkout',
        headers: {'Authorization': 'Bearer $token'},
        body: body,
      );
      final data = _map(response.data);
      if (data['success'] != true) {
        throw SeedCheckoutException(
          '${data['error'] ?? 'Seed payment could not be completed.'}',
        );
      }
      return data;
    } on SeedCheckoutException {
      rethrow;
    } catch (error) {
      throw SeedCheckoutException(_cleanError(error));
    }
  }

  static String _cleanError(Object error) {
    final message = '$error'
        .replaceFirst('FunctionsHttpError: ', '')
        .replaceFirst('PostgrestException(message: ', '')
        .trim();
    return message.isEmpty ? 'Seed payment could not be completed.' : message;
  }
}

class SeedCheckoutException implements Exception {
  final String message;

  const SeedCheckoutException(this.message);

  @override
  String toString() => message;
}

Map<String, dynamic> _map(Object? value) {
  if (value is! Map) return const {};
  return Map<String, dynamic>.from(value);
}

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
