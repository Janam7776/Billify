// ════════════════════════════════════════════════════════════
//  client_screens.dart — Billify Clients Module  (v2)
//  Fully separated client-info vs reel-data flows.
//  Flow: ClientListScreen → ClientDetailScreen
//        Add: ClientInfoFormScreen → ClientReelFormScreen (multi-reel)
//        Edit client info: ClientInfoFormScreen (standalone)
//        Edit reel: ClientReelFormScreen (standalone)
// ════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'main.dart'
    show BillifyColors, AppRoutes, BillifyDrawer, BillifyDialog, BillifyC;
import 'web_layout.dart' show WebScaffold;
import 'theme_controller.dart' show ThemeController;
import 'client_export_service.dart' show ClientExportSheet;

// ════════════════════════════════════════════════════════════
//  REEL MODEL
// ════════════════════════════════════════════════════════════

class ReelEntry {
  final int index;
  final DateTime? projectStartDate;
  final String shootCategory;
  final String customShootCategory;
  final String reelCategory;
  final String customReelCategory;
  final double paymentAmount;
  final String paymentType;
  final String customPaymentType;
  final String paymentStatus;

  const ReelEntry({
    required this.index,
    this.projectStartDate,
    required this.shootCategory,
    this.customShootCategory = '',
    required this.reelCategory,
    this.customReelCategory = '',
    required this.paymentAmount,
    required this.paymentType,
    this.customPaymentType = '',
    required this.paymentStatus,
  });

  static String _sfx(int idx) => idx == 1 ? '' : '$idx';

  factory ReelEntry.fromMap(Map<String, dynamic> d, int idx) {
    final s = _sfx(idx);
    return ReelEntry(
      index: idx,
      projectStartDate: (d['projectStartDate$s'] as Timestamp?)?.toDate(),
      shootCategory: d['shootCategory$s'] as String? ?? 'Mobile Shoot',
      customShootCategory: d['customShootCategory$s'] as String? ?? '',
      reelCategory: d['reelCategory$s'] as String? ?? 'Promotional Reel',
      customReelCategory: d['customReelCategory$s'] as String? ?? '',
      paymentAmount: ((d['paymentAmount$s'] ?? 0) as num).toDouble(),
      paymentType: d['paymentType$s'] as String? ?? 'Cash',
      customPaymentType: d['customPaymentType$s'] as String? ?? '',
      paymentStatus: d['paymentStatus$s'] as String? ?? 'Pending',
    );
  }

  Map<String, dynamic> toFields() {
    final s = _sfx(index);
    return {
      'projectStartDate$s':
      projectStartDate != null ? Timestamp.fromDate(projectStartDate!) : null,
      'shootCategory$s': shootCategory,
      'customShootCategory$s': customShootCategory,
      'reelCategory$s': reelCategory,
      'customReelCategory$s': customReelCategory,
      'paymentAmount$s': paymentAmount,
      'paymentType$s': paymentType,
      'customPaymentType$s': customPaymentType,
      'paymentStatus$s': paymentStatus,
    };
  }

  String get displayShootCategory =>
      shootCategory == 'Custom' ? customShootCategory : shootCategory;
  String get displayReelCategory =>
      reelCategory == 'Custom' ? customReelCategory : reelCategory;
  String get displayPaymentType =>
      paymentType == 'Other' ? customPaymentType : paymentType;

  static int countReels(Map<String, dynamic> d) {
    int count = 0;
    if (d.containsKey('reelCategory')) count = 1;
    int i = 2;
    while (d.containsKey('reelCategory$i')) {
      count = i;
      i++;
    }
    return count;
  }

  /// Check if a specific reel index actually exists in Firestore data
  static bool reelExists(Map<String, dynamic> d, int idx) {
    final key = idx == 1 ? 'reelCategory' : 'reelCategory$idx';
    return d.containsKey(key);
  }

  /// Build a map of fields to DELETE for this reel index (for Firestore update)
  Map<String, dynamic> toDeleteFields() {
    final s = _sfx(index);
    return {
      'projectStartDate$s': FieldValue.delete(),
      'shootCategory$s': FieldValue.delete(),
      'customShootCategory$s': FieldValue.delete(),
      'reelCategory$s': FieldValue.delete(),
      'customReelCategory$s': FieldValue.delete(),
      'paymentAmount$s': FieldValue.delete(),
      'paymentType$s': FieldValue.delete(),
      'customPaymentType$s': FieldValue.delete(),
      'paymentStatus$s': FieldValue.delete(),
    };
  }
}

// ════════════════════════════════════════════════════════════
//  CLIENT MODEL
// ════════════════════════════════════════════════════════════

class ClientModel {
  final String id;
  final String name;
  final String mobile;
  final String clientCategory;
  final String customClientCategory;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ReelEntry> reels;

  const ClientModel({
    required this.id,
    required this.name,
    required this.mobile,
    required this.clientCategory,
    this.customClientCategory = '',
    required this.createdAt,
    required this.updatedAt,
    required this.reels,
  });

  factory ClientModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final reelCount = ReelEntry.countReels(d);
    final reels = reelCount == 0
        ? [ReelEntry.fromMap(d, 1)] // fallback for legacy docs without reel fields
        : List.generate(reelCount, (i) => ReelEntry.fromMap(d, i + 1));
    return ClientModel(
      id: doc.id,
      name: d['name'] as String? ?? '',
      mobile: d['mobile'] as String? ?? '',
      clientCategory: d['clientCategory'] as String? ?? 'Mobile Shoot',
      customClientCategory: d['customClientCategory'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      reels: reels,
    );
  }

  ReelEntry get primaryReel => reels.first;
  double get paymentAmount => primaryReel.paymentAmount;
  String get paymentStatus => primaryReel.paymentStatus;
  String get displayReelCategory => primaryReel.displayReelCategory;
  String get displayPaymentType => primaryReel.displayPaymentType;
  double get totalPaymentAmount => reels.fold(0, (sum, r) => sum + r.paymentAmount);
  int get reelCount => reels.length;

  String get displayCategory =>
      clientCategory == 'Custom' ? customClientCategory : clientCategory;
}

// ════════════════════════════════════════════════════════════
//  CONSTANTS
// ════════════════════════════════════════════════════════════

const _kClientCategories = [
  'Mobile Shoot',
  'Camera Shoot',
  'Edit',
  'Custom',
];

const _kPaymentTypes = ['Cash', 'UPI', 'Bank Transfer', 'Card Payment', 'Other'];

const _kPaymentStatuses = ['Pending', 'Advance', 'Completed', 'Overdue'];

