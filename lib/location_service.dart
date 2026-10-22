import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// GPS và chuyển tọa độ thành địa chỉ cho ứng dụng WorkTime.
/// Thư viện geocoding 5.x: sử dụng Geocoding(locale: ...).
class LocationService {
  static Future<Position> getCurrentLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      throw Exception('Vui lòng bật dịch vụ vị trí (GPS).');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Ứng dụng chưa được cấp quyền vị trí.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Quyền vị trí bị từ chối vĩnh viễn. '
        'Hãy cấp lại quyền trong Cài đặt ứng dụng.',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return position;
    } on TimeoutException {
      throw Exception('GPS phản hồi quá lâu, hãy thử lại.');
    }
  }

  /// Tra cứu tên đường/phường/thành phố. Nếu thất bại vẫn trả về
  /// thông báo, không ngăn Check-in bằng GPS.
  static Future<String> getReadableAddress(Position position) async {
    try {
      final geocoding = Geocoding(
        locale: const Locale('vi', 'VN'),
      );
      final places = await geocoding
          .placemarkFromCoordinates(position.latitude, position.longitude)
          .timeout(const Duration(seconds: 10));

      if (places.isEmpty) {
        return 'Không có thông tin địa chỉ cho vị trí này.';
      }

      final place = places.first;
      final street = (place.street ?? '').trim();
      final thoroughfare = (place.thoroughfare ?? '').trim();
      final number = (place.subThoroughfare ?? '').trim();

      final roadName = street.isNotEmpty
          ? street
          : [number, thoroughfare]
              .where((part) => part.isNotEmpty)
              .join(' ');

      final pieces = <String>[];
      for (final part in [
        roadName,
        place.subLocality ?? '',
        place.subAdministrativeArea ?? '',
        place.locality ?? '',
        place.administrativeArea ?? '',
      ]) {
        final trimmed = part.trim();
        if (trimmed.isEmpty) continue;
        if (pieces.any((existing) =>
            existing.toLowerCase() == trimmed.toLowerCase())) {
          continue;
        }
        pieces.add(trimmed);
      }

      if (pieces.isEmpty) {
        return 'Không tìm thấy tên đường tại vị trí này.';
      }
      return pieces.join(', ');
    } catch (error) {
      debugPrint('Reverse geocoding error: $error');
      return 'Không tra cứu được tên đường. Hãy thử lại hoặc kiểm tra mạng.';
    }
  }

  static Future<LocationResult> getLocationDetails() async {
    final position = await getCurrentLocation();
    final address = await getReadableAddress(position);
    return LocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      address: address,
    );
  }

  static Future<bool> openAppSettings() =>
      Geolocator.openAppSettings();

  static Future<bool> openLocationSettings() =>
      Geolocator.openLocationSettings();
}

class LocationResult {
  final double latitude;
  final double longitude;
  final double accuracy;
  final String address;

  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.address,
  });
}
