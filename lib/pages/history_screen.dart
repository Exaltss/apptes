import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<dynamic>> _historyFuture;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // Inisialisasi Tab Controller untuk 2 kategori
    _tabController = TabController(length: 2, vsync: this);
    _refreshHistory();
  }

  void _refreshHistory() {
    setState(() {
      _historyFuture = ApiService().getHistoryLaporan();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF151B25), // Tema Gelap
      appBar: AppBar(
        // Perubahan Nama menjadi "Riwayat" dengan Font Bold & Putih
        title: const Text(
          "Riwayat",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        backgroundColor: const Color(0xFF1F2937),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orangeAccent),
            onPressed: _refreshHistory,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.orangeAccent,
          indicatorWeight: 3,
          labelColor: Colors.orangeAccent,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: "Checkpoint", icon: Icon(Icons.location_on, size: 20)),
            Tab(text: "Aduan", icon: Icon(Icons.report_problem, size: 20)),
          ],
        ),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            );
          } else if (snapshot.hasError) {
            return Center(
              child: Text(
                "Gagal memuat data: ${snapshot.error}",
                style: const TextStyle(color: Colors.redAccent),
              ),
            );
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return _buildEmptyState();
          }

          final data = snapshot.data!;

          // Filter data berdasarkan tipe laporan
          final checkpointData = data
              .where(
                (item) => (item['tipe_laporan'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains('checkpoint'),
              )
              .toList();
          final aduanData = data
              .where(
                (item) => (item['tipe_laporan'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains('aduan'),
              )
              .toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildListView(checkpointData, "Belum ada riwayat checkpoint."),
              _buildListView(aduanData, "Belum ada riwayat aduan."),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_toggle_off,
            size: 80,
            color: Colors.grey.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 10),
          const Text(
            "Belum ada riwayat.",
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildListView(List<dynamic> listData, String emptyMessage) {
    if (listData.isEmpty) {
      return Center(
        child: Text(emptyMessage, style: const TextStyle(color: Colors.grey)),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _refreshHistory(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: listData.length,
        itemBuilder: (context, index) {
          final item = listData[index];
          final String title =
              item['judul_laporan'] ?? item['title'] ?? 'Laporan Patroli';
          final String dateRaw =
              item['created_at'] ?? DateTime.now().toString();
          final String status = item['status_penanganan'] ?? 'selesai';

          String formattedDate = "Waktu tidak diketahui";
          try {
            DateTime date = DateTime.parse(dateRaw);
            formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(date);
          } catch (e) {
            formattedDate = dateRaw;
          }

          return Card(
            color: const Color(0xFF1F2937),
            elevation: 2,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(
                color: Colors.grey.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                radius: 25,
                backgroundColor: _getStatusColor(status).withValues(alpha: 0.1),
                child: Icon(
                  _getStatusIcon(status),
                  color: _getStatusColor(status),
                  size: 28,
                ),
              ),
              title: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6.0),
                child: Text(
                  formattedDate,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _getStatusColor(status).withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: _getStatusColor(status),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'selesai':
      case 'diterima':
        return Colors.greenAccent;
      case 'proses':
      case 'menunggu konfirmasi':
        return Colors.blueAccent;
      case 'ditolak':
      case 'darurat':
        return Colors.redAccent;
      default:
        return Colors.orangeAccent;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'selesai':
      case 'diterima':
        return Icons.check_circle_outline;
      case 'proses':
      case 'menunggu konfirmasi':
        return Icons.hourglass_empty_rounded;
      case 'ditolak':
        return Icons.highlight_off_rounded;
      case 'darurat':
        return Icons.warning_amber_rounded;
      default:
        return Icons.info_outline;
    }
  }
}
