// ════════════════════════════════════════════════════════════
//  client_screens.dart — Billify Clients Module
//  Full CRUD client management: list, add, edit, detail, search, filter
//  Cloud-synced via Firestore under users/{uid}/clients
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

// ════════════════════════════════════════════════════════════
//  CLIENT MODEL
// ════════════════════════════════════════════════════════════

class ClientModel {
  final String id;
  final String name;
  final String mobile;
  final DateTime? projectStartDate;
  final String clientCategory;
  final double paymentAmount;
  final String paymentType;
  final String paymentStatus;
  final String reelCategory;
  final DateTime createdAt;
  final DateTime updatedAt;
  // Custom category support
  final String customClientCategory;
  final String customPaymentType;
  final String customReelCategory;

  const ClientModel({
    required this.id,
    required this.name,
    required this.mobile,
    this.projectStartDate,
    required this.clientCategory,
    required this.paymentAmount,
    required this.paymentType,
    required this.paymentStatus,
    required this.reelCategory,
    required this.createdAt,
    required this.updatedAt,
    this.customClientCategory = '',
    this.customPaymentType = '',
    this.customReelCategory = '',
  });

  factory ClientModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ClientModel(
      id: doc.id,
      name: d['name'] as String? ?? '',
      mobile: d['mobile'] as String? ?? '',
      projectStartDate: (d['projectStartDate'] as Timestamp?)?.toDate(),
      clientCategory: d['clientCategory'] as String? ?? 'Mobile Shoot',
      paymentAmount: ((d['paymentAmount'] ?? 0) as num).toDouble(),
      paymentType: d['paymentType'] as String? ?? 'Cash',
      paymentStatus: d['paymentStatus'] as String? ?? 'Pending',
      reelCategory: d['reelCategory'] as String? ?? 'Promotional Reel',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      customClientCategory: d['customClientCategory'] as String? ?? '',
      customPaymentType: d['customPaymentType'] as String? ?? '',
      customReelCategory: d['customReelCategory'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'mobile': mobile,
    'projectStartDate': projectStartDate != null
        ? Timestamp.fromDate(projectStartDate!)
        : null,
    'clientCategory': clientCategory,
    'paymentAmount': paymentAmount,
    'paymentType': paymentType,
    'paymentStatus': paymentStatus,
    'reelCategory': reelCategory,
    'customClientCategory': customClientCategory,
    'customPaymentType': customPaymentType,
    'customReelCategory': customReelCategory,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  String get displayCategory =>
      clientCategory == 'Custom' ? customClientCategory : clientCategory;
  String get displayPaymentType =>
      paymentType == 'Other' ? customPaymentType : paymentType;
  String get displayReelCategory =>
      reelCategory == 'Custom' ? customReelCategory : reelCategory;
}

// ════════════════════════════════════════════════════════════
//  CONSTANTS
// ════════════════════════════════════════════════════════════

const _kClientCategories = [
  'Mobile Shoot',
  'Camera Shoot',
  'Edit',
  // 'Outdoor Shoot',
  // 'Event Coverage',
  // 'Portrait Session',
  // 'Product Shoot',
  'Custom',
];

const _kPaymentTypes = [
  'Cash',
  'UPI',
  'Bank Transfer',
  'Card Payment',
  'Other',
];

const _kPaymentStatuses = [
  'Pending',
  'Advance',
  'Completed',
  'Overdue',
];

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
    case 'completed':
      return BillifyColors.paid;
    case 'advance':
      return const Color(0xFF1976D2);
    case 'overdue':
      return BillifyColors.overdue;
    default:
      return BillifyColors.unpaid;
  }
}

Color _paymentStatusBg(String s) {
  switch (s.toLowerCase()) {
    case 'completed':
      return const Color(0xFFE8F5E9);
    case 'advance':
      return const Color(0xFFE3F2FD);
    case 'overdue':
      return const Color(0xFFFFF3E0);
    default:
      return const Color(0xFFFFEBEE);
  }
}

IconData _paymentStatusIcon(String s) {
  switch (s.toLowerCase()) {
    case 'completed':
      return Icons.check_circle_rounded;
    case 'advance':
      return Icons.timelapse_rounded;
    case 'overdue':
      return Icons.warning_amber_rounded;
    default:
      return Icons.hourglass_empty_rounded;
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
          .where((c) =>
      c.name.toLowerCase().contains(q) ||
          c.mobile.contains(q))
          .toList();
    }

    if (_filterStatus != null) {
      clients = clients
          .where((c) =>
      c.paymentStatus.toLowerCase() == _filterStatus!.toLowerCase())
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
        backgroundColor: BillifyColors.primary,
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
                  return const Center(
                    child: CircularProgressIndicator(
                        color: BillifyColors.primary),
                  );
                }
                if (snap.hasError) {
                  return _ErrorState(message: snap.error.toString());
                }
                final clients = _filter(snap.data?.docs ?? []);
                if (clients.isEmpty) {
                  return _EmptyClientState(
                    hasFilter: _hasFilter || _searchQuery.isNotEmpty,
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  itemCount: clients.length,
                  separatorBuilder: (_, __) =>
                      Container(height: 1, color: BillifyColors.outlineVariant.withOpacity(0.4)),
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

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: BillifyColors.background,
      elevation: 0,
      title: Text(
        'CLIENTS',
        style: GoogleFonts.poppins(
          color: BillifyColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.0,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
            height: 1,
            color: BillifyColors.outlineVariant.withOpacity(0.4)),
      ),
      actions: [
        IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(Icons.filter_list_rounded,
                  color: _hasFilter
                      ? BillifyColors.primary
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
                      color: BillifyColors.unpaid,
                      shape: BoxShape.circle,
                    ),
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
          const Icon(Icons.search_rounded, color: BillifyColors.primary, size: 18),
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
              onRemove: () => setState(() => _filterStatus = null),
            ),
          if (_filterReelCategory != null)
            _FilterChip(
              label: _filterReelCategory!,
              onRemove: () => setState(() => _filterReelCategory = null),
            ),
          if (_filterClientCategory != null)
            _FilterChip(
              label: _filterClientCategory!,
              onRemove: () => setState(() => _filterClientCategory = null),
            ),
          TextButton(
            onPressed: () => setState(() {
              _filterStatus = null;
              _filterReelCategory = null;
              _filterClientCategory = null;
            }),
            style: TextButton.styleFrom(
              padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            ),
            child: Text(
              'CLEAR ALL',
              style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: BillifyColors.unpaid),
            ),
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
        'Are you sure you want to delete "${client.name}"? This action cannot be undone.',
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
      Get.snackbar(
        'Deleted',
        '${client.name} has been removed.',
        backgroundColor: BillifyColors.paid,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
      );
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
              width: 42,
              height: 42,
              color: BillifyColors.primary.withOpacity(0.12),
              child: Center(
                child: Text(
                  client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: BillifyColors.primary,
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
                  Text(
                    client.name,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    client.mobile,
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      color: c.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _MiniChip(label: client.displayCategory),
                      _MiniChip(label: client.displayReelCategory,
                          color: BillifyColors.primaryLight),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right column: amount + status + actions
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${NumberFormat('#,##,###.##').format(client.paymentAmount)}',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
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
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _IconAction(
                      icon: Icons.edit_rounded,
                      color: BillifyColors.primary,
                      onTap: () => Get.toNamed(AppRoutes.clientEdit,
                          arguments: client.id),
                    ),
                    const SizedBox(width: 4),
                    _IconAction(
                      icon: Icons.delete_rounded,
                      color: BillifyColors.unpaid,
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
          color: col,
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _IconAction(
      {required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        color: color.withOpacity(0.1),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  CLIENT ADD / EDIT SCREEN
// ════════════════════════════════════════════════════════════

class ClientFormScreen extends StatefulWidget {
  final String? clientId; // null = create mode
  const ClientFormScreen({super.key, this.clientId});

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isFetching = false;

  // Controllers
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _customCategoryCtrl = TextEditingController();
  final _customPaymentTypeCtrl = TextEditingController();
  final _customReelCtrl = TextEditingController();

  // State fields
  DateTime? _projectStartDate;
  String _clientCategory = 'Mobile Shoot';
  String _paymentType = 'Cash';
  String _paymentStatus = 'Pending';
  String _reelCategory = 'Promotional Reel';

  bool get _isEdit => widget.clientId != null;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    if (_isEdit) _fetchClient();
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
      final c = ClientModel.fromDoc(doc);
      _nameCtrl.text = c.name;
      _mobileCtrl.text = c.mobile;
      _amountCtrl.text = c.paymentAmount == 0 ? '' : c.paymentAmount.toString();
      _projectStartDate = c.projectStartDate;
      _clientCategory = c.clientCategory;
      _paymentType = c.paymentType;
      _paymentStatus = c.paymentStatus;
      _reelCategory = c.reelCategory;
      _customCategoryCtrl.text = c.customClientCategory;
      _customPaymentTypeCtrl.text = c.customPaymentType;
      _customReelCtrl.text = c.customReelCategory;
    } catch (_) {}
    if (mounted) setState(() => _isFetching = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _amountCtrl.dispose();
    _customCategoryCtrl.dispose();
    _customPaymentTypeCtrl.dispose();
    _customReelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _projectStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: BillifyColors.primary,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_projectStartDate ?? DateTime.now()),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: BillifyColors.primary,
          ),
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
    setState(() => _isLoading = true);

    final data = {
      'name': _nameCtrl.text.trim(),
      'mobile': _mobileCtrl.text.trim(),
      'projectStartDate': _projectStartDate != null
          ? Timestamp.fromDate(_projectStartDate!)
          : null,
      'clientCategory': _clientCategory,
      'paymentAmount':
      double.tryParse(_amountCtrl.text.trim()) ?? 0.0,
      'paymentType': _paymentType,
      'paymentStatus': _paymentStatus,
      'reelCategory': _reelCategory,
      'customClientCategory': _customCategoryCtrl.text.trim(),
      'customPaymentType': _customPaymentTypeCtrl.text.trim(),
      'customReelCategory': _customReelCtrl.text.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('clients');

      if (_isEdit) {
        await col.doc(widget.clientId).update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await col.add(data);
      }

      Get.back();
      Get.snackbar(
        _isEdit ? 'Updated' : 'Saved',
        _isEdit
            ? 'Client record updated successfully.'
            : 'New client added successfully.',
        backgroundColor: BillifyColors.paid,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
      );
    } catch (e) {
      Get.snackbar('Error', 'Could not save client. Try again.',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: BillifyColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: BillifyColors.primary),
          onPressed: () => Get.back(),
        ),
        title: Text(
          _isEdit ? 'EDIT CLIENT' : 'NEW CLIENT',
          style: GoogleFonts.poppins(
            color: BillifyColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              height: 1,
              color: BillifyColors.outlineVariant.withOpacity(0.4)),
        ),
      ),
      body: _isFetching
          ? const Center(
          child:
          CircularProgressIndicator(color: BillifyColors.primary))
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            // ── Basic Info ──────────────────────────────
            _SectionHeader(label: 'CLIENT INFORMATION'),
            const SizedBox(height: 12),
            _buildField(
              label: 'CLIENT NAME *',
              child: TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Enter client full name',
                  prefixIcon: Icon(Icons.person_rounded,
                      color: BillifyColors.primary, size: 18),
                ),
                validator: (v) =>
                (v == null || v.trim().isEmpty)
                    ? 'Name is required'
                    : null,
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
            _buildField(
              label: 'MOBILE NUMBER',
              child: TextFormField(
                controller: _mobileCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(15),
                ],
                decoration: const InputDecoration(
                  hintText: 'Enter mobile number (optional)',
                  prefixIcon: Icon(Icons.phone_rounded,
                      color: BillifyColors.primary, size: 18),
                ),
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty && v.trim().length < 7) {
                    return 'Enter a valid mobile number';
                  }
                  return null;
                },
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
            // ── Project Start Date ──────────────────────
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
                          .withOpacity(0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          color: BillifyColors.primary, size: 18),
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
                          onTap: () =>
                              setState(() => _projectStartDate = null),
                          child: const Icon(Icons.close_rounded,
                              size: 16,
                              color: BillifyColors.textSecondary),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Classification ─────────────────────────
            _SectionHeader(label: 'CLASSIFICATION'),
            const SizedBox(height: 12),
            _buildField(
              label: 'CLIENT CATEGORY *',
              child: _DropdownField<String>(
                value: _clientCategory,
                items: _kClientCategories,
                icon: Icons.category_rounded,
                onChanged: (v) =>
                    setState(() => _clientCategory = v!),
              ),
            ),
            if (_clientCategory == 'Custom') ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _customCategoryCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Enter custom category name',
                  prefixIcon: Icon(Icons.edit_rounded,
                      color: BillifyColors.primary, size: 16),
                ),
                validator: (v) => _clientCategory == 'Custom' &&
                    (v == null || v.trim().isEmpty)
                    ? 'Custom category is required'
                    : null,
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
            const SizedBox(height: 12),
            _buildField(
              label: 'REEL CATEGORY *',
              child: _DropdownField<String>(
                value: _reelCategory,
                items: _kReelCategories,
                icon: Icons.video_library_rounded,
                onChanged: (v) => setState(() => _reelCategory = v!),
              ),
            ),
            if (_reelCategory == 'Custom') ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _customReelCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Enter custom reel category',
                  prefixIcon: Icon(Icons.edit_rounded,
                      color: BillifyColors.primary, size: 16),
                ),
                validator: (v) => _reelCategory == 'Custom' &&
                    (v == null || v.trim().isEmpty)
                    ? 'Custom reel category is required'
                    : null,
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
            const SizedBox(height: 20),

            // ── Payment ────────────────────────────────
            _SectionHeader(label: 'PAYMENT DETAILS'),
            const SizedBox(height: 12),
            _buildField(
              label: 'PAYMENT AMOUNT *',
              child: TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.currency_rupee_rounded,
                      color: BillifyColors.primary, size: 18),
                ),
                validator: (v) =>
                (v == null || v.trim().isEmpty)
                    ? 'Payment amount is required'
                    : null,
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
            _buildField(
              label: 'PAYMENT TYPE *',
              child: _DropdownField<String>(
                value: _paymentType,
                items: _kPaymentTypes,
                icon: Icons.payment_rounded,
                onChanged: (v) => setState(() => _paymentType = v!),
              ),
            ),
            if (_paymentType == 'Other') ...[
              const SizedBox(height: 8),
              TextFormField(
                controller: _customPaymentTypeCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Describe the payment method',
                  prefixIcon: Icon(Icons.edit_rounded,
                      color: BillifyColors.primary, size: 16),
                ),
                validator: (v) => _paymentType == 'Other' &&
                    (v == null || v.trim().isEmpty)
                    ? 'Payment method description is required'
                    : null,
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
            const SizedBox(height: 12),
            _buildField(
              label: 'PAYMENT STATUS *',
              child: _PaymentStatusSelector(
                selected: _paymentStatus,
                onSelect: (v) => setState(() => _paymentStatus = v),
              ),
            ),
            const SizedBox(height: 32),

            // ── Save Button ────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
                    : Text(
                  _isEdit ? 'UPDATE CLIENT' : 'SAVE CLIENT',
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
            color: BillifyColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

// ── Dropdown helper ─────────────────────────────────────────

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
        prefixIcon: Icon(icon, color: BillifyColors.primary, size: 18),
      ),
      icon: const Icon(Icons.expand_more_rounded,
          color: BillifyColors.textSecondary, size: 18),
      style: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: BillifyColors.textPrimary),
      dropdownColor: BillifyColors.surface,
      items: items
          .map((e) => DropdownMenuItem<T>(
        value: e,
        child: Text(e.toString()),
      ))
          .toList(),
      onChanged: onChanged,
    );
  }
}