const _kReelCategories = [
  'Promotional Reel',
  'Wedding Reel',
  'New car Delivery Reel',
  'Birthday Reel',
  'Welcome Baby Reel',
  'Home interior Video',
  'Traditional Chhathi Reel',
  'Custom',
];

// ════════════════════════════════════════════════════════════
//  COLOR HELPERS
// ════════════════════════════════════════════════════════════

Color _paymentStatusColor(String s) {
  switch (s.toLowerCase()) {
    case 'completed': return BillifyColors.paid;
    case 'advance':   return const Color(0xFF1976D2);
    case 'overdue':   return BillifyColors.overdue;
    default:          return BillifyColors.unpaid;
  }
}

Color _paymentStatusBg(String s) {
  switch (s.toLowerCase()) {
    case 'completed': return const Color(0xFFE8F5E9);
    case 'advance':   return const Color(0xFFE3F2FD);
    case 'overdue':   return const Color(0xFFFFF3E0);
    default:          return const Color(0xFFFFEBEE);
  }
}

IconData _paymentStatusIcon(String s) {
  switch (s.toLowerCase()) {
    case 'completed': return Icons.check_circle_rounded;
    case 'advance':   return Icons.timelapse_rounded;
    case 'overdue':   return Icons.warning_amber_rounded;
    default:          return Icons.hourglass_empty_rounded;
  }
}

// ════════════════════════════════════════════════════════════
//  CLIENT LIST SCREEN
// ════════════════════════════════════════════════════════════

class ClientListScreen extends StatefulWidget {
  const ClientListScreen({super.key});

  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _filterStatus;
  String? _filterReelCategory;
  String? _filterClientCategory;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Stream<QuerySnapshot> get _stream => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('clients')
      .orderBy('createdAt', descending: true)
      .snapshots();

  List<ClientModel> _filter(List<DocumentSnapshot> docs) {
    var clients = docs.map((d) => ClientModel.fromDoc(d)).toList();
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      clients = clients
          .where((c) => c.name.toLowerCase().contains(q) || c.mobile.contains(q))
          .toList();
    }
    if (_filterStatus != null) {
      clients = clients
          .where((c) => c.paymentStatus.toLowerCase() == _filterStatus!.toLowerCase())
          .toList();
    }
    if (_filterReelCategory != null) {
      clients = clients
          .where((c) => c.displayReelCategory == _filterReelCategory)
          .toList();
    }
    if (_filterClientCategory != null) {
      clients = clients
          .where((c) => c.displayCategory == _filterClientCategory)
          .toList();
    }
    return clients;
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      isScrollControlled: true,
      builder: (_) => _ClientFilterSheet(
        selectedStatus: _filterStatus,
        selectedReel: _filterReelCategory,
        selectedCategory: _filterClientCategory,
        onApply: (status, reel, cat) {
          setState(() {
            _filterStatus = status;
            _filterReelCategory = reel;
            _filterClientCategory = cat;
          });
        },
      ),
    );
  }

  bool get _hasFilter =>
      _filterStatus != null ||
          _filterReelCategory != null ||
          _filterClientCategory != null;

  @override
  Widget build(BuildContext context) {
    return WebScaffold(
      activeRoute: AppRoutes.clients,
      appBar: _buildAppBar(),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_client',
        onPressed: () => Get.toNamed(AppRoutes.clientAdd),
        icon: const Icon(Icons.person_add_rounded, size: 18),
        label: Text(
          'NEW CLIENT',
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.2),
        ),
        backgroundColor: ThemeController.to.primary,
        foregroundColor: const Color(0xFFF7F7FF),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          if (_hasFilter) _buildActiveFilters(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _stream,
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(
                      child: CircularProgressIndicator(
                          color: ThemeController.to.primary));
                }
                if (snap.hasError) {
                  return _ErrorState(message: snap.error.toString());
                }
                final clients = _filter(snap.data?.docs ?? []);
                // Keep reference for export
                WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _latestFilteredClients = clients);
                if (clients.isEmpty) {
                  return _EmptyClientState(
                      hasFilter: _hasFilter || _searchQuery.isNotEmpty);
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  itemCount: clients.length,
                  separatorBuilder: (_, __) => Container(
                      height: 1,
                      color: BillifyColors.outlineVariant.withOpacity(0.4)),
                  itemBuilder: (ctx, i) => _ClientCard(
                    client: clients[i],
                    onDelete: () => _deleteClient(clients[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Holds the latest filtered clients so the export sheet uses them ──────
  List<ClientModel> _latestFilteredClients = [];

  void _showExportSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => ClientExportSheet(clients: _latestFilteredClients),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: BillifyColors.background,
      elevation: 0,
      title: Text(
        'CLIENTS',
        style: GoogleFonts.poppins(
          color: ThemeController.to.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.0,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
            height: 1, color: BillifyColors.outlineVariant.withOpacity(0.4)),
      ),
      actions: [
        // ── Export button ───────────────────────────────────
        IconButton(
          tooltip: 'Export',
          icon: Icon(
            Icons.ios_share_rounded,
            color: BillifyColors.textSecondary,
            size: 20,
          ),
          onPressed: _showExportSheet,
        ),
        // ── Filter button ───────────────────────────────────
        IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.filter_list_rounded,
                  color: _hasFilter
                      ? ThemeController.to.primary
                      : BillifyColors.textSecondary,
                  size: 22),
              if (_hasFilter)
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: BillifyColors.unpaid, shape: BoxShape.circle),
                  ),
                ),
            ],
          ),
          onPressed: _showFilterSheet,
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
        decoration: InputDecoration(
          hintText: 'Search by name or mobile…',
          prefixIcon:
          Icon(Icons.search_rounded, color: ThemeController.to.primary, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.close_rounded,
                color: BillifyColors.textSecondary, size: 16),
            onPressed: () {
              _searchCtrl.clear();
              setState(() => _searchQuery = '');
            },
          )
              : null,
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
        style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildActiveFilters() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (_filterStatus != null)
            _FilterChip(
                label: _filterStatus!,
                onRemove: () => setState(() => _filterStatus = null)),
          if (_filterReelCategory != null)
            _FilterChip(
                label: _filterReelCategory!,
                onRemove: () => setState(() => _filterReelCategory = null)),
          if (_filterClientCategory != null)
            _FilterChip(
                label: _filterClientCategory!,
                onRemove: () => setState(() => _filterClientCategory = null)),
          TextButton(
            onPressed: () => setState(() {
              _filterStatus = null;
              _filterReelCategory = null;
              _filterClientCategory = null;
            }),
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0)),
            child: Text('CLEAR ALL',
                style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                    color: BillifyColors.unpaid)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteClient(ClientModel client) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => BillifyDialog(
        icon: Icons.delete_forever_rounded,
        iconColor: BillifyColors.unpaid,
        title: 'Delete Client',
        body:
        'Are you sure you want to delete "${client.name}"? This cannot be undone.',
        confirmLabel: 'Delete',
        confirmColor: BillifyColors.unpaid,
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('clients')
          .doc(client.id)
          .delete();
      Get.snackbar('Deleted', '${client.name} has been removed.',
          backgroundColor: BillifyColors.paid,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP);
    } catch (e) {
      Get.snackbar('Error', 'Could not delete client.',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    }
  }
}

