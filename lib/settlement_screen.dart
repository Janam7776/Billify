// ════════════════════════════════════════════════════════════
//  settlement_screen.dart — Billify Settlement Module
//
//  Features:
//    • Partners/Staff management — add, edit, remove partners
//    • Settlement per client — assign revenue split to partners
//    • Settlement status: Paid / Pending
//    • Settlement history per partner
//    • Overview of total settled vs pending
// ════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'main.dart'
    show BillifyColors, AppRoutes, BillifyDrawer, BillifyDialog, BillifyC, AppThemeContext;
import 'web_layout.dart' show WebScaffold, WebLayoutService;
import 'theme_controller.dart' show ThemeController;
import 'client_screens.dart' show ClientModel;

// ── Desktop-safe nav ──────────────────────────────────────────
void _navTo(String route, {Object? arguments}) {
  if (Get.isRegistered<WebLayoutService>()) {
    WebLayoutService.to.syncRoute(route);
  }
  Get.toNamed(route, arguments: arguments);
}

// ════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════

class PartnerModel {
  final String id;
  final String name;
  final String role;
  final String mobile;
  final String email;
  final DateTime createdAt;

  const PartnerModel({
    required this.id,
    required this.name,
    required this.role,
    required this.mobile,
    this.email = '',
    required this.createdAt,
  });