// ── Payment Status Selector ─────────────────────────────────

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
                    color: isSelected
                        ? color
                        : BillifyColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  s.toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: isSelected ? color : BillifyColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

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
          icon: const Icon(Icons.arrow_back_rounded,
              color: BillifyColors.primary),
          onPressed: () => Get.back(),
        ),
        title: Text(
          'CLIENT PROFILE',
          style: GoogleFonts.poppins(
            color: BillifyColors.primary,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              height: 1,
              color: BillifyColors.outlineVariant.withOpacity(0.4)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded,
                color: BillifyColors.primary, size: 20),
            onPressed: () =>
                Get.toNamed(AppRoutes.clientEdit, arguments: clientId),
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
            return const Center(
                child: CircularProgressIndicator(
                    color: BillifyColors.primary));
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
    final statusColor = _paymentStatusColor(client.paymentStatus);
    final statusBg = _paymentStatusBg(client.paymentStatus);
    final fmt = NumberFormat('#,##,###.##');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero card ────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: c.card,
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  color: BillifyColors.primary.withOpacity(0.12),
                  child: Center(
                    child: Text(
                      client.name.isNotEmpty
                          ? client.name[0].toUpperCase()
                          : '?',
                      style: GoogleFonts.poppins(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: BillifyColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  client.name,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  client.mobile,
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  color: statusBg,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_paymentStatusIcon(client.paymentStatus),
                          size: 14, color: statusColor),
                      const SizedBox(width: 6),
                      Text(
                        client.paymentStatus.toUpperCase(),
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Amount highlight ─────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: BillifyColors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TOTAL PAYMENT',
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${fmt.format(client.paymentAmount)}',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Via ${client.displayPaymentType}',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Details ──────────────────────────────────────
          _DetailCard(
            title: 'PROJECT DETAILS',
            rows: [
              if (client.projectStartDate != null)
                _DetailRow(
                  label: 'Start Date & Time',
                  value: DateFormat('dd MMM yyyy  hh:mm a')
                      .format(client.projectStartDate!),
                  icon: Icons.calendar_month_rounded,
                ),
              _DetailRow(
                label: 'Client Category',
                value: client.displayCategory,
                icon: Icons.category_rounded,
              ),
              _DetailRow(
                label: 'Reel Category',
                value: client.displayReelCategory,
                icon: Icons.video_library_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),

          _DetailCard(
            title: 'PAYMENT INFO',
            rows: [
              _DetailRow(
                label: 'Amount',
                value: '₹${fmt.format(client.paymentAmount)}',
                icon: Icons.currency_rupee_rounded,
              ),
              _DetailRow(
                label: 'Payment Type',
                value: client.displayPaymentType,
                icon: Icons.payment_rounded,
              ),
              _DetailRow(
                label: 'Status',
                value: client.paymentStatus,
                icon: _paymentStatusIcon(client.paymentStatus),
                valueColor: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 12),

          _DetailCard(
            title: 'RECORD TIMESTAMPS',
            rows: [
              _DetailRow(
                label: 'Created',
                value: DateFormat('dd MMM yyyy  hh:mm a')
                    .format(client.createdAt),
                icon: Icons.add_circle_outline_rounded,
              ),
              _DetailRow(
                label: 'Last Updated',
                value: DateFormat('dd MMM yyyy  hh:mm a')
                    .format(client.updatedAt),
                icon: Icons.update_rounded,
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Edit button ──────────────────────────────────
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () =>
                  Get.toNamed(AppRoutes.clientEdit, arguments: clientId),
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: Text(
                'EDIT CLIENT',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: BillifyColors.surfaceContainer,
            child: Row(
              children: [
                Container(
                    width: 3, height: 12, color: BillifyColors.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: BillifyColors.primary,
                  ),
                ),
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
          Icon(icon, size: 16, color: BillifyColors.primary.withOpacity(0.7)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor ?? c.textPrimary,
              ),
            ),
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
          Container(height: 3, color: BillifyColors.primary),
          const SizedBox(height: 16),
          Text(
            'FILTER CLIENTS',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
              color: BillifyColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          _filterGroup('PAYMENT STATUS', _kPaymentStatuses, _status,
                  (v) => setState(() => _status = _status == v ? null : v)),
          const SizedBox(height: 12),
          _filterGroup('CLIENT CATEGORY',
              _kClientCategories.where((c) => c != 'Custom').toList(),
              _category,
                  (v) =>
                  setState(() => _category = _category == v ? null : v)),
          const SizedBox(height: 12),
          _filterGroup('REEL CATEGORY',
              _kReelCategories.where((c) => c != 'Custom').toList(),
              _reel,
                  (v) => setState(() => _reel = _reel == v ? null : v)),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _status = null;
                      _reel = null;
                      _category = null;
                    });
                  },
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
        Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: BillifyColors.textSecondary,
          ),
        ),
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
                      ? BillifyColors.primary
                      : BillifyColors.surfaceLow,
                  border: Border.all(
                    color: isSel
                        ? BillifyColors.primary
                        : BillifyColors.outlineVariant,
                  ),
                ),
                child: Text(
                  o,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isSel ? Colors.white : BillifyColors.textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
//  DASHBOARD RECENT CLIENTS WIDGET (exported for dashboard use)
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
          // Section header
          Row(
            children: [
              Container(width: 3, height: 14, color: BillifyColors.primary),
              const SizedBox(width: 8),
              Text(
                'RECENT CLIENTS',
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.8,
                  color: BillifyColors.primary,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Get.toNamed(AppRoutes.clients),
                child: Text(
                  'VIEW ALL →',
                  style: GoogleFonts.poppins(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: BillifyColors.primary,
                  ),
                ),
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
                return const Center(
                    child: CircularProgressIndicator(
                        color: BillifyColors.primary, strokeWidth: 2));
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return _DashboardEmptyClients();
              }
              final clients = docs.map((d) => ClientModel.fromDoc(d)).toList();
              return Column(
                children: clients
                    .map((c) => _DashboardClientRow(client: c))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: 8),
          // Add client quick action
          GestureDetector(
            onTap: () => Get.toNamed(AppRoutes.clientAdd),
            child: Container(
              width: double.infinity,
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: BillifyColors.primary.withOpacity(0.06),
                border: Border.all(
                    color: BillifyColors.primary.withOpacity(0.2),
                    width: 1,
                    style: BorderStyle.solid),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_add_rounded,
                      size: 14, color: BillifyColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'ADD NEW CLIENT',
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: BillifyColors.primary,
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
      onTap: () =>
          Get.toNamed(AppRoutes.clientDetail, arguments: client.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        margin: const EdgeInsets.only(bottom: 1),
        color: c.card,
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              color: BillifyColors.primary.withOpacity(0.12),
              child: Center(
                child: Text(
                  client.name.isNotEmpty ? client.name[0].toUpperCase() : '?',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: BillifyColors.primary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    client.name,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    client.displayCategory,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${fmt.format(client.paymentAmount)}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  client.paymentStatus,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
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
            color: BillifyColors.primary.withOpacity(0.1),
            child: const Icon(Icons.people_outline_rounded,
                color: BillifyColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            'No clients yet. Add your first client!',
            style: GoogleFonts.nunito(
              fontSize: 13,
              color: BillifyColors.textSecondary,
            ),
          ),
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
        Container(width: 3, height: 14, color: BillifyColors.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
            color: BillifyColors.primary,
          ),
        ),
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
        color: BillifyColors.primary.withOpacity(0.1),
        border: Border.all(color: BillifyColors.primary.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.poppins(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: BillifyColors.primary,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded,
                size: 12, color: BillifyColors.primary),
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
              color: BillifyColors.primary.withOpacity(0.08),
              child: const Icon(Icons.people_outline_rounded,
                  size: 48, color: BillifyColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              hasFilter ? 'NO MATCHES' : 'NO CLIENTS YET',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                color: BillifyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Try adjusting your search or filters to find clients.'
                  : 'Add your first client to start tracking projects and payments.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 13,
                color: BillifyColors.textSecondary,
                height: 1.5,
              ),
            ),
            if (!hasFilter) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Get.toNamed(AppRoutes.clientAdd),
                icon: const Icon(Icons.person_add_rounded, size: 16),
                label: Text(
                  'ADD FIRST CLIENT',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 1.2),
                ),
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