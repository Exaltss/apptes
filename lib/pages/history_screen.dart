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
    // Tab Controller untuk membagi antara Checkpoint dan Aduan
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
      backgroundColor: const Color(0xFF151B25), // Background gelap
      appBar: AppBar(
        title: const Text(
          "Riwayat Aktivitas",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: const Color(0xFF1F2937),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshHistory,
          ),
        ],
        // Menambahkan TabBar di bawah AppBar
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.orange, // Garis bawah tab
          indicatorWeight: 3,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: "Riwayat Checkpoint", icon: Icon(Icons.location_on)),
            Tab(text: "Riwayat Aduan", icon: Icon(Icons.report_problem)),
          ],
        ),
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _historyFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.orange),
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

          // --- MEMISAHKAN DATA BERDASARKAN TIPE LAPORAN ---
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
              // --- TAB 1: LIST CHECKPOINT ---
              checkpointData.isEmpty
                  ? _buildEmptyState()
                  : _buildListView(checkpointData),

              // --- TAB 2: LIST ADUAN ---
              aduanData.isEmpty
                  ? _buildEmptyState()
                  : _buildListView(aduanData),
            ],
          );
        },
      ),
    );
  }

  // --- FUNGSI TAMPILAN JIKA DATA KOSONG ---
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: Colors.grey.withValues(alpha: 0.5),
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

  // --- FUNGSI BUILDER LISTVIEW ---
  Widget _buildListView(List<dynamic> listData) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: listData.length,
      itemBuilder: (context, index) {
        final item = listData[index];
        final String title =
            item['judul_laporan'] ?? item['title'] ?? 'Tanpa Judul';
        final String dateRaw = item['created_at'] ?? DateTime.now().toString();
        final String status =
            item['status_penanganan'] ?? item['status'] ?? 'selesai';

        DateTime date = DateTime.parse(dateRaw);
        String formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(date);

        return Card(
          color: const Color(0xFF1F2937), // Warna card gelap
          elevation: 4,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(
              color: Colors.grey.withValues(alpha: 0.2),
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
              backgroundColor: _getStatusColor(status).withValues(alpha: 0.2),
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
                fontSize: 16,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6.0),
              child: Text(
                formattedDate,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                // PERBAIKAN ERROR: Menggunakan Border.all, bukan BorderSide
                border: Border.all(color: _getStatusColor(status), width: 1),
              ),
              child: Text(
                status.toUpperCase(),
                style: TextStyle(
                  color: _getStatusColor(status),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // --- PENENTUAN WARNA & ICON STATUS ---
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
        return Icons.check_circle;
      case 'proses':
      case 'menunggu konfirmasi':
        return Icons.sync;
      case 'ditolak':
        return Icons.cancel;
      case 'darurat':
        return Icons.warning_rounded;
      default:
        return Icons.access_time_filled;
    }
  }
}