// ════════════════════════════════════════════════════════════
//  CLIENT CARD
// ════════════════════════════════════════════════════════════

class _ClientCard extends StatelessWidget {
  final ClientModel client;
  final VoidCallback onDelete;

  const _ClientCard({required this.client, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final statusColor = _paymentStatusColor(client.paymentStatus);
    final statusBg = _paymentStatusBg(client.paymentStatus);
    final c = BillifyC.of(context);
    final fmt = NumberFormat('#,##,###.##');

    return InkWell(
      onTap: () => Get.toNamed(AppRoutes.clientDetail, arguments: client.id),
      child: Container(
        padding: const EdgeInsets.all(14),
        color: c.card,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              color: ThemeController.to.primary.withOpacity(0.12),
              child: Center(
                child: Text(
                  client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: ThemeController.to.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(client.name,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary)),
                  const SizedBox(height: 2),
                  if (client.mobile.isNotEmpty)
                    Text(client.mobile,
                        style: GoogleFonts.nunito(
                            fontSize: 12, color: c.textSecondary)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _MiniChip(label: client.displayCategory),
                      _MiniChip(
                          label: client.primaryReel.displayReelCategory,
                          color: ThemeController.to.primaryLight),
                      if (client.reelCount > 1)
                        _MiniChip(
                            label: '+${client.reelCount - 1} more reel${client.reelCount > 2 ? 's' : ''}',
                            color: BillifyColors.paid),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right: amount + status + actions
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${fmt.format(client.totalPaymentAmount)}',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  color: statusBg,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_paymentStatusIcon(client.paymentStatus),
                          size: 10, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        client.paymentStatus.toUpperCase(),
                        style: GoogleFonts.poppins(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: statusColor),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _IconAction(
                      icon: Icons.edit_rounded,
                      color: ThemeController.to.primary,
                      tooltip: 'Edit',
                      onTap: () => Get.toNamed(AppRoutes.clientEdit,
                          arguments: {'clientId': client.id}),
                    ),
                    const SizedBox(width: 4),
                    _IconAction(
                      icon: Icons.delete_rounded,
                      color: BillifyColors.unpaid,
                      tooltip: 'Delete',
                      onTap: onDelete,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color? color;
  const _MiniChip({required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final col = color ?? BillifyColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: col.withOpacity(0.1),
        border: Border.all(color: col.withOpacity(0.3), width: 0.5),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.poppins(
            fontSize: 7,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: col),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _IconAction(
      {required this.icon,
        required this.color,
        required this.onTap,
        this.tooltip = ''});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          color: color.withOpacity(0.1),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  STEP 1 — CLIENT INFO FORM
//  Used for: Add new client (before reels), Edit client details
// ════════════════════════════════════════════════════════════

class ClientInfoFormScreen extends StatefulWidget {
  /// null = create new; non-null = edit existing client info
  final String? clientId;

  const ClientInfoFormScreen({super.key, this.clientId});

  @override
  State<ClientInfoFormScreen> createState() => _ClientInfoFormScreenState();
}

class _ClientInfoFormScreenState extends State<ClientInfoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isFetching = false;
  bool _isSaving = false;

  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  bool get _isEdit => widget.clientId != null;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    if (_isEdit) _fetchClient();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchClient() async {
    setState(() => _isFetching = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('clients')
          .doc(widget.clientId)
          .get();
      if (!doc.exists) return;
      final d = doc.data() as Map<String, dynamic>;
      _nameCtrl.text = d['name'] as String? ?? '';
      _mobileCtrl.text = d['mobile'] as String? ?? '';
    } catch (_) {}
    if (mounted) setState(() => _isFetching = false);
  }

  Future<void> _next() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final baseData = {
      'name': _nameCtrl.text.trim(),
      'mobile': _mobileCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('clients');

      if (_isEdit) {
        // Editing existing — save client info and go back
        await col.doc(widget.clientId).update(baseData);
        Get.back();
        Get.snackbar('Updated', 'Client info updated successfully.',
            backgroundColor: BillifyColors.paid,
            colorText: Colors.white,
            snackPosition: SnackPosition.TOP);
      } else {
        // Creating new — save client first, then proceed to reel form
        final data = {
          ...baseData,
          'createdAt': FieldValue.serverTimestamp(),
        };
        final ref = await col.add(data);
        // Navigate to reel form (first reel, index=1) passing the new client ID
        Get.off(
              () => ClientReelFormScreen(clientId: ref.id, reelIndex: 1, isNewClient: true),
          transition: Transition.rightToLeft,
        );
      }
    } catch (e) {
      Get.snackbar('Error', 'Could not save. Try again.',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: BillifyColors.background,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: ThemeController.to.primary),
          onPressed: () => Get.back(),
        ),
        title: Text(
          _isEdit ? 'EDIT CLIENT INFO' : 'NEW CLIENT',
          style: GoogleFonts.poppins(
              color: ThemeController.to.primary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              height: 1, color: BillifyColors.outlineVariant.withOpacity(0.4)),
        ),
      ),
      body: _isFetching
          ? Center(
          child: CircularProgressIndicator(color: ThemeController.to.primary))
          : Column(
        children: [
          // Step indicator (only for new client flow)
          if (!_isEdit) _StepIndicator(currentStep: 1, totalSteps: 2),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding:
                const EdgeInsets.fromLTRB(16, 20, 16, 100),
                children: [
                  _SectionHeader(label: 'CLIENT INFORMATION'),
                  const SizedBox(height: 12),

                  // Name
                  _buildField(
                    label: 'CLIENT NAME *',
                    child: TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Enter client full name',
                        prefixIcon: Icon(Icons.person_rounded,
                            color: ThemeController.to.primary, size: 18),
                      ),
                      validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Name is required'
                          : null,
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Mobile
                  _buildField(
                    label: 'MOBILE NUMBER',
                    child: TextFormField(
                      controller: _mobileCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(15),
                      ],
                      decoration: InputDecoration(
                        hintText: 'Enter mobile number (optional)',
                        prefixIcon: Icon(Icons.phone_rounded,
                            color: ThemeController.to.primary, size: 18),
                      ),
                      validator: (v) {
                        if (v != null &&
                            v.trim().isNotEmpty &&
                            v.trim().length < 7) {
                          return 'Enter a valid mobile number';
                        }
                        return null;
                      },
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 24),

                  const SizedBox(height: 32),

                  // Action button
                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _next,
                      icon: _isSaving
                          ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                          : Icon(
                          _isEdit
                              ? Icons.save_rounded
                              : Icons.arrow_forward_rounded,
                          size: 18),
                      label: Text(
                        _isEdit ? 'SAVE CHANGES' : 'CONTINUE TO REEL',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 1.5),
                      ),
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

  Widget _buildField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: BillifyColors.textSecondary),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
//  STEP 2 — REEL FORM (supports adding + editing a single reel)
//  Also used standalone from ClientDetailScreen to add/edit reels.
// ════════════════════════════════════════════════════════════

class ClientReelFormScreen extends StatefulWidget {
  final String clientId;
  final int reelIndex; // 1-based
  final bool isNewClient; // true = came from ClientInfoFormScreen (step 2)

  const ClientReelFormScreen({
    super.key,
    required this.clientId,
    required this.reelIndex,
    this.isNewClient = false,
  });

  @override
  State<ClientReelFormScreen> createState() => _ClientReelFormScreenState();
}

class _ClientReelFormScreenState extends State<ClientReelFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isFetching = false;
  bool _isSaving = false;

  final _amountCtrl = TextEditingController();
  final _customPaymentTypeCtrl = TextEditingController();
  final _customReelCtrl = TextEditingController();
  final _customShootCtrl = TextEditingController();

  DateTime? _projectStartDate;
  String _shootCategory = 'Mobile Shoot';
  String _paymentType = 'Cash';
  String _paymentStatus = 'Pending';
  String _reelCategory = 'Promotional Reel';

  // Locked after _fetchReelData — true only if this reel already exists in Firestore
  bool _isEditing = false;
  int _existingReelCount = 0;

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _fetchReelData();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _customPaymentTypeCtrl.dispose();
    _customReelCtrl.dispose();
    _customShootCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchReelData() async {
    setState(() => _isFetching = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('clients')
          .doc(widget.clientId)
          .get();
      if (!doc.exists) return;
      final d = doc.data() as Map<String, dynamic>;
      _existingReelCount = ReelEntry.countReels(d);

      // Lock editing flag — true only if this specific reel slot actually exists in Firestore
      _isEditing = !widget.isNewClient && ReelEntry.reelExists(d, widget.reelIndex);

      // Only prefill if editing existing reel
      if (_isEditing) {
        final reel = ReelEntry.fromMap(d, widget.reelIndex);
        _amountCtrl.text =
        reel.paymentAmount == 0 ? '' : reel.paymentAmount.toString();
        _projectStartDate = reel.projectStartDate;
        _shootCategory = reel.shootCategory;
        _customShootCtrl.text = reel.customShootCategory;
        _paymentType = reel.paymentType;
        _paymentStatus = reel.paymentStatus;
        _reelCategory = reel.reelCategory;
        _customPaymentTypeCtrl.text = reel.customPaymentType;
        _customReelCtrl.text = reel.customReelCategory;
      }
    } catch (_) {}
    if (mounted) setState(() => _isFetching = false);
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _projectStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx)
              .colorScheme
              .copyWith(primary: ThemeController.to.primary),
        ),
        child: child!,
      ),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime:
      TimeOfDay.fromDateTime(_projectStartDate ?? DateTime.now()),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx)
              .colorScheme
              .copyWith(primary: ThemeController.to.primary),
        ),
        child: child!,
      ),
    );
    if (time == null) return;
    setState(() {
      _projectStartDate =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSaving = true;
    });

    final reel = ReelEntry(
      index: widget.reelIndex,
      projectStartDate: _projectStartDate,
      shootCategory: _shootCategory,
      customShootCategory: _customShootCtrl.text.trim(),
      reelCategory: _reelCategory,
      customReelCategory: _customReelCtrl.text.trim(),
      paymentAmount: double.tryParse(_amountCtrl.text.trim()) ?? 0.0,
      paymentType: _paymentType,
      customPaymentType: _customPaymentTypeCtrl.text.trim(),
      paymentStatus: _paymentStatus,
    );

    final data = {
      ...reel.toFields(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('clients')
          .doc(widget.clientId)
          .update(data);

      if (widget.isNewClient) {
        // Pop back to client list after finishing reel
        Get.until((r) => r.settings.name == AppRoutes.clients);
      } else {
        Get.back();
      }
      Get.snackbar(
        _isEditing ? 'Updated' : 'Saved',
        _isEditing
            ? 'Reel #${widget.reelIndex} updated.'
            : 'Reel #${widget.reelIndex} added.',
        backgroundColor: BillifyColors.paid,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
      );
    } catch (e) {
      Get.snackbar('Error', 'Could not save reel. Try again.',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final appBarTitle = _isFetching
        ? 'LOADING…'
        : _isEditing
        ? 'EDIT REEL #${widget.reelIndex}'
        : widget.isNewClient
        ? 'ADD REEL #${widget.reelIndex}'
        : 'NEW REEL #${widget.reelIndex}';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: BillifyColors.background,
        leading: IconButton(
          icon:
          Icon(Icons.arrow_back_rounded, color: ThemeController.to.primary),
          onPressed: () => Get.back(),
        ),
        title: Text(
          appBarTitle,
          style: GoogleFonts.poppins(
              color: ThemeController.to.primary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              height: 1, color: BillifyColors.outlineVariant.withOpacity(0.4)),
        ),
      ),
      body: _isFetching
          ? Center(
          child: CircularProgressIndicator(color: ThemeController.to.primary))
          : Column(
        children: [
          if (widget.isNewClient)
            _StepIndicator(currentStep: 2, totalSteps: 2),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding:
                const EdgeInsets.fromLTRB(16, 20, 16, 120),
                children: [
                  // ── Project date ───────────────────
                  _SectionHeader(label: 'PROJECT SCHEDULE'),
                  const SizedBox(height: 12),
                  _buildField(
                    label: 'PROJECT START DATE & TIME',
                    child: GestureDetector(
                      onTap: _pickDateTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: BillifyColors.surfaceLow,
                          border: Border.all(
                              color: BillifyColors.outlineVariant
                                  .withOpacity(0.6)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_month_rounded,
                                color: ThemeController.to.primary,
                                size: 18),
                            const SizedBox(width: 10),
                            Text(
                              _projectStartDate == null
                                  ? 'Select date & time'
                                  : DateFormat('dd MMM yyyy  hh:mm a')
                                  .format(_projectStartDate!),
                              style: GoogleFonts.nunito(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: _projectStartDate == null
                                    ? BillifyColors.outlineVariant
                                    : BillifyColors.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            if (_projectStartDate != null)
                              GestureDetector(
                                onTap: () => setState(
                                        () => _projectStartDate = null),
                                child: const Icon(Icons.close_rounded,
                                    size: 16,
                                    color: BillifyColors.textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Reel details ──────────────────
                  _SectionHeader(label: 'REEL DETAILS'),
                  const SizedBox(height: 12),
                  _buildField(
                    label: 'SHOOT CATEGORY *',
                    child: _DropdownField<String>(
                      value: _shootCategory,
                      items: _kClientCategories,
                      icon: Icons.camera_alt_rounded,
                      onChanged: (v) =>
                          setState(() => _shootCategory = v!),
                    ),
                  ),
                  if (_shootCategory == 'Custom') ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _customShootCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Enter custom shoot category',
                        prefixIcon: Icon(Icons.edit_rounded,
                            color: ThemeController.to.primary, size: 16),
                      ),
                      validator: (v) =>
                      _shootCategory == 'Custom' &&
                          (v == null || v.trim().isEmpty)
                          ? 'Custom shoot category is required'
                          : null,
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _buildField(
                    label: 'REEL CATEGORY *',
                    child: _DropdownField<String>(
                      value: _reelCategory,
                      items: _kReelCategories,
                      icon: Icons.video_library_rounded,
                      onChanged: (v) =>
                          setState(() => _reelCategory = v!),
                    ),
                  ),
                  if (_reelCategory == 'Custom') ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _customReelCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Enter custom reel category',
                        prefixIcon: Icon(Icons.edit_rounded,
                            color: ThemeController.to.primary, size: 16),
                      ),
                      validator: (v) =>
                      _reelCategory == 'Custom' &&
                          (v == null || v.trim().isEmpty)
                          ? 'Custom reel category is required'
                          : null,
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 24),

                  // ── Payment ────────────────────────
                  _SectionHeader(label: 'PAYMENT DETAILS'),
                  const SizedBox(height: 12),
                  _buildField(
                    label: 'PAYMENT AMOUNT *',
                    child: TextFormField(
                      controller: _amountCtrl,
                      keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixIcon: Icon(Icons.currency_rupee_rounded,
                            color: ThemeController.to.primary, size: 18),
                      ),
                      validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'Payment amount is required'
                          : null,
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildField(
                    label: 'PAYMENT TYPE *',
                    child: _DropdownField<String>(
                      value: _paymentType,
                      items: _kPaymentTypes,
                      icon: Icons.payment_rounded,
                      onChanged: (v) =>
                          setState(() => _paymentType = v!),
                    ),
                  ),
                  if (_paymentType == 'Other') ...[
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _customPaymentTypeCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: 'Describe the payment method',
                        prefixIcon: Icon(Icons.edit_rounded,
                            color: ThemeController.to.primary, size: 16),
                      ),
                      validator: (v) =>
                      _paymentType == 'Other' &&
                          (v == null || v.trim().isEmpty)
                          ? 'Payment method description is required'
                          : null,
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _buildField(
                    label: 'PAYMENT STATUS *',
                    child: _PaymentStatusSelector(
                      selected: _paymentStatus,
                      onSelect: (v) =>
                          setState(() => _paymentStatus = v),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // ── Save button ────────────────────
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                          : Text(
                        _isEditing
                            ? 'UPDATE REEL #${widget.reelIndex}'
                            : widget.isNewClient
                            ? 'FINISH & SAVE'
                            : 'SAVE REEL',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            letterSpacing: 1.5),
                      ),
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

  Widget _buildField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: BillifyColors.textSecondary)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
//  LEGACY REDIRECT — ClientFormScreen kept for route compatibility
//  main.dart routes clientAdd → ClientInfoFormScreen
//  main.dart routes clientEdit → ClientInfoFormScreen (with clientId)
// ════════════════════════════════════════════════════════════
// Defined at bottom as a thin wrapper so existing GetPage definitions
// in main.dart continue to compile. See _RouteShims at the end.

// ════════════════════════════════════════════════════════════
//  CLIENT DETAIL SCREEN
// ════════════════════════════════════════════════════════════

class ClientDetailScreen extends StatelessWidget {
  final String clientId;
  const ClientDetailScreen({super.key, required this.clientId});

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: BillifyColors.background,
        leading: IconButton(
          icon:
          Icon(Icons.arrow_back_rounded, color: ThemeController.to.primary),
          onPressed: () => Get.back(),
        ),
        title: Text(
          'CLIENT PROFILE',
          style: GoogleFonts.poppins(
              color: ThemeController.to.primary,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.0),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              height: 1, color: BillifyColors.outlineVariant.withOpacity(0.4)),
        ),
        actions: [
          // Edit client info button in AppBar
          IconButton(
            icon: Icon(Icons.edit_rounded,
                color: ThemeController.to.primary, size: 20),
            tooltip: 'Edit client info',
            onPressed: () => Get.to(
                  () => ClientInfoFormScreen(clientId: clientId),
              transition: Transition.rightToLeft,
            ),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('clients')
            .doc(clientId)
            .snapshots(),
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
                child: CircularProgressIndicator(
                    color: ThemeController.to.primary));
          }
          if (!snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('Client not found.'));
          }
          final client = ClientModel.fromDoc(snap.data!);
          return _buildProfile(context, client);
        },
      ),
    );
  }

  Widget _buildProfile(BuildContext context, ClientModel client) {
    final c = BillifyC.of(context);
    final fmt = NumberFormat('#,##,###.##');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero card ────────────────────────────────────
          Container(
            width: double.infinity,
            color: c.card,
            child: Column(
              children: [
                // Gradient header strip
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ThemeController.to.primary,
                        ThemeController.to.primary.withOpacity(0.75),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    children: [
                      // Avatar
                      Container(
                        width: 64,
                        height: 64,
                        color: Colors.white.withOpacity(0.2),
                        child: Center(
                          child: Text(
                            client.name.isNotEmpty
                                ? client.name[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(client.name,
                          style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)),
                      if (client.mobile.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(client.mobile,
                            style: GoogleFonts.nunito(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.75))),
                      ],
                      const SizedBox(height: 8),
                      // Category + reel count badges
                      Wrap(
                        spacing: 8,
                        children: [
                          _heroBadge(client.displayCategory),
                          _heroBadge(
                              '${client.reelCount} REEL${client.reelCount > 1 ? 'S' : ''}',
                              icon: Icons.video_library_rounded),
                        ],
                      ),
                    ],
                  ),
                ),

                // Total payment highlight
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 16),
                  color: c.card,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              client.reelCount > 1
                                  ? 'TOTAL (ALL REELS)'
                                  : 'TOTAL PAYMENT',
                              style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.2,
                                  color: c.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '₹${fmt.format(client.totalPaymentAmount)}',
                              style: GoogleFonts.poppins(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: ThemeController.to.primary,
                                  letterSpacing: -1),
                            ),
                          ],
                        ),
                      ),
                      // Quick stats
                      _QuickStat(
                        label: 'REELS',
                        value: '${client.reelCount}',
                        color: ThemeController.to.primary,
                      ),
                      const SizedBox(width: 12),
                      _QuickStat(
                        label: 'STATUS',
                        value: client.paymentStatus.toUpperCase(),
                        color: _paymentStatusColor(client.paymentStatus),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Reels ────────────────────────────────────────
          Row(
            children: [
              _SectionHeader(label: 'REEL BREAKDOWN'),
              const Spacer(),
              // Add reel quick action
              GestureDetector(
                onTap: () => Get.to(
                      () => ClientReelFormScreen(
                    clientId: clientId,
                    reelIndex: client.reelCount + 1,
                  ),
                  transition: Transition.rightToLeft,
                ),
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  color: ThemeController.to.primary.withOpacity(0.1),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded,
                          size: 13, color: ThemeController.to.primary),
                      const SizedBox(width: 4),
                      Text('ADD REEL',
                          style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: ThemeController.to.primary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Reel cards
          ...client.reels.asMap().entries.map((e) {
            final reelIdx = e.key; // 0-based
            final reel = e.value;
            return _ReelDetailCard(
              reel: reel,
              reelNumber: reelIdx + 1,
              totalReels: client.reelCount,
              clientId: clientId,
              onDelete: client.reelCount > 1
                  ? () => _confirmDeleteReel(context, clientId, reel, client.reelCount)
                  : null,
            );
          }),
          const SizedBox(height: 16),

          // ── Timestamps ───────────────────────────────────
          _DetailCard(
            title: 'RECORD INFO',
            rows: [
              _DetailRow(
                label: 'Created',
                value: DateFormat('dd MMM yyyy  hh:mm a').format(client.createdAt),
                icon: Icons.add_circle_outline_rounded,
              ),
              _DetailRow(
                label: 'Last Updated',
                value: DateFormat('dd MMM yyyy  hh:mm a').format(client.updatedAt),
                icon: Icons.update_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroBadge(String label, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      color: Colors.white.withOpacity(0.18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            label.toUpperCase(),
            style: GoogleFonts.poppins(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Colors.white),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteReel(BuildContext context, String clientId,
      ReelEntry reel, int totalReels) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => BillifyDialog(
        icon: Icons.delete_rounded,
        iconColor: BillifyColors.unpaid,
        title: 'Delete Reel #${reel.index}',
        body:
        'Remove reel #${reel.index} from this client? This cannot be undone.',
        confirmLabel: 'Delete',
        confirmColor: BillifyColors.unpaid,
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
    if (confirm != true) return;

    try {
      // Delete the reel fields
      final deleteData = reel.toDeleteFields();

      // If not the last reel, shift higher-indexed reels down by 1
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('clients')
          .doc(clientId)
          .get();
      final d = doc.data() as Map<String, dynamic>;
      final currentCount = ReelEntry.countReels(d);

      final batch = <String, dynamic>{...deleteData};

      // Shift reels above the deleted one down
      for (int i = reel.index + 1; i <= currentCount; i++) {
        final src = ReelEntry.fromMap(d, i);
        final shifted = ReelEntry(
          index: i - 1,
          projectStartDate: src.projectStartDate,
          shootCategory: src.shootCategory,
          customShootCategory: src.customShootCategory,
          reelCategory: src.reelCategory,
          customReelCategory: src.customReelCategory,
          paymentAmount: src.paymentAmount,
          paymentType: src.paymentType,
          customPaymentType: src.customPaymentType,
          paymentStatus: src.paymentStatus,
        );
        batch.addAll(shifted.toFields());
        // Delete the old slot at position i (now shifted to i-1)
        batch.addAll(ReelEntry(
          index: i,
          shootCategory: '',
          reelCategory: '',
          paymentAmount: 0,
          paymentType: '',
          paymentStatus: '',
        ).toDeleteFields());
      }

      batch['updatedAt'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('clients')
          .doc(clientId)
          .update(batch);

      Get.snackbar('Deleted', 'Reel #${reel.index} removed.',
          backgroundColor: BillifyColors.paid,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP);
    } catch (e) {
      Get.snackbar('Error', 'Could not delete reel.',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    }
  }
}

// ── Reel Detail Card ──────────────────────────────────────
class _ReelDetailCard extends StatefulWidget {
  final ReelEntry reel;
  final int reelNumber;
  final int totalReels;
  final String clientId;
  final VoidCallback? onDelete;

  const _ReelDetailCard({
    required this.reel,
    required this.reelNumber,
    required this.totalReels,
    required this.clientId,
    this.onDelete,
  });

  @override
  State<_ReelDetailCard> createState() => _ReelDetailCardState();
}

class _ReelDetailCardState extends State<_ReelDetailCard> {
  bool _expanded = true;

  @override
  void initState() {
    super.initState();
    // Collapse all but the first reel by default
    _expanded = widget.reelNumber == 1;
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _paymentStatusColor(widget.reel.paymentStatus);
    final statusBg = _paymentStatusBg(widget.reel.paymentStatus);
    final fmt = NumberFormat('#,##,###.##');
    final c = BillifyC.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(
          left: BorderSide(color: statusColor, width: 3),
        ),
      ),
      child: Column(
        children: [
          // Reel card header (always visible)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    color: ThemeController.to.primary.withOpacity(0.1),
                    child: Text(
                      widget.totalReels > 1
                          ? 'REEL ${widget.reelNumber}'
                          : 'REEL',
                      style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: ThemeController.to.primary),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.reel.displayReelCategory,
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.textPrimary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Amount
                  Text(
                    '₹${fmt.format(widget.reel.paymentAmount)}',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary),
                  ),
                  const SizedBox(width: 8),
                  // Status badge
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    color: statusBg,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_paymentStatusIcon(widget.reel.paymentStatus),
                            size: 9, color: statusColor),
                        const SizedBox(width: 3),
                        Text(
                          widget.reel.paymentStatus.toUpperCase(),
                          style: GoogleFonts.poppins(
                              fontSize: 7,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                              color: statusColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: c.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // Expandable details
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              children: [
                Container(
                    height: 0.5,
                    color: BillifyColors.outlineVariant.withOpacity(0.5)),
                _DetailRow(
                  label: 'Shoot Category',
                  value: widget.reel.displayShootCategory,
                  icon: Icons.camera_alt_rounded,
                ),
                if (widget.reel.projectStartDate != null)
                  _DetailRow(
                    label: 'Start Date & Time',
                    value: DateFormat('dd MMM yyyy  hh:mm a')
                        .format(widget.reel.projectStartDate!),
                    icon: Icons.calendar_month_rounded,
                  ),
                _DetailRow(
                  label: 'Payment Type',
                  value: widget.reel.displayPaymentType,
                  icon: Icons.payment_rounded,
                ),
                // Action row: edit + delete
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Get.to(
                                () => ClientReelFormScreen(
                              clientId: widget.clientId,
                              reelIndex: widget.reel.index,
                            ),
                            transition: Transition.rightToLeft,
                          ),
                          icon: const Icon(Icons.edit_rounded, size: 14),
                          label: Text('EDIT REEL',
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0)),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 38),
                          ),
                        ),
                      ),
                      if (widget.onDelete != null) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 38,
                          child: OutlinedButton.icon(
                            onPressed: widget.onDelete,
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 14, color: BillifyColors.unpaid),
                            label: Text('REMOVE',
                                style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.0,
                                    color: BillifyColors.unpaid)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                  color: BillifyColors.unpaid, width: 1.5),
                              minimumSize: const Size(0, 38),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _QuickStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _QuickStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Text(value,
          style: GoogleFonts.poppins(
              fontSize: 14, fontWeight: FontWeight.w900, color: color)),
      Text(label,
          style: GoogleFonts.poppins(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: BillifyColors.textSecondary)),
    ],
  );
}

class _DetailCard extends StatelessWidget {
  final String title;
  final List<_DetailRow> rows;
  const _DetailCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Container(
      color: c.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: BillifyColors.surfaceContainer,
              child: Row(
                children: [
                  Container(
                      width: 3,
                      height: 12,
                      color: ThemeController.to.primary),
                  const SizedBox(width: 8),
                  Text(title,
                      style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          color: ThemeController.to.primary)),
                ],
              ),
            ),
          ...rows.asMap().entries.map((e) {
            final isLast = e.key == rows.length - 1;
            return Column(
              children: [
                e.value,
                if (!isLast)
                  Container(
                      height: 0.5,
                      color: BillifyColors.outlineVariant.withOpacity(0.4),
                      margin: const EdgeInsets.symmetric(horizontal: 16)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: ThemeController.to.primary.withOpacity(0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary)),
          ),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? c.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  FILTER SHEET
// ════════════════════════════════════════════════════════════

class _ClientFilterSheet extends StatefulWidget {
  final String? selectedStatus;
  final String? selectedReel;
  final String? selectedCategory;
  final void Function(String?, String?, String?) onApply;

  const _ClientFilterSheet({
    this.selectedStatus,
    this.selectedReel,
    this.selectedCategory,
    required this.onApply,
  });

  @override
  State<_ClientFilterSheet> createState() => _ClientFilterSheetState();
}

class _ClientFilterSheetState extends State<_ClientFilterSheet> {
  String? _status;
  String? _reel;
  String? _category;

  @override
  void initState() {
    super.initState();
    _status = widget.selectedStatus;
    _reel = widget.selectedReel;
    _category = widget.selectedCategory;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: BillifyColors.surface,
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 3, color: ThemeController.to.primary),
          const SizedBox(height: 16),
          Text('FILTER CLIENTS',
              style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: ThemeController.to.primary)),
          const SizedBox(height: 16),
          _filterGroup('PAYMENT STATUS', _kPaymentStatuses, _status,
                  (v) => setState(() => _status = _status == v ? null : v)),
          const SizedBox(height: 12),
          _filterGroup(
              'REEL CATEGORY',
              _kClientCategories.where((c) => c != 'Custom').toList(),
              _category,
                  (v) => setState(() => _category = _category == v ? null : v)),
          const SizedBox(height: 12),
          _filterGroup(
              'REEL CATEGORY',
              _kReelCategories.where((c) => c != 'Custom').toList(),
              _reel,
                  (v) => setState(() => _reel = _reel == v ? null : v)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _status = null;
                    _reel = null;
                    _category = null;
                  }),
                  child: Text('CLEAR',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 1.2)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    widget.onApply(_status, _reel, _category);
                    Get.back();
                  },
                  child: Text('APPLY',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 1.2)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterGroup(String title, List<String> options, String? selected,
      ValueChanged<String> onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: BillifyColors.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((o) {
            final isSel = o == selected;
            return GestureDetector(
              onTap: () => onTap(o),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSel
                      ? ThemeController.to.primary
                      : BillifyColors.surfaceLow,
                  border: Border.all(
                    color: isSel
                        ? ThemeController.to.primary
                        : BillifyColors.outlineVariant,
                  ),
                ),
                child: Text(o,
                    style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: isSel ? Colors.white : BillifyColors.textPrimary)),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
//  STEP INDICATOR WIDGET
// ════════════════════════════════════════════════════════════

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _StepIndicator({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    final labels = ['Client Info', 'Reel Details'];
    return Container(
      color: BillifyColors.surfaceLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: List.generate(totalSteps * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line
            final stepBefore = (i ~/ 2) + 1;
            final done = stepBefore < currentStep;
            return Expanded(
              child: Container(
                height: 2,
                color: done
                    ? ThemeController.to.primary
                    : BillifyColors.outlineVariant,
              ),
            );
          }
          final step = i ~/ 2 + 1;
          final isDone = step < currentStep;
          final isCurrent = step == currentStep;
          final color = (isDone || isCurrent)
              ? ThemeController.to.primary
              : BillifyColors.outlineVariant;

          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                color: isDone || isCurrent
                    ? ThemeController.to.primary
                    : BillifyColors.surfaceLow,
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                      : Text('$step',
                      style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: isCurrent
                              ? Colors.white
                              : BillifyColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                step <= labels.length ? labels[step - 1] : 'Step $step',
                style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                    color: color),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  DASHBOARD RECENT CLIENTS
// ════════════════════════════════════════════════════════════

class DashboardRecentClients extends StatelessWidget {
  const DashboardRecentClients({super.key});

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                  width: 3,
                  height: 14,
                  color: ThemeController.to.primary),
              const SizedBox(width: 8),
              Text('RECENT CLIENTS',
                  style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.8,
                      color: ThemeController.to.primary)),
              const Spacer(),
              GestureDetector(
                onTap: () => Get.toNamed(AppRoutes.clients),
                child: Text('VIEW ALL →',
                    style: GoogleFonts.poppins(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: ThemeController.to.primary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(_uid)
                .collection('clients')
                .orderBy('createdAt', descending: true)
                .limit(4)
                .snapshots(),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(
                        color: ThemeController.to.primary, strokeWidth: 2));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) return _DashboardEmptyClients();
              final clients =
              docs.map((d) => ClientModel.fromDoc(d)).toList();
              return Column(
                  children:
                  clients.map((c) => _DashboardClientRow(client: c)).toList());
            },
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => Get.toNamed(AppRoutes.clientAdd),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: ThemeController.to.primary.withOpacity(0.06),
                border: Border.all(
                    color: ThemeController.to.primary.withOpacity(0.2),
                    width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_add_rounded,
                      size: 14, color: ThemeController.to.primary),
                  const SizedBox(width: 8),
                  Text('ADD NEW CLIENT',
                      style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: ThemeController.to.primary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardClientRow extends StatelessWidget {
  final ClientModel client;
  const _DashboardClientRow({required this.client});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final statusColor = _paymentStatusColor(client.paymentStatus);
    final fmt = NumberFormat('#,##,###');
    return GestureDetector(
      onTap: () => Get.toNamed(AppRoutes.clientDetail, arguments: client.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 1),
        color: c.card,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              color: ThemeController.to.primary.withOpacity(0.12),
              child: Center(
                child: Text(
                  client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ThemeController.to.primary),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(client.name,
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: c.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(client.displayCategory,
                      style: GoogleFonts.nunito(
                          fontSize: 11, color: c.textSecondary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${fmt.format(client.totalPaymentAmount)}',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary)),
                Text(client.paymentStatus,
                    style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: statusColor)),
              ],
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 16, color: c.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _DashboardEmptyClients extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      color: BillifyColors.surfaceLow,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: ThemeController.to.primary.withOpacity(0.1),
            child: Icon(Icons.people_outline_rounded,
                color: ThemeController.to.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Text('No clients yet. Add your first client!',
              style:
              GoogleFonts.nunito(fontSize: 13, color: BillifyColors.textSecondary)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  SHARED UI HELPERS
// ════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 3, height: 14, color: ThemeController.to.primary),
        const SizedBox(width: 8),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
                color: ThemeController.to.primary)),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onRemove;
  const _FilterChip({required this.label, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ThemeController.to.primary.withOpacity(0.1),
        border:
        Border.all(color: ThemeController.to.primary.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: GoogleFonts.poppins(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: ThemeController.to.primary)),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded,
                size: 12, color: ThemeController.to.primary),
          ),
        ],
      ),
    );
  }
}

class _EmptyClientState extends StatelessWidget {
  final bool hasFilter;
  const _EmptyClientState({this.hasFilter = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: ThemeController.to.primary.withOpacity(0.08),
              child: Icon(Icons.people_outline_rounded,
                  size: 48, color: ThemeController.to.primary),
            ),
            const SizedBox(height: 20),
            Text(
              hasFilter ? 'NO MATCHES' : 'NO CLIENTS YET',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: BillifyColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Try adjusting your search or filters.'
                  : 'Add your first client to start tracking projects.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                  fontSize: 13,
                  color: BillifyColors.textSecondary,
                  height: 1.5),
            ),
            if (!hasFilter) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Get.toNamed(AppRoutes.clientAdd),
                icon: const Icon(Icons.person_add_rounded, size: 16),
                label: Text('ADD FIRST CLIENT',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1.2)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: BillifyColors.unpaid),
            const SizedBox(height: 12),
            Text('Something went wrong',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: BillifyColors.textPrimary)),
            const SizedBox(height: 4),
            Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                    fontSize: 12, color: BillifyColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  DROPDOWN + PAYMENT STATUS WIDGETS
// ════════════════════════════════════════════════════════════

class _DropdownField<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final IconData icon;
  final ValueChanged<T?> onChanged;

  const _DropdownField({
    required this.value,
    required this.items,
    required this.icon,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: ThemeController.to.primary, size: 18),
      ),
      icon: const Icon(Icons.expand_more_rounded,
          color: BillifyColors.textSecondary, size: 18),
      style: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: BillifyColors.textPrimary),
      dropdownColor: BillifyColors.surface,
      items: items
          .map((e) =>
          DropdownMenuItem<T>(value: e, child: Text(e.toString())))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _PaymentStatusSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;

  const _PaymentStatusSelector(
      {required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kPaymentStatuses.map((s) {
        final isSelected = s == selected;
        final color = _paymentStatusColor(s);
        final bg = _paymentStatusBg(s);
        return GestureDetector(
          onTap: () => onSelect(s),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? bg : BillifyColors.surfaceLow,
              border: Border.all(
                color: isSelected ? color : BillifyColors.outlineVariant,
                width: isSelected ? 2 : 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_paymentStatusIcon(s),
                    size: 13,
                    color: isSelected ? color : BillifyColors.textSecondary),
                const SizedBox(width: 6),
                Text(s.toUpperCase(),
                    style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: isSelected
                            ? color
                            : BillifyColors.textSecondary)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  LEGACY SHIM — ClientFormScreen
//  Keeps main.dart route declarations compiling unchanged.
//  clientAdd  → ClientInfoFormScreen (no clientId)
//  clientEdit → ClientInfoFormScreen (with clientId)
// ════════════════════════════════════════════════════════════

class ClientFormScreen extends StatelessWidget {
  final String? clientId;
  final int reelIndex;
  const ClientFormScreen({super.key, this.clientId, this.reelIndex = 1});

  @override
  Widget build(BuildContext context) {
    // If called from clientEdit with a specific reelIndex > 0 and it's editing
    // a reel directly (not client info), go to reel form.
    // Otherwise default to client info form.
    if (clientId != null && reelIndex > 1) {
      return ClientReelFormScreen(clientId: clientId!, reelIndex: reelIndex);
    }
    return ClientInfoFormScreen(clientId: clientId);
  }
}