import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _api = ApiService();
  final _picker = ImagePicker();

  String nama = '...';
  String pangkat = '...';
  String noWa = '...'; // hanya info, tidak ada link WA
  String? fotoUrl;
  String username = '...';
  String status = '...';

  bool _isInitialLoading = true;
  bool _isUploading = false;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
    // Auto-sync setiap 30 detik
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _syncProfileFromServer();
    });
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      nama = prefs.getString('nama_lengkap') ?? 'Petugas';
      pangkat = prefs.getString('pangkat') ?? '-';
      noWa = prefs.getString('nrp') ?? '-';
      username = prefs.getString('username') ?? '-';
      status = prefs.getString('status_aktif') ?? 'offline';
      final saved = prefs.getString('foto_profil');
      fotoUrl = (saved != null && !saved.contains('10.0.2.2')) ? saved : null;
      _isInitialLoading = false;
    });
    _syncProfileFromServer();
  }

  Future<void> _syncProfileFromServer() async {
    try {
      final data = await _api.getProfile();
      final p = data['personnel'];
      if (p == null || !mounted) return;
      final prefs = await SharedPreferences.getInstance();
      String? newFoto;
      if (p['foto_profil'] != null && p['foto_profil'].toString().isNotEmpty) {
        final fp = p['foto_profil'].toString();
        newFoto = fp.startsWith('http')
            ? fp
            : fp.startsWith('profile_photos/')
            ? 'https://tulgungpatrol.my.id/public/$fp'
            : 'https://tulgungpatrol.my.id/storage/$fp';
        await prefs.setString('foto_profil', newFoto);
      }
      setState(() {
        nama = p['nama_lengkap'] ?? nama;
        pangkat = p['pangkat'] ?? pangkat;
        noWa = p['nrp'] ?? noWa;
        status = p['status_aktif'] ?? status;
        if (newFoto != null) fotoUrl = newFoto;
      });
    } catch (e) {
      debugPrint('Sync profil error: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final img = await _picker.pickImage(source: source, imageQuality: 50);
    if (img != null) await _uploadPhoto(File(img.path));
  }

  Future<void> _uploadPhoto(File file) async {
    setState(() => _isUploading = true);
    final url = await _api.updateProfilePhoto(file);
    if (!mounted) return;
    setState(() {
      _isUploading = false;
      if (url != null) fotoUrl = url;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          url != null ? 'Foto berhasil diperbarui' : 'Gagal mengunggah foto',
        ),
        backgroundColor: url != null ? Colors.green : Colors.red,
      ),
    );
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222B36),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text(
                'Ganti Foto Profil',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: Colors.blueAccent,
              ),
              title: const Text(
                'Pilih dari Galeri',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blueAccent),
              title: const Text(
                'Ambil dari Kamera',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _handleLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF222B36),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Yakin ingin keluar?',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Ya, Keluar',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _api.logout();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF151B25),
      appBar: AppBar(
        title: const Text(
          'Profil Saya',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF151B25),
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.yellow),
            onPressed: _syncProfileFromServer,
          ),
        ],
      ),
      body: _isInitialLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.yellow))
          : RefreshIndicator(
              onRefresh: _syncProfileFromServer,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(25),
                child: Column(
                  children: [
                    // ── Foto profil ──
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.blueAccent.withValues(alpha: .5),
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: 60,
                              backgroundColor: const Color(0xFF222B36),
                              backgroundImage: fotoUrl != null
                                  ? NetworkImage(fotoUrl!)
                                  : null,
                              child: fotoUrl == null
                                  ? const Icon(
                                      Icons.person,
                                      size: 70,
                                      color: Colors.blueAccent,
                                    )
                                  : null,
                            ),
                          ),
                          if (_isUploading)
                            const Positioned.fill(
                              child: CircularProgressIndicator(
                                color: Colors.yellow,
                              ),
                            ),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: _showPickerOptions,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                  color: Colors.blueAccent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.camera_enhance,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      nama,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      pangkat,
                      style: const TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    const SizedBox(height: 28),

                    // ── Nomor WA — hanya info, TIDAK ada tap ke WhatsApp ──
                    _buildInfoTile(
                      Icons.phone,
                      'NOMOR WHATSAPP',
                      noWa,
                      color: Colors.greenAccent,
                    ),
                    _buildInfoTile(
                      Icons.account_circle,
                      'USERNAME AKUN',
                      username,
                    ),
                    _buildInfoTile(
                      Icons.info_outline,
                      'STATUS SAAT INI',
                      status.toUpperCase(),
                    ),

                    const SizedBox(height: 40),

                    // ── Tombol Logout ──
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(
                            alpha: .1,
                          ),
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        onPressed: _handleLogout,
                        icon: const Icon(Icons.logout),
                        label: const Text(
                          'LOGOUT',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInfoTile(
    IconData icon,
    String label,
    String value, {
    Color? color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF222B36),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, color: color ?? Colors.blueAccent, size: 24),
          const SizedBox(width: 15),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 10),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
