import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Gunakan 10.0.2.2 untuk emulator, atau IP Laptop (misal: 192.168.1.5) untuk HP fisik
  static const String baseUrl = 'http://10.0.2.2:8000/api';

  // --- HELPER: AMBIL TOKEN DARI STORAGE ---
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  // --- LOGIN ---
  Future<bool> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        body: {'username': username, 'password': password},
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['access_token']);

        // Simpan metadata user untuk ditampilkan di UI
        if (data['user'] != null && data['user']['personnel'] != null) {
          await prefs.setString(
            'nama_lengkap',
            data['user']['personnel']['nama_lengkap'] ?? "Petugas",
          );
          await prefs.setString(
            'pangkat',
            data['user']['personnel']['pangkat'] ?? "-",
          );
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error Login: $e");
      return false;
    }
  }

  // --- LOGOUT ---
  Future<bool> logout() async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error Logout: $e");
      return false;
    }
  }

  // --- AMBIL PROFIL USER ---
  Future<Map<String, dynamic>> getProfile() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/user'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      throw Exception('Gagal profil');
    } catch (e) {
      throw Exception('Koneksi bermasalah: $e');
    }
  }

  // --- UPDATE LOKASI REALTIME (TRACKING) ---
  Future<bool> updatePatrolStatus({
    required double lat,
    required double long,
    required String status,
  }) async {
    try {
      final token = await getToken();
      final response = await http.post(
        Uri.parse('$baseUrl/tracking'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'latitude': lat,
          'longitude': long,
          'status_aktif': status,
        }),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint("Error Update Tracking: $e");
      return false;
    }
  }

  // --- AMBIL LOKASI PERSONEL LAIN UNTUK PETA ---
  Future<List<dynamic>> getOtherLocations() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/locations'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      return response.statusCode == 200 ? jsonDecode(response.body) : [];
    } catch (e) {
      return [];
    }
  }

  // --- KIRIM LAPORAN / ADUAN (MULTIPART UNTUK FOTO) ---
  Future<bool> sendReport({
    required String judul,
    required String deskripsi,
    required String tipe,
    required String prioritas,
    required double lat,
    required double lng,
    File? foto,
  }) async {
    try {
      final token = await getToken();
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/reports'),
      );

      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });

      // Mapping data sesuai field di Database/Controller Laravel
      request.fields['judul_kejadian'] = judul;
      request.fields['tipe_laporan'] = tipe;
      request.fields['deskripsi'] = deskripsi;
      request.fields['prioritas'] = prioritas;
      request.fields['latitude'] = lat.toString();
      request.fields['longitude'] = lng.toString();

      // SINKRONISASI: Status awal wajib 'menunggu konfirmasi'
      request.fields['status_penanganan'] = 'menunggu konfirmasi';

      // Lampirkan foto jika ada
      if (foto != null) {
        request.files.add(
          await http.MultipartFile.fromPath('foto_bukti', foto.path),
        );
      }

      debugPrint("Mengirim laporan ke: ${request.url}");
      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 20),
      );
      var response = await http.Response.fromStream(streamedResponse);

      // LOG DEBUG: Cek ini di terminal jika status code bukan 200/201
      debugPrint("Response Status: ${response.statusCode}");
      debugPrint("Response Body: ${response.body}");

      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      debugPrint("Exception Send Report: $e");
      return false;
    }
  }

  // --- WRAPPER UNTUK CHECKPOINT ---
  Future<bool> kirimCheckpoint(double lat, double long) async {
    return await sendReport(
      judul: 'Titik Checkpoint',
      tipe: 'checkpoint',
      deskripsi: 'Petugas melakukan scanning di titik ini.',
      prioritas: 'rendah',
      lat: lat,
      lng: long,
    );
  }

  // --- AMBIL RIWAYAT LAPORAN SAYA ---
  Future<List<dynamic>> getHistoryLaporan() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/reports'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // --- AMBIL JADWAL TUGAS ---
  Future<List<dynamic>> getJadwal() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/jadwal-mobile'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // --- AMBIL INSTRUKSI TERBARU (NOTIFIKASI) ---
  Future<Map<String, dynamic>?> getLatestInstruction() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/latest-instruction'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      return response.statusCode == 200 ? jsonDecode(response.body) : null;
    } catch (e) {
      return null;
    }
  }

  // --- AMBIL RINGKASAN JUMLAH TUGAS ---
  Future<Map<String, dynamic>> getRingkasan() async {
    try {
      final token = await getToken();
      final response = await http.get(
        Uri.parse('$baseUrl/ringkasan-laporan'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'laporan_count': 0, 'checkpoint_count': 0};
    } catch (e) {
      return {'laporan_count': 0, 'checkpoint_count': 0};
    }
  }
}
