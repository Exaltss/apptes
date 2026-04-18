import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_service.dart';

class AduanScreen extends StatefulWidget {
  final VoidCallback? onSuccess;
  const AduanScreen({super.key, this.onSuccess});
  @override
  State<AduanScreen> createState() => _AduanScreenState();
}

class _AduanScreenState extends State<AduanScreen> {
  final _judulCtrl = TextEditingController();
  final _deskripsiCtrl = TextEditingController();
  String _prioritas = "sedang";
  Position? _currentPosition;
  File? _mediaFile;
  bool _isVideo = false;
  bool _isSending = false;
  final _picker = ImagePicker();

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

  Future<void> _getLocation() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      ).timeout(const Duration(seconds: 5));
      if (mounted) setState(() => _currentPosition = pos);
    } catch (_) {}
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    try {
      if (isVideo) {
        final f = await _picker.pickVideo(
          source: source,
          maxDuration: const Duration(minutes: 3),
        );
        if (f != null) {
          setState(() {
            _mediaFile = File(f.path);
            _isVideo = true;
          });
        }
      } else {
        final f = await _picker.pickImage(source: source, imageQuality: 60);
        if (f != null) {
          setState(() {
            _mediaFile = File(f.path);
            _isVideo = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Media error: $e");
    }
  }

  Future<void> _kirimLaporan() async {
    setState(() => _isSending = true);
    try {
      if (_currentPosition == null) {
        try {
          _currentPosition = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
            ),
          ).timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
      double lat = _currentPosition?.latitude ?? -8.0667;
      double lng = _currentPosition?.longitude ?? 111.9000;

      bool success = await ApiService().sendReport(
        judul: _judulCtrl.text,
        deskripsi: _deskripsiCtrl.text,
        tipe: 'aduan/kejadian',
        prioritas: _prioritas,
        lat: lat,
        lng: lng,
        foto: _mediaFile,
      );

      if (!mounted) return;
      setState(() => _isSending = false);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text("Laporan Berhasil Terkirim!"),
          ),
        );
        _judulCtrl.clear();
        _deskripsiCtrl.clear();
        setState(() {
          _mediaFile = null;
          _isVideo = false;
        });
        widget.onSuccess?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.red,
            content: Text("Gagal mengirim. Cek koneksi atau ukuran file."),
          ),
        );
      }
    } catch (e) {
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
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                      // ✅ JUDUL DIGANTI "LAPORAN"
                      const Text(
                        "Laporan",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),

                  _buildLabel("Foto / Video Bukti Kejadian"),
                  GestureDetector(
                    onTap: _showMediaOptions,
                    child: Container(
                      width: double.infinity,
                      height: 200,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C3542),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _mediaFile != null
                              ? Colors.greenAccent
                              : Colors.white10,
                        ),
                      ),
                      child: _mediaFile == null
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
                                  "Klik untuk Lampirkan Foto / Video",
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            )
                          : _isVideo
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.videocam,
                                  color: Colors.greenAccent,
                                  size: 55,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _mediaFile!.path.split('/').last,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  "✓ Video terpilih",
                                  style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(_mediaFile!, fit: BoxFit.cover),
                            ),
                    ),
                  ),

                  _buildLabel("Judul Kejadian"),
                  TextField(
                    controller: _judulCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: _inputDecoration(
                      "Contoh: Kecelakaan atau Tawuran",
                    ),
                  ),

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
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
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
                        onChanged: (v) => setState(() => _prioritas = v!),
                      ),
                    ),
                  ),

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
                        "KIRIM LAPORAN",
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
          if (_isSending)
            Container(
              color: Colors.black.withValues(alpha: .7),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.yellow),
                    SizedBox(height: 15),
                    Text(
                      "Mengirim Laporan...",
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
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              "Pilih Media",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.white),
            title: const Text(
              "Kamera — Foto",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _pickMedia(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: Colors.white),
            title: const Text(
              "Galeri — Foto",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _pickMedia(ImageSource.gallery);
            },
          ),
          ListTile(
            leading: const Icon(Icons.videocam, color: Colors.greenAccent),
            title: const Text(
              "Kamera — Video",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _pickMedia(ImageSource.camera, isVideo: true);
            },
          ),
          ListTile(
            leading: const Icon(Icons.video_library, color: Colors.greenAccent),
            title: const Text(
              "Galeri — Video",
              style: TextStyle(color: Colors.white),
            ),
            onTap: () {
              Navigator.pop(ctx);
              _pickMedia(ImageSource.gallery, isVideo: true);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

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
          "Kirim laporan sekarang?",
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
