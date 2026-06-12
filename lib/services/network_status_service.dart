import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NetworkStatusService {
  static const _probeUri = 'https://www.gstatic.com/generate_204';
  static const _defaultProbeTimeout = Duration(milliseconds: 800);
  static const _onlineCacheTtl = Duration(seconds: 2);
  static const _offlineCacheTtl = Duration(seconds: 45);
  static final http.Client _httpClient = http.Client();

  final Connectivity _connectivity = Connectivity();
  Future<bool>? _inFlightProbe;
  DateTime? _lastProbeAt;
  bool? _lastProbeResult;

  Stream<Object> get connectivityChanges =>
      _connectivity.onConnectivityChanged.map((event) => event as Object);

  Future<bool> hasNetworkInterface() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return _hasConnection(result);
    } catch (e) {
      debugPrint('[NetworkStatusService.hasNetworkInterface] $e');
      return false;
    }
  }

  Future<bool> isOnline({Duration timeout = _defaultProbeTimeout}) async {
    if (!await hasNetworkInterface()) {
      _rememberProbeResult(false);
      return false;
    }
    if (kIsWeb) {
      _rememberProbeResult(true);
      return true;
    }
    final cached = _cachedProbeResult();
    if (cached != null) return cached;
    final inFlightProbe = _inFlightProbe;
    if (inFlightProbe != null) return inFlightProbe;

    final probe = _probeReachability(timeout);
    _inFlightProbe = probe;
    try {
      return await probe;
    } finally {
      if (identical(_inFlightProbe, probe)) {
        _inFlightProbe = null;
      }
    }
  }

  bool looksOffline(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('socket') ||
        text.contains('network') ||
        text.contains('connection') ||
        text.contains('failed host lookup') ||
        text.contains('clientexception') ||
        text.contains('xmlhttprequest') ||
        text.contains('timeout') ||
        text.contains('connection closed') ||
        text.contains('network is unreachable');
  }

  bool _hasConnection(Object? result) {
    if (result is Iterable) {
      return result.any(_isConnectedResult);
    }
    return _isConnectedResult(result);
  }

  bool _isConnectedResult(Object? result) {
    return result is ConnectivityResult && result != ConnectivityResult.none;
  }

  Future<bool> _probeReachability(Duration timeout) async {
    try {
      final response = await _httpClient
          .get(Uri.parse(_probeUri))
          .timeout(timeout);
      final online = response.statusCode >= 200 && response.statusCode < 500;
      _rememberProbeResult(online);
      return online;
    } catch (e) {
      debugPrint('[NetworkStatusService.isOnline] $e');
      _rememberProbeResult(false);
      return false;
    }
  }

  bool? _cachedProbeResult() {
    final probedAt = _lastProbeAt;
    final result = _lastProbeResult;
    if (probedAt == null || result == null) return null;

    final age = DateTime.now().toUtc().difference(probedAt);
    final ttl = result ? _onlineCacheTtl : _offlineCacheTtl;
    if (age <= ttl) return result;
    return null;
  }

  void _rememberProbeResult(bool online) {
    _lastProbeAt = DateTime.now().toUtc();
    _lastProbeResult = online;
  }
}
