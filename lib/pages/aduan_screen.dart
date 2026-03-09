import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';

class AduanScreen extends StatefulWidget {
  final VoidCallback?
  onSuccess; // Digunakan untuk kembali ke Beranda Tab tanpa error Navigator
  const AduanScreen({super.key, this.onSuccess});

  @override
  State<AduanScreen> createState() => _AduanScreenState();
}

class _AduanScreenState extends State<AduanScreen> {
  // Kontroler Input
  final TextEditingController _judulCtrl = TextEditingController();
  final TextEditingController _deskripsiCtrl = TextEditingController();
  String _prioritas = "sedang";

  // Data Lokasi & Foto
  Position? _currentPosition;
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  // State UI
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  @override
  void dispose() {
    _judulCtrl.dispose();
    _deskripsiCtrl.dispose();
    super.dispose();
  }

  // --- FUNGSI AMBIL LOKASI ---
  Future<void> _getLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 5));

      if (mounted) {
        setState(() => _currentPosition = position);
      }
    } catch (e) {
      debugPrint("GPS Error Awal: $e");
    }
  }

  // --- FUNGSI PILIH FOTO ---
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 60, // Kompresi agar upload lebih cepat
      );
      if (pickedFile != null) {
        setState(() => _imageFile = File(pickedFile.path));
      }
    } catch (e) {
      debugPrint("Gagal mengambil media: $e");
    }
  }

  // --- PROSES KIRIM DATA KE BACKEND ---
  Future<void> _kirimLaporan() async {
    setState(() => _isSending = true);

    try {
      final api = ApiService();

      // Logika GPS Cadangan: Jika belum dapat lokasi, coba ambil sekali lagi
      if (_currentPosition == null) {
        try {
          _currentPosition = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          ).timeout(const Duration(seconds: 3));
        } catch (e) {
          debugPrint(
            "Gagal lock lokasi instan, menggunakan koordinat default.",
          );
        }
      }

      double lat = _currentPosition?.latitude ?? -8.0667;
      double lng = _currentPosition?.longitude ?? 111.9000;

      // Panggil API multipart
      bool success = await api.sendReport(
        judul: _judulCtrl.text,
        deskripsi: _deskripsiCtrl.text,
        tipe: 'aduan/kejadian',
        prioritas: _prioritas,
        lat: lat,
        lng: lng,
        foto: _imageFile,
      );

      if (!mounted) return;
      setState(() => _isSending = false);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text("Laporan Berhasil Terkirim ke Pusat!"),
          ),
        );

        // Reset Form
        _judulCtrl.clear();
        _deskripsiCtrl.clear();
        setState(() => _imageFile = null);

        // Berpindah tab ke Beranda melalui callback
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text(
              "Gagal mengirim data. Cek koneksi internet atau ukuran foto.",
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("Crash di UI Aduan: $e");
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF151B25),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- HEADER ---
                  Row(
                    children: [
                      InkWell(
                        onTap: widget.onSuccess,
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 15),
                      const Text(
                        "Form Aduan Digital",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),

                  // --- WIDGET FOTO ---
                  _buildLabel("Foto Bukti Kejadian"),
                  GestureDetector(
                    onTap: () => _showMediaOptions(),
                    child: Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C3542),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: _imageFile == null
                          ? const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_a_photo,
                                  color: Colors.grey,
                                  size: 45,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  "Klik untuk Lampirkan Foto",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(_imageFile!, fit: BoxFit.cover),
                            ),
                    ),
                  ),

                  // --- INPUT JUDUL ---
                  _buildLabel("Judul Kejadian"),
                  TextField(
                    controller: _judulCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                      "Contoh: Kecelakaan atau Tawuran",
                    ),
                  ),

                  // --- DROPDOWN PRIORITAS ---
                  _buildLabel("Prioritas Keamanan"),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2C3542),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _prioritas,
                        dropdownColor: const Color(0xFF2C3542),
                        isExpanded: true,
                        icon: const Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.white,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: "sedang",
                            child: Text("Sedang (Normal)"),
                          ),
                          DropdownMenuItem(
                            value: "tinggi",
                            child: Text("Tinggi (Gawat)"),
                          ),
                        ],
                        onChanged: (val) => setState(() => _prioritas = val!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),

                  // --- INPUT DESKRIPSI ---
                  _buildLabel("Kronologi Kejadian"),
                  TextField(
                    controller: _deskripsiCtrl,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                      "Jelaskan detail kejadian secara singkat...",
                    ),
                  ),

                  const SizedBox(height: 35),

                  // --- TOMBOL SUBMIT ---
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: _isSending ? null : _showConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFC107),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "KIRIM DATA LAPORAN",
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // --- LOADING OVERLAY ---
          if (_isSending)
            Container(
              color: Colors.black.withValues(alpha: 0.7),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.yellow),
                    SizedBox(height: 15),
                    Text(
                      "Memproses Laporan...",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // --- UI HELPER: MEDIA SOURCE SHEET ---
  void _showMediaOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222B36),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.white),
            title: const Text(
              "Gunakan Kamera",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Colors.white),
            title: const Text(
              "Pilih dari Galeri",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _pickImage(ImageSource.gallery);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // --- UI HELPER: TEXT STYLES ---
  Widget _buildLabel(String t) => Padding(
    padding: const EdgeInsets.only(top: 15, bottom: 8),
    child: Text(
      t,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.bold,
        fontSize: 14,
      ),
    ),
  );

  InputDecoration _inputDecoration(String h) => InputDecoration(
    hintText: h,
    hintStyle: const TextStyle(color: Colors.grey),
    filled: true,
    fillColor: const Color(0xFF2C3542),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
  );

  // --- UI HELPER: CONFIRMATION DIALOG ---
  void _showConfirm() {
    if (_judulCtrl.text.isEmpty || _deskripsiCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mohon lengkapi judul dan kronologi!")),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF222B36),
        title: const Text("Konfirmasi", style: TextStyle(color: Colors.white)),
        content: const Text(
          "Pastikan data sudah benar. Kirim laporan sekarang?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("BATAL", style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _kirimLaporan();
            },
            child: const Text(
              "YA, KIRIM",
              style: TextStyle(color: Colors.green),
            ),
          ),
        ],
      ),
    );
  }
}