  factory PartnerModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return PartnerModel(
      id: doc.id,
      name: d['name'] as String? ?? '',
      role: d['role'] as String? ?? 'Partner',
      mobile: d['mobile'] as String? ?? '',
      email: d['email'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'role': role,
    'mobile': mobile,
    'email': email,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}

class SettlementModel {
  final String id;
  final String clientId;
  final String clientName;
  final String partnerId;
  final String partnerName;
  final double totalAmount;
  final double settledAmount;
  final String status; // 'Paid' | 'Pending' | 'Partial'
  final String notes;
  final DateTime createdAt;
  final DateTime? settledAt;

  const SettlementModel({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.partnerId,
    required this.partnerName,
    required this.totalAmount,
    required this.settledAmount,
    required this.status,
    this.notes = '',
    required this.createdAt,
    this.settledAt,
  });

  factory SettlementModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SettlementModel(
      id: doc.id,
      clientId: d['clientId'] as String? ?? '',
      clientName: d['clientName'] as String? ?? '',
      partnerId: d['partnerId'] as String? ?? '',
      partnerName: d['partnerName'] as String? ?? '',
      totalAmount: ((d['totalAmount'] ?? 0) as num).toDouble(),
      settledAmount: ((d['settledAmount'] ?? 0) as num).toDouble(),
      status: d['status'] as String? ?? 'Pending',
      notes: d['notes'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      settledAt: (d['settledAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'clientId': clientId,
    'clientName': clientName,
    'partnerId': partnerId,
    'partnerName': partnerName,
    'totalAmount': totalAmount,
    'settledAmount': settledAmount,
    'status': status,
    'notes': notes,
    'createdAt': Timestamp.fromDate(createdAt),
    'settledAt': settledAt != null ? Timestamp.fromDate(settledAt!) : null,
  };
}

// ════════════════════════════════════════════════════════════
//  SETTLEMENT SCREEN
// ════════════════════════════════════════════════════════════

class SettlementScreen extends StatefulWidget {
  const SettlementScreen({super.key});

  @override
  State<SettlementScreen> createState() => _SettlementScreenState();
}

class _SettlementScreenState extends State<SettlementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return WebScaffold(
      activeRoute: AppRoutes.settlement,
      appBar: AppBar(
        title: const Text('SETTLEMENT'),
        leading: Navigator.canPop(context)
            ? IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Get.back(),
        )
            : null,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'SETTLEMENTS'),
            Tab(text: 'PARTNERS'),
          ],
          labelStyle:
          GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2),
          unselectedLabelStyle:
          GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w600),
          labelColor: c.primary,
          unselectedLabelColor: c.textSecondary,
          indicatorColor: c.primary,
          indicatorWeight: 2.5,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _SettlementsTab(),
          _PartnersTab(),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  SETTLEMENTS TAB
// ════════════════════════════════════════════════════════════

class _SettlementsTab extends StatefulWidget {
  const _SettlementsTab();

  @override
  State<_SettlementsTab> createState() => _SettlementsTabState();
}

class _SettlementsTabState extends State<_SettlementsTab> {
  String _filterStatus = 'All';
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference get _settlRef => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('settlements');

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _markStatus(SettlementModel s, String newStatus) async {
    await _settlRef.doc(s.id).update({
      'status': newStatus,
      'settledAt':
      newStatus == 'Paid' ? Timestamp.fromDate(DateTime.now()) : null,
      'settledAmount': newStatus == 'Paid' ? s.totalAmount : s.settledAmount,
    });
  }

  Future<void> _deleteSettlement(String id) async {
    final confirm = await Get.dialog<bool>(BillifyDialog(
      title: 'Delete Settlement',
      body: 'Are you sure you want to delete this settlement record?',
      confirmLabel: 'Delete',
      icon: Icons.delete_forever_rounded,
      iconColor: BillifyColors.unpaid,
      confirmColor: BillifyColors.unpaid,
      onConfirm: () => Get.back(result: true),
    ));
    if (confirm == true) {
      await _settlRef.doc(id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          // Summary strip + search + filter
          _SettlementSummaryStrip(uid: _uid),

          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: 'Search by client or partner…',
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
                    : null,
              ),
            ),
          ),

          // Filter chips
          _StatusFilterBar(
            selected: _filterStatus,
            onChanged: (s) => setState(() => _filterStatus = s),
          ),

          const SizedBox(height: 4),

          // Settlement list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _settlRef.orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: c.primary));
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return _EmptyState(
                    icon: Icons.handshake_outlined,
                    title: 'No Settlements Yet',
                    subtitle: 'Tap + to create a settlement record for a client',
                  );
                }

                var items = snap.data!.docs
                    .map((d) => SettlementModel.fromDoc(d))
                    .toList();

                // Filter
                if (_filterStatus != 'All') {
                  items = items.where((s) => s.status == _filterStatus).toList();
                }
                if (_searchQuery.isNotEmpty) {
                  items = items
                      .where((s) =>
                  s.clientName.toLowerCase().contains(_searchQuery) ||
                      s.partnerName.toLowerCase().contains(_searchQuery))
                      .toList();
                }

                if (items.isEmpty) {
                  return _EmptyState(
                    icon: Icons.filter_alt_outlined,
                    title: 'No Results',
                    subtitle: 'Try changing filter or search term',
                  );
                }

                return Column(
                  children: [
                    // Item count bar
                    Container(
                      color: c.card,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Container(width: 3, height: 12, color: c.primary),
                          const SizedBox(width: 8),
                          Text(
                            '${items.length} SETTLEMENT${items.length != 1 ? 'S' : ''}',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              color: c.textSecondary,
                            ),
                          ),
                          const Spacer(),
                          if (_filterStatus != 'All')
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              color: c.primary.withOpacity(0.08),
                              child: Text(
                                _filterStatus.toUpperCase(),
                                style: GoogleFonts.poppins(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  color: c.primary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(height: 0.5, color: c.border),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                        itemCount: items.length,
                        itemBuilder: (ctx, i) => _SettlementCard(
                          settlement: items[i],
                          onMarkPaid: () => _markStatus(items[i], 'Paid'),
                          onMarkPending: () => _markStatus(items[i], 'Pending'),
                          onDelete: () => _deleteSettlement(items[i].id),
                          onEdit: () =>
                              _showSettlementForm(context, existing: items[i]),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSettlementForm(context),
        icon: const Icon(Icons.add_rounded),
        label: Text('ADD SETTLEMENT',
            style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w800)),
      ),
    );
  }

  void _showSettlementForm(BuildContext context,
      {SettlementModel? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettlementFormSheet(
        existing: existing,
        uid: _uid,
        settlRef: _settlRef,
      ),
    );
  }
}

// ── Settlement Summary Strip ──────────────────────────────────
class _SettlementSummaryStrip extends StatelessWidget {
  final String uid;
  const _SettlementSummaryStrip({required this.uid});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final fmt = NumberFormat.compact(locale: 'en_IN');

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settlements')
          .snapshots(),
      builder: (context, snap) {
        double totalAmount = 0, paidAmount = 0, pendingAmount = 0;
        int paidCount = 0, pendingCount = 0;

        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final s = SettlementModel.fromDoc(doc);
            totalAmount += s.totalAmount;
            if (s.status == 'Paid') {
              paidAmount += s.totalAmount;
              paidCount++;
            } else {
              pendingAmount += s.totalAmount;
              pendingCount++;
            }
          }
        }

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(
            color: c.card,
            border: Border.all(color: c.border, width: 0.5),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _SummaryTile('TOTAL', '₹${fmt.format(totalAmount)}',
                      Icons.account_balance_wallet_rounded, c.primary, c),
                  Container(width: 0.5, height: 52, color: c.border),
                  _SummaryTile('PAID', '₹${fmt.format(paidAmount)}',
                      Icons.check_circle_rounded, BillifyColors.paid, c,
                      sub: '$paidCount settled'),
                  Container(width: 0.5, height: 52, color: c.border),
                  _SummaryTile('PENDING', '₹${fmt.format(pendingAmount)}',
                      Icons.pending_rounded, BillifyColors.unpaid, c,
                      sub: '$pendingCount pending'),
                ],
              ),
              // Settlement progress bar
              if (totalAmount > 0) ...[
                Container(height: 0.5, color: c.border),
                ClipRect(
                  child: Stack(
                    children: [
                      Container(height: 4, color: BillifyColors.unpaid.withOpacity(0.18)),
                      FractionallySizedBox(
                        widthFactor: (paidAmount / totalAmount).clamp(0.0, 1.0),
                        child: Container(height: 4, color: BillifyColors.paid),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _SummaryTile(
      String label, String value, IconData icon, Color color, BillifyC c,
      {String? sub}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: c.textSecondary)),
                Text(value,
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: color)),
                if (sub != null)
                  Text(sub,
                      style: GoogleFonts.poppins(
                          fontSize: 7, color: c.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status Filter Bar ─────────────────────────────────────────
class _StatusFilterBar extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _StatusFilterBar({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    const statuses = ['All', 'Pending', 'Paid'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: statuses.map((s) {
          final active = s == selected;
          Color color = s == 'Paid'
              ? BillifyColors.paid
              : s == 'Pending'
              ? BillifyColors.unpaid
              : c.primary;
          return GestureDetector(
            onTap: () => onChanged(s),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? color : color.withOpacity(0.08),
                border: Border.all(
                    color: active ? color : color.withOpacity(0.3),
                    width: 1),
                borderRadius: BorderRadius.zero,
              ),
              child: Text(
                s.toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: active ? Colors.white : color,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Settlement Card ───────────────────────────────────────────
class _SettlementCard extends StatelessWidget {
  final SettlementModel settlement;
  final VoidCallback onMarkPaid;
  final VoidCallback onMarkPending;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  const _SettlementCard({
    required this.settlement,
    required this.onMarkPaid,
    required this.onMarkPending,
    required this.onDelete,
    required this.onEdit,
  });

  Color _statusColor() {
    switch (settlement.status) {
      case 'Paid':
        return BillifyColors.paid;
      case 'Partial':
        return BillifyColors.primary;
      default:
        return BillifyColors.unpaid;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final fmt =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final dateFmt = DateFormat('dd MMM yyyy');
    final statusColor = _statusColor();
    final progress = settlement.totalAmount > 0
        ? (settlement.settledAmount / settlement.totalAmount).clamp(0.0, 1.0)
        : 0.0;

    return Dismissible(
      key: ValueKey(settlement.id),
      direction: settlement.status != 'Paid'
          ? DismissDirection.endToStart
          : DismissDirection.none,
      confirmDismiss: (_) async {
        onMarkPaid();
        return false; // don't actually dismiss, just trigger action
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: BillifyColors.paid,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 6),
            Text('MARK PAID',
                style: GoogleFonts.poppins(
                    fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)),
          ],
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: c.card,
          border: Border(left: BorderSide(color: statusColor, width: 3)),
          boxShadow: [
            BoxShadow(
                color: c.border.withOpacity(0.3),
                blurRadius: 2,
                offset: const Offset(0, 1)),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              settlement.clientName,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.person_rounded,
                                    size: 11, color: c.textSecondary),
                                const SizedBox(width: 3),
                                Text(
                                  settlement.partnerName,
                                  style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Amount
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            fmt.format(settlement.totalAmount),
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: c.textPrimary,
                            ),
                          ),
                          // Status badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            color: statusColor.withOpacity(0.12),
                            child: Text(
                              settlement.status.toUpperCase(),
                              style: GoogleFonts.poppins(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Options menu
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert_rounded,
                            size: 18, color: c.textSecondary),
                        onSelected: (v) {
                          if (v == 'paid') onMarkPaid();
                          if (v == 'pending') onMarkPending();
                          if (v == 'edit') onEdit();
                          if (v == 'delete') onDelete();
                        },
                        itemBuilder: (_) => [
                          if (settlement.status != 'Paid')
                            _menuItem('paid', Icons.check_circle_rounded,
                                'Mark as Paid', BillifyColors.paid),
                          if (settlement.status == 'Paid')
                            _menuItem('pending', Icons.pending_rounded,
                                'Mark as Pending', BillifyColors.unpaid),
                          _menuItem(
                              'edit', Icons.edit_rounded, 'Edit', BillifyColors.primary),
                          _menuItem('delete', Icons.delete_rounded, 'Delete',
                              BillifyColors.unpaid),
                        ],
                      ),
                    ],
                  ),

                  // Settlement progress bar
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRect(
                          child: Stack(
                            children: [
                              Container(height: 3, color: c.border),
                              FractionallySizedBox(
                                widthFactor: progress,
                                child: Container(height: 3, color: statusColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.poppins(
                            fontSize: 8, fontWeight: FontWeight.w800,
                            color: statusColor),
                      ),
                    ],
                  ),

                  if (settlement.notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      color: c.background,
                      child: Text(
                        settlement.notes,
                        style: GoogleFonts.nunito(
                            fontSize: 11, color: c.textSecondary),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Footer
            Container(
              color: c.background,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 10, color: c.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Created ${dateFmt.format(settlement.createdAt)}',
                    style: GoogleFonts.poppins(
                        fontSize: 9, color: c.textSecondary),
                  ),
                  if (settlement.settledAt != null) ...[
                    const SizedBox(width: 12),
                    Icon(Icons.check_rounded, size: 10, color: BillifyColors.paid),
                    const SizedBox(width: 4),
                    Text(
                      'Settled ${dateFmt.format(settlement.settledAt!)}',
                      style: GoogleFonts.poppins(
                          fontSize: 9, color: BillifyColors.paid),
                    ),
                  ],
                  const Spacer(),
                  // Swipe hint for pending items
                  if (settlement.status != 'Paid')
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.swipe_left_rounded, size: 10, color: c.textSecondary.withOpacity(0.5)),
                        const SizedBox(width: 3),
                        Text('swipe to pay',
                            style: GoogleFonts.poppins(
                                fontSize: 8, color: c.textSecondary.withOpacity(0.5))),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
      String value, IconData icon, String label, Color color) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  SETTLEMENT FORM SHEET
// ════════════════════════════════════════════════════════════

class _SettlementFormSheet extends StatefulWidget {
  final SettlementModel? existing;
  final String uid;
  final CollectionReference settlRef;

  const _SettlementFormSheet({
    this.existing,
    required this.uid,
    required this.settlRef,
  });

  @override
  State<_SettlementFormSheet> createState() => _SettlementFormSheetState();
}

class _SettlementFormSheetState extends State<_SettlementFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String? _selectedClientId;
  String? _selectedClientName;
  String? _selectedPartnerId;
  String? _selectedPartnerName;
  String _status = 'Pending';
  bool _saving = false;

  List<ClientModel> _clients = [];
  List<PartnerModel> _partners = [];
  bool _loadingClients = true;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _amountCtrl.text = e.totalAmount.toStringAsFixed(0);
      _notesCtrl.text = e.notes;
      _selectedClientId = e.clientId;
      _selectedClientName = e.clientName;
      _selectedPartnerId = e.partnerId;
      _selectedPartnerName = e.partnerName;
      _status = e.status;
    }
    _loadOptions();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    final clientSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('clients')
        .orderBy('name')
        .get();

    final partnerSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('partners')
        .orderBy('name')
        .get();

    if (mounted) {
      setState(() {
        _clients = clientSnap.docs.map((d) => ClientModel.fromDoc(d)).toList();
        _partners = partnerSnap.docs.map((d) => PartnerModel.fromDoc(d)).toList();
        _loadingClients = false;
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClientId == null) {
      Get.snackbar('Error', 'Please select a client',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
      return;
    }
    if (_selectedPartnerId == null) {
      Get.snackbar('Error', 'Please select a partner',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
      return;
    }

    setState(() => _saving = true);
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    final now = DateTime.now();

    final data = SettlementModel(
      id: widget.existing?.id ?? '',
      clientId: _selectedClientId!,
      clientName: _selectedClientName!,
      partnerId: _selectedPartnerId!,
      partnerName: _selectedPartnerName!,
      totalAmount: amount,
      settledAmount: _status == 'Paid' ? amount : 0,
      status: _status,
      notes: _notesCtrl.text.trim(),
      createdAt: widget.existing?.createdAt ?? now,
      settledAt: _status == 'Paid' ? now : null,
    ).toMap();

    try {
      if (widget.existing != null) {
        await widget.settlRef.doc(widget.existing!.id).update(data);
      } else {
        await widget.settlRef.add(data);
      }
      Get.back();
      Get.snackbar(
        widget.existing != null ? 'Updated' : 'Created',
        'Settlement record saved',
        backgroundColor: BillifyColors.paid,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
      );
    } catch (e) {
      Get.snackbar('Error', 'Could not save settlement',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final isEdit = widget.existing != null;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.zero,
      ),
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top accent bar
          Container(height: 3, color: c.primary),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: _loadingClients
                ? const Center(child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ))
                : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: c.primary.withOpacity(0.1),
                      child: Icon(Icons.handshake_rounded,
                          color: c.primary, size: 16),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isEdit
                          ? 'EDIT SETTLEMENT'
                          : 'NEW SETTLEMENT',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: c.textPrimary),
                    ),
                  ]),
                  const SizedBox(height: 20),

                  // Client dropdown
                  _DropdownField<ClientModel>(
                    label: 'CLIENT',
                    hint: 'Select client',
                    items: _clients,
                    selectedId: _selectedClientId,
                    itemLabel: (c) => c.name,
                    itemId: (c) => c.id,
                    onChanged: (client) => setState(() {
                      _selectedClientId = client?.id;
                      _selectedClientName = client?.name;
                      if (client != null) {
                        _amountCtrl.text = client.totalPaymentAmount.toStringAsFixed(0);
                      }
                    }),
                  ),
                  const SizedBox(height: 12),

                  // Partner dropdown
                  _DropdownField<PartnerModel>(
                    label: 'PARTNER / STAFF',
                    hint: 'Select partner',
                    items: _partners,
                    selectedId: _selectedPartnerId,
                    itemLabel: (p) => '${p.name} (${p.role})',
                    itemId: (p) => p.id,
                    onChanged: (partner) => setState(() {
                      _selectedPartnerId = partner?.id;
                      _selectedPartnerName = partner?.name;
                    }),
                  ),
                  const SizedBox(height: 12),

                  // Amount
                  TextFormField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'))
                    ],
                    decoration: const InputDecoration(
                      labelText: 'AMOUNT (₹)',
                      prefixIcon:
                      Icon(Icons.currency_rupee_rounded, size: 16),
                    ),
                    validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Required'
                        : null,
                  ),
                  const SizedBox(height: 12),

                  // Status
                  Row(
                    children: [
                      Text('STATUS',
                          style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                              color: c.textSecondary)),
                      const SizedBox(width: 16),
                      ...['Pending', 'Paid'].map((s) {
                        final active = _status == s;
                        final color = s == 'Paid'
                            ? BillifyColors.paid
                            : BillifyColors.unpaid;
                        return GestureDetector(
                          onTap: () => setState(() => _status = s),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: active
                                  ? color
                                  : color.withOpacity(0.08),
                              border: Border.all(
                                  color: active
                                      ? color
                                      : color.withOpacity(0.4),
                                  width: 1),
                              borderRadius: BorderRadius.zero,
                            ),
                            child: Text(
                              s.toUpperCase(),
                              style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: active ? Colors.white : color,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Notes
                  TextFormField(
                    controller: _notesCtrl,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'NOTES (OPTIONAL)',
                      prefixIcon:
                      Icon(Icons.notes_rounded, size: 16),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                          : Text(
                        isEdit
                            ? 'UPDATE SETTLEMENT'
                            : 'CREATE SETTLEMENT',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.3),
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
}

// ── Generic Dropdown Field ────────────────────────────────────
class _DropdownField<T> extends StatelessWidget {
  final String label;
  final String hint;
  final List<T> items;
  final String? selectedId;
  final String Function(T) itemLabel;
  final String Function(T) itemId;
  final ValueChanged<T?> onChanged;

  const _DropdownField({
    required this.label,
    required this.hint,
    required this.items,
    required this.selectedId,
    required this.itemLabel,
    required this.itemId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final selected = selectedId != null
        ? items.where((i) => itemId(i) == selectedId).firstOrNull
        : null;

    return GestureDetector(
      onTap: () => _showPicker(context, c),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: context.isDark ? BillifyColors.darkCard : BillifyColors.surfaceLow,
          border: Border.all(
              color: context.isDark
                  ? BillifyColors.darkBorder
                  : BillifyColors.outlineVariant.withOpacity(0.6),
              width: 1),
          borderRadius: BorderRadius.zero,
        ),
        child: Row(
          children: [
            Icon(Icons.person_search_rounded, size: 16, color: c.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                      style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: c.textSecondary)),
                  Text(
                    selected != null ? itemLabel(selected) : hint,
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: selected != null
                          ? c.textPrimary
                          : c.textSecondary.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.expand_more_rounded, size: 18, color: c.textSecondary),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context, BillifyC c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        color: c.surface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 3, color: c.primary),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(
                label,
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: c.primary),
              ),
            ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No items available',
                    style: GoogleFonts.poppins(color: c.textSecondary)),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final item = items[i];
                    final isSelected = itemId(item) == selectedId;
                    return ListTile(
                      dense: true,
                      leading: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected ? c.primary : c.border,
                        ),
                      ),
                      title: Text(itemLabel(item),
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected ? c.primary : c.textPrimary)),
                      onTap: () {
                        Get.back();
                        onChanged(item);
                      },
                    );
                  },
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  PARTNERS TAB
// ════════════════════════════════════════════════════════════

class _PartnersTab extends StatefulWidget {
  const _PartnersTab();

  @override
  State<_PartnersTab> createState() => _PartnersTabState();
}

class _PartnersTabState extends State<_PartnersTab> {
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  CollectionReference get _partnerRef => FirebaseFirestore.instance
      .collection('users')
      .doc(_uid)
      .collection('partners');

  Future<void> _deletePartner(String id) async {
    final confirm = await Get.dialog<bool>(BillifyDialog(
      title: 'Remove Partner',
      body: 'Are you sure you want to remove this partner?',
      confirmLabel: 'Remove',
      icon: Icons.person_remove_rounded,
      iconColor: BillifyColors.unpaid,
      confirmColor: BillifyColors.unpaid,
      onConfirm: () => Get.back(result: true),
    ));
    if (confirm == true) {
      await _partnerRef.doc(id).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: StreamBuilder<QuerySnapshot>(
        stream: _partnerRef.orderBy('name').snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: c.primary));
          }
          if (!snap.hasData || snap.data!.docs.isEmpty) {
            return _EmptyState(
              icon: Icons.group_add_outlined,
              title: 'No Partners Yet',
              subtitle: 'Add partners or staff members to assign settlements',
            );
          }

          final partners = snap.data!.docs
              .map((d) => PartnerModel.fromDoc(d))
              .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Partner count header
              Container(
                color: c.card,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Container(width: 3, height: 14, color: c.primary),
                    const SizedBox(width: 8),
                    Text(
                      '${partners.length} PARTNER${partners.length != 1 ? 'S' : ''} / STAFF',
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: c.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    // Status legend
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PartnerLegendDot(color: BillifyColors.paid, label: 'Settled'),
                        const SizedBox(width: 8),
                        _PartnerLegendDot(color: BillifyColors.unpaid, label: 'Due'),
                        const SizedBox(width: 8),
                        _PartnerLegendDot(color: BillifyColors.primary, label: 'None'),
                      ],
                    ),
                  ],
                ),
              ),
              Container(height: 0.5, color: c.border),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                  itemCount: partners.length,
                  itemBuilder: (ctx, i) => _PartnerCard(
                    partner: partners[i],
                    uid: _uid,
                    onEdit: () => _showPartnerForm(context, existing: partners[i]),
                    onDelete: () => _deletePartner(partners[i].id),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showPartnerForm(context),
        icon: const Icon(Icons.person_add_rounded),
        label: Text('ADD PARTNER',
            style: GoogleFonts.poppins(
                fontSize: 10, fontWeight: FontWeight.w800)),
      ),
    );
  }

  void _showPartnerForm(BuildContext context, {PartnerModel? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PartnerFormSheet(
        existing: existing,
        partnerRef: _partnerRef,
      ),
    );
  }
}

// ── Partner Card ──────────────────────────────────────────────
class _PartnerCard extends StatelessWidget {
  final PartnerModel partner;
  final String uid;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PartnerCard({
    required this.partner,
    required this.uid,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final fmt = NumberFormat.compact(locale: 'en_IN');
    // Build initials (up to 2 chars)
    final initials = partner.name.trim().split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settlements')
          .where('partnerId', isEqualTo: partner.id)
          .snapshots(),
      builder: (context, snap) {
        double total = 0;
        double paid = 0;
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final s = SettlementModel.fromDoc(doc);
            total += s.totalAmount;
            if (s.status == 'Paid') paid += s.totalAmount;
          }
        }
        final due = total - paid;
        final progress = total > 0 ? (paid / total).clamp(0.0, 1.0) : 0.0;
        // Border accent: green if all paid, orange if partial/pending, blue if no settlements
        final accentColor = total == 0
            ? BillifyColors.primary
            : due == 0
            ? BillifyColors.paid
            : BillifyColors.unpaid;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: c.card,
            border: Border(left: BorderSide(color: accentColor, width: 3)),
            boxShadow: [
              BoxShadow(
                  color: c.border.withOpacity(0.3),
                  blurRadius: 2,
                  offset: const Offset(0, 1)),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // Avatar with initials
                    Container(
                      width: 44,
                      height: 44,
                      color: accentColor.withOpacity(0.12),
                      child: Center(
                        child: Text(
                          initials.isNotEmpty ? initials : '?',
                          style: GoogleFonts.poppins(
                            fontSize: initials.length > 1 ? 14 : 18,
                            fontWeight: FontWeight.w900,
                            color: accentColor,
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
                            partner.name,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                color: BillifyColors.primary.withOpacity(0.1),
                                child: Text(
                                  partner.role.toUpperCase(),
                                  style: GoogleFonts.poppins(
                                    fontSize: 7,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                    color: BillifyColors.primary,
                                  ),
                                ),
                              ),
                              if (partner.mobile.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Icon(Icons.phone_rounded,
                                    size: 10, color: c.textSecondary),
                                const SizedBox(width: 2),
                                Text(
                                  partner.mobile,
                                  style: GoogleFonts.poppins(
                                      fontSize: 10, color: c.textSecondary),
                                ),
                              ],
                            ],
                          ),
                          if (partner.email.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.email_rounded,
                                    size: 10, color: c.textSecondary),
                                const SizedBox(width: 2),
                                Text(
                                  partner.email,
                                  style: GoogleFonts.poppins(
                                      fontSize: 10, color: c.textSecondary),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Settlement stats
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '₹${fmt.format(total)}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          '₹${fmt.format(paid)} paid',
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            color: BillifyColors.paid,
                          ),
                        ),
                        if (due > 0)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            color: BillifyColors.unpaid.withOpacity(0.1),
                            child: Text(
                              '₹${fmt.format(due)} DUE',
                              style: GoogleFonts.poppins(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: BillifyColors.unpaid,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    // Options menu
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded,
                          size: 18, color: c.textSecondary),
                      onSelected: (v) {
                        if (v == 'edit') onEdit();
                        if (v == 'delete') onDelete();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            const Icon(Icons.edit_rounded,
                                size: 16, color: BillifyColors.primary),
                            const SizedBox(width: 10),
                            Text('Edit',
                                style: GoogleFonts.poppins(
                                    fontSize: 12, color: BillifyColors.primary)),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            const Icon(Icons.person_remove_rounded,
                                size: 16, color: BillifyColors.unpaid),
                            const SizedBox(width: 10),
                            Text('Remove',
                                style: GoogleFonts.poppins(
                                    fontSize: 12, color: BillifyColors.unpaid)),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Settlement progress bar at bottom of card
              if (total > 0) ...[
                Container(height: 0.5, color: c.border),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ClipRect(
                              child: Stack(
                                children: [
                                  Container(height: 3, color: c.border),
                                  FractionallySizedBox(
                                    widthFactor: progress,
                                    child: Container(
                                        height: 3, color: accentColor),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(progress * 100).toStringAsFixed(0)}% settled',
                            style: GoogleFonts.poppins(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: accentColor),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Partner Form Sheet ────────────────────────────────────────
class _PartnerFormSheet extends StatefulWidget {
  final PartnerModel? existing;
  final CollectionReference partnerRef;

  const _PartnerFormSheet({this.existing, required this.partnerRef});

  @override
  State<_PartnerFormSheet> createState() => _PartnerFormSheetState();
}

class _PartnerFormSheetState extends State<_PartnerFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  String _role = 'Partner';
  bool _saving = false;

  static const _kRoles = [
    'Partner',
    'Co-founder',
    'Staff',
    'Freelancer',
    'Videographer',
    'Photographer',
    'Editor',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _nameCtrl.text = e.name;
      _mobileCtrl.text = e.mobile;
      _emailCtrl.text = e.email;
      _role = e.role;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final data = PartnerModel(
      id: widget.existing?.id ?? '',
      name: _nameCtrl.text.trim(),
      role: _role,
      mobile: _mobileCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
    ).toMap();

    try {
      if (widget.existing != null) {
        await widget.partnerRef.doc(widget.existing!.id).update(data);
      } else {
        await widget.partnerRef.add(data);
      }
      Get.back();
      Get.snackbar(
        widget.existing != null ? 'Updated' : 'Added',
        'Partner saved successfully',
        backgroundColor: BillifyColors.paid,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
      );
    } catch (e) {
      Get.snackbar('Error', 'Could not save partner',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final isEdit = widget.existing != null;

    return Container(
      decoration: BoxDecoration(color: c.surface),
      padding:
      EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 3, color: c.primary),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        color: c.primary.withOpacity(0.1),
                        child: Icon(Icons.person_add_rounded,
                            color: c.primary, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isEdit ? 'EDIT PARTNER' : 'ADD PARTNER',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: c.textPrimary),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // Name
                    TextFormField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'FULL NAME',
                        prefixIcon: Icon(Icons.person_rounded, size: 16),
                      ),
                      validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),

                    // Role
                    DropdownButtonFormField<String>(
                      value: _role,
                      decoration: const InputDecoration(
                        labelText: 'ROLE',
                        prefixIcon: Icon(Icons.work_rounded, size: 16),
                      ),
                      style: GoogleFonts.nunito(
                          fontSize: 13,
                          color: c.textPrimary),
                      items: _kRoles.map((r) {
                        return DropdownMenuItem(value: r, child: Text(r));
                      }).toList(),
                      onChanged: (v) => setState(() => _role = v ?? _role),
                    ),
                    const SizedBox(height: 12),

                    // Mobile
                    TextFormField(
                      controller: _mobileCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'MOBILE (OPTIONAL)',
                        prefixIcon: Icon(Icons.phone_rounded, size: 16),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Email
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'EMAIL (OPTIONAL)',
                        prefixIcon: Icon(Icons.email_rounded, size: 16),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Save
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white))
                            : Text(
                          isEdit ? 'UPDATE PARTNER' : 'ADD PARTNER',
                          style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Partner Legend Dot ────────────────────────────────────────
class _PartnerLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _PartnerLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 8, fontWeight: FontWeight.w600,
                color: c.textSecondary)),
      ],
    );
  }
}

// ── Empty State ───────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              color: c.primary.withOpacity(0.08),
              child: Icon(icon, size: 36, color: c.primary.withOpacity(0.5)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: c.textSecondary, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}