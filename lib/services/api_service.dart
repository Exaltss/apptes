import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Gunakan 10.0.2.2 untuk emulator, atau IP Laptop untuk HP fisik.
  static const String baseUrl = 'http://10.0.2.2:8000/api';

  // --- HELPER: DATA STORAGE ---
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  // --- LOGIN: SIMPAN SEMUA KE LOKAL ---
  Future<bool> login(String username, String password) async {
    try {
      debugPrint("--- MENCOBA LOGIN: $username ---");
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        body: {'username': username, 'password': password},
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('token', data['access_token']);

        if (data['user'] != null) {
          await prefs.setInt('user_id', data['user']['id']);
          await prefs.setString('username', data['user']['username'] ?? "-");

          if (data['user']['personnel'] != null) {
            final p = data['user']['personnel'];
            await prefs.setString(
              'nama_lengkap',
              p['nama_lengkap'] ?? "Petugas",
            );
            await prefs.setString('pangkat', p['pangkat'] ?? "-");
            await prefs.setString('nrp', p['nrp'] ?? "-");
            await prefs.setString(
              'status_aktif',
              p['status_aktif'] ?? "online",
            );

            if (p['foto_profil'] != null) {
              String photoUrl =
                  "http://10.0.2.2:8000/storage/${p['foto_profil']}";
              await prefs.setString('foto_profil', photoUrl);
            }
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Error Login: $e");
      return false;
    }
  }

  // --- UPDATE FOTO PROFIL ---
  Future<String?> updateProfilePhoto(File imageFile) async {
    try {
      final token = await getToken();
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/user/photo'),
      );
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      request.files.add(
        await http.MultipartFile.fromPath('foto', imageFile.path),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String newUrl = data['url'];
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('foto_profil', newUrl);
        return newUrl;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // --- AMBIL PROFIL (SYNC) ---
  Future<Map<String, dynamic>> getProfile() async {
    try {
      final token = await getToken();
      final response = await http
          .get(
            Uri.parse('$baseUrl/user'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) return jsonDecode(response.body);
      throw Exception('Gagal profil');
    } catch (e) {
      throw Exception('Koneksi bermasalah: $e');
    }
  }

  // --- UPDATE LOKASI ---
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
      return false;
    }
  }

  // --- AMBIL LOKASI REKAN ---
  Future<List<dynamic>> getAllPersonnelLocations() async {
    try {
      final token = await getToken();
      final response = await http
          .get(
            Uri.parse('$baseUrl/locations'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) return jsonDecode(response.body);
      return [];
    } catch (e) {
      return [];
    }
  }

  // --- KIRIM LAPORAN / ADUAN (MULTIPART) ---
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

      request.fields['judul_kejadian'] = judul;
      request.fields['tipe_laporan'] = tipe;
      request.fields['deskripsi'] = deskripsi;
      request.fields['prioritas'] = prioritas;
      request.fields['latitude'] = lat.toString();
      request.fields['longitude'] = lng.toString();
      request.fields['status_penanganan'] = 'menunggu konfirmasi';

      if (foto != null) {
        request.files.add(
          await http.MultipartFile.fromPath('foto_bukti', foto.path),
        );
      }

      var streamedResponse = await request.send().timeout(
        const Duration(seconds: 20),
      );
      var response = await http.Response.fromStream(streamedResponse);
      return response.statusCode == 201 || response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // --- WRAPPER KIRIM ADUAN (YANG TADI HILANG) ---
  Future<bool> kirimAduan({
    required String judul,
    required String isiLaporan,
    required double lat,
    required double lng,
    String tipeLaporan = 'aduan/kejadian',
    File? foto,
  }) async {
    return await sendReport(
      judul: judul,
      deskripsi: isiLaporan,
      tipe: tipeLaporan,
      prioritas: 'sedang',
      lat: lat,
      lng: lng,
      foto: foto,
    );
  }

  // --- AMBIL RIWAYAT LAPORAN (YANG TADI HILANG) ---
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

  // --- LAIN-LAIN ---
  Future<bool> logout() async {
    try {
      final token = await getToken();
      await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<List<dynamic>> getJadwal() async {
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/jadwal-mobile'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode == 200) return jsonDecode(res.body)['data'] ?? [];
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getLatestInstruction() async {
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/latest-instruction'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return res.statusCode == 200 ? jsonDecode(res.body) : null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getRingkasan() async {
    try {
      final token = await getToken();
      final res = await http.get(
        Uri.parse('$baseUrl/ringkasan-laporan'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return res.statusCode == 200
          ? jsonDecode(res.body)
          : {'laporan_count': 0, 'checkpoint_count': 0};
    } catch (e) {
      return {'laporan_count': 0, 'checkpoint_count': 0};
    }
  }
}
