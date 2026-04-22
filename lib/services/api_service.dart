import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String domain = 'https://tulgungpatrol.my.id';
  static const String baseUrl = '$domain/api';

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static bool _isVideo(String path) {
    final ext = path.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi', '3gp', 'mkv', 'webm'].contains(ext);
  }

  static MediaType _mediaType(String path) {
    final ext = path.split('.').last.toLowerCase();
    if (_isVideo(path)) {
      return MediaType('video', ext == 'mov' ? 'quicktime' : ext);
    }
    return MediaType('image', ext == 'jpg' ? 'jpeg' : ext);
  }

  // ── LOGIN ──
  Future<bool> login(String username, String password) async {
    try {
      debugPrint('--- LOGIN: $username ---');
      final res = await http
          .post(
            Uri.parse('$baseUrl/login'),
            body: {'username': username, 'password': password},
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', data['access_token']);

        if (data['user'] != null) {
          await prefs.setInt('user_id', data['user']['id']);
          await prefs.setString('username', data['user']['username'] ?? '-');
          final p = data['user']['personnel'];
          if (p != null) {
            await prefs.setString(
              'nama_lengkap',
              p['nama_lengkap'] ?? 'Petugas',
            );
            await prefs.setString('pangkat', p['pangkat'] ?? '-');
            await prefs.setString('nrp', p['nrp'] ?? '-');
            await prefs.setString(
              'status_aktif',
              p['status_aktif'] ?? 'online',
            );
            if (p['foto_profil'] != null &&
                p['foto_profil'].toString().isNotEmpty) {
              final fp = p['foto_profil'].toString();
              final url = fp.startsWith('http')
                  ? fp
                  : fp.startsWith('profile_photos/')
                  ? '$domain/public/$fp'
                  : '$domain/storage/$fp';
              await prefs.setString('foto_profil', url);
            }
          }
        }
        debugPrint('Login OK');
        return true;
      }
      debugPrint('Login gagal: ${res.statusCode} ${res.body}');
      return false;
    } catch (e) {
      debugPrint('Login error: $e');
      return false;
    }
  }

  // ── UPDATE FOTO PROFIL ──
  Future<String?> updateProfilePhoto(File file) async {
    try {
      final token = await getToken();
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/user/photo'),
      );
      req.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      req.files.add(
        await http.MultipartFile.fromPath(
          'foto',
          file.path,
          contentType: _mediaType(file.path),
        ),
      );
      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final res = await http.Response.fromStream(streamed);
      if (res.statusCode == 200) {
        final url = jsonDecode(res.body)['url'].toString();
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('foto_profil', url);
        return url;
      }
      return null;
    } catch (e) {
      debugPrint('Upload foto error: $e');
      return null;
    }
  }

  // ── AMBIL PROFIL ──
  Future<Map<String, dynamic>> getProfile() async {
    final token = await getToken();
    final res = await http
        .get(
          Uri.parse('$baseUrl/user'),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body);
    throw Exception('Gagal memuat profil');
  }

  // ── UPDATE LOKASI (TIME-BASED + speed & heading) ──
  Future<bool> updatePatrolStatus({
    required double lat,
    required double long,
    required String status,
    double speed = 0.0, // m/s dari GPS
    double heading = 0.0, // derajat 0-360
  }) async {
    try {
      final token = await getToken();
      final res = await http
          .post(
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
              'speed': speed,
              'heading': heading,
            }),
          )
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // ── LOKASI REKAN ──
  Future<List<dynamic>> getAllPersonnelLocations() async {
    try {
      final token = await getToken();
      final res = await http
          .get(
            Uri.parse('$baseUrl/locations'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) return jsonDecode(res.body);
      return [];
    } catch (_) {
      return [];
    }
  }

  // ── KIRIM LAPORAN / ADUAN (FOTO & VIDEO) ──
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
      final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/reports'));
      req.headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      });
      req.fields['judul_kejadian'] = judul;
      req.fields['tipe_laporan'] = tipe;
      req.fields['deskripsi'] = deskripsi;
      req.fields['prioritas'] = prioritas;
      req.fields['latitude'] = lat.toString();
      req.fields['longitude'] = lng.toString();
      req.fields['status_penanganan'] = 'menunggu konfirmasi';

      if (foto != null) {
        final isVid = _isVideo(foto.path);
        debugPrint('Upload ${isVid ? "VIDEO" : "FOTO"}: ${foto.path}');
        req.files.add(
          http.MultipartFile(
            'foto_bukti',
            foto.openRead(),
            await foto.length(),
            filename: foto.path.split('/').last,
            contentType: _mediaType(foto.path),
          ),
        );
      }

      final streamed = await req.send().timeout(const Duration(minutes: 3));
      final res = await http.Response.fromStream(streamed);
      debugPrint('Upload response: ${res.statusCode} ${res.body}');
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('sendReport error: $e');
      return false;
    }
  }

  Future<bool> kirimAduan({
    required String judul,
    required String isiLaporan,
    required double lat,
    required double lng,
    String tipeLaporan = 'aduan/kejadian',
    File? foto,
  }) async {
    return sendReport(
      judul: judul,
      deskripsi: isiLaporan,
      tipe: tipeLaporan,
      prioritas: 'sedang',
      lat: lat,
      lng: lng,
      foto: foto,
    );
  }

  // ── RIWAYAT ──
  Future<List<dynamic>> getHistoryLaporan() async {
    try {
      final token = await getToken();
      final res = await http
          .get(
            Uri.parse('$baseUrl/reports'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return jsonDecode(res.body)['data'] ?? [];
      return [];
    } catch (_) {
      return [];
    }
  }

  // ── LOGOUT ──
  Future<bool> logout() async {
    try {
      final token = await getToken();
      await http
          .post(
            Uri.parse('$baseUrl/logout'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    return true;
  }

  // ── JADWAL & INSTRUKSI ──
  Future<List<dynamic>> getJadwal() async {
    try {
      final token = await getToken();
      final res = await http
          .get(
            Uri.parse('$baseUrl/jadwal-mobile'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return jsonDecode(res.body)['data'] ?? [];
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> getLatestInstruction() async {
    try {
      final token = await getToken();
      final res = await http
          .get(
            Uri.parse('$baseUrl/latest-instruction'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200 ? jsonDecode(res.body) : null;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> getRingkasan() async {
    try {
      final token = await getToken();
      final res = await http
          .get(
            Uri.parse('$baseUrl/ringkasan-laporan'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return jsonDecode(res.body);
      return {'laporan_count': 0, 'checkpoint_count': 0};
    } catch (_) {
      return {'laporan_count': 0, 'checkpoint_count': 0};
    }
  }
}
