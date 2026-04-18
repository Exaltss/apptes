import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';

// ── Notification channel (wajib dibuat sebelum service start) ──
const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'patrol_gps_channel',
  'GPS Patroli Aktif',
  description: 'Notifikasi lokasi patroli berjalan di latar belakang',
  importance: Importance.low,
  playSound: false,
  enableVibration: false,
);

Future<void> initBackgroundService() async {
  // 1. Buat notification channel DULU
  final flnp = FlutterLocalNotificationsPlugin();
  await flnp
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(_channel);

  // 2. Baru configure background service
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'patrol_gps_channel',
      initialNotificationTitle: 'GPS Patroli Aktif',
      initialNotificationContent: 'Lokasi Anda sedang dipantau...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onBackgroundStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((_) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((_) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  String currentStatus = 'patroli';
  service.on('updateStatus').listen((data) {
    if (data != null) {
      currentStatus = (data['status'] ?? 'patroli').toString();
    }
  });

  // Kirim lokasi setiap 3 detik
  Timer.periodic(const Duration(seconds: 3), (_) async {
    if (service is AndroidServiceInstance) {
      if (!await service.isForegroundService()) return;
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 5));

      await ApiService().updatePatrolStatus(
        lat: pos.latitude,
        long: pos.longitude,
        status: currentStatus,
      );

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'GPS Patroli — ${currentStatus.toUpperCase()}',
          content:
              'Update: ${DateTime.now().toLocal().toString().substring(11, 19)} WIB',
        );
      }
    } catch (_) {}
  });
}

Future<void> startBackgroundService(String status) async {
  final service = FlutterBackgroundService();
  final isRunning = await service.isRunning();
  if (!isRunning) {
    await service.startService();
    // Tunggu sebentar agar service siap
    await Future.delayed(const Duration(milliseconds: 500));
  }
  service.invoke('updateStatus', {'status': status});
}

Future<void> stopBackgroundService() async {
  FlutterBackgroundService().invoke('stopService');
}

Future<void> updateBackgroundStatus(String status) async {
  FlutterBackgroundService().invoke('updateStatus', {'status': status});
}
