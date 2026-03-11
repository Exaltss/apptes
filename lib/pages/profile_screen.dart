import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiService _apiService = ApiService();
  final ImagePicker _picker = ImagePicker();

  // Data State
  String nama = "Memuat...";
  String pangkat = "...";
  String nrp = "...";
  String? fotoUrl;
  String username = "...";
  String status = "...";

  bool _isInitialLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadLocalData(); // Prioritas: Ambil data dari memori HP (Instan)
  }

  // --- 1. AMBIL DATA LOKAL (BIAR CEPAT) ---
  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      nama = prefs.getString('nama_lengkap') ?? "Petugas";
      pangkat = prefs.getString('pangkat') ?? "-";
      nrp = prefs.getString('nrp') ?? "-";
      fotoUrl = prefs.getString('foto_profil');
      username = prefs.getString('username') ?? "-";
      status = prefs.getString('status_aktif') ?? "offline";
      _isInitialLoading = false;
    });
    // Setelah data lokal muncul, tetap sync ke server di latar belakang
    _syncProfileFromServer();
  }

  // --- 2. SYNC KE SERVER (LATAR BELAKANG) ---
  Future<void> _syncProfileFromServer() async {
    try {
      final data = await _apiService.getProfile();
      final p = data['personnel'];
      if (p != null) {
        final prefs = await SharedPreferences.getInstance();
        setState(() {
          nama = p['nama_lengkap'] ?? nama;
          pangkat = p['pangkat'] ?? pangkat;
          nrp = p['nrp'] ?? nrp;
          status = p['status_aktif'] ?? status;
          // Perbarui foto jika ada perubahan di server
          if (p['foto_profil'] != null) {
            fotoUrl = "http://10.0.2.2:8000/storage/${p['foto_profil']}";
            prefs.setString('foto_profil', fotoUrl!);
          }
        });
      }
    } catch (e) {
      debugPrint("Gagal sync profil: $e");
    }
  }

  // --- 3. LOGIKA PILIH FOTO ---
  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 50, // Kompres agar upload cepat
    );

    if (image != null) {
      _uploadPhoto(File(image.path));
    }
  }

  // --- 4. UPLOAD FOTO KE SERVER ---
  Future<void> _uploadPhoto(File imageFile) async {
    setState(() => _isUploading = true);

    final newUrl = await _apiService.updateProfilePhoto(imageFile);

    setState(() => _isUploading = false);

    if (newUrl != null) {
      setState(() => fotoUrl = newUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Foto profil berhasil diperbarui")),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Gagal mengunggah foto ke server")),
        );
      }
    }
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222B36),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                "Ganti Foto Profil",
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
                "Pilih dari Galeri",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blueAccent),
              title: const Text(
                "Ambil Kamera",
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _handleLogout() async {
    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF222B36),
            title: const Text("Logout", style: TextStyle(color: Colors.white)),
            content: const Text(
              "Apakah Anda yakin ingin keluar?",
              style: TextStyle(color: Colors.grey),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("Batal"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  "Ya, Keluar",
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      await _apiService.logout();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF151B25),
      appBar: AppBar(
        title: const Text(
          "Profil Saya",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF151B25),
        elevation: 0,
        centerTitle: true,
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
                    // --- HEADER: FOTO PROFIL DENGAN TOMBOL EDIT ---
                    Center(
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.blueAccent.withValues(alpha: 0.5),
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
                            bottom: 5,
                            right: 5,
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
                    const SizedBox(height: 20),
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
                    const SizedBox(height: 30),

                    // --- DETAIL INFO BOXES ---
                    _buildInfoTile(Icons.badge, "NRP", nrp),
                    _buildInfoTile(
                      Icons.account_circle,
                      "USERNAME AKUN",
                      username,
                    ),
                    _buildInfoTile(
                      Icons.info_outline,
                      "STATUS SAAT INI",
                      status.toUpperCase(),
                    ),

                    const SizedBox(height: 40),

                    // --- TOMBOL LOGOUT ---
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(
                            alpha: 0.1,
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
                          "LOGOUT",
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

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFF222B36),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 24),
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
