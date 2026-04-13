// ════════════════════════════════════════════════════════════
//  expense_screens.dart — Billify
//  Expense & Income tracking: List, Add/Edit, Detail
// ════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'main.dart'
    show
    BillifyColors,
    AppRoutes,
    BillifyDrawer,
    AppSettings,
    BillifyC,
    BillifyDialog;
import 'web_layout.dart' show WebScaffold;

// ════════════════════════════════════════════════════════════
//  CONSTANTS
// ════════════════════════════════════════════════════════════

const List<String> kExpenseCategories = [
  'Equipment',
  'Software & Subscriptions',
  'Travel & Transport',
  'Food & Entertainment',
  'Marketing & Ads',
  'Office & Supplies',
  'Freelancer / Outsourcing',
  'Utilities',
  'Taxes & Fees',
  'Other',
];

const List<String> kIncomeCategories = [
  'Invoice Payment',
  'Freelance Project',
  'Retainer',
  'Bonus',
  'Refund',
  'Other Income',
];

// ════════════════════════════════════════════════════════════
//  DATA MODEL
// ════════════════════════════════════════════════════════════

class Expense {
  String id;
  String type;
  String title;
  String category;
  double amount;
  DateTime date;
  String note;
  String paymentMode;
  String whoPaid;       // NEW: person/entity who made the payment
  bool isTaxable;
  double taxPercent;

  Expense({
    this.id = '',
    this.type = 'expense',
    this.title = '',
    this.category = '',
    this.amount = 0,
    DateTime? date,
    this.note = '',
    this.paymentMode = 'UPI',
    this.whoPaid = '',
    this.isTaxable = false,
    this.taxPercent = 18,
  }) : date = date ?? DateTime.now();

  double get taxAmount => isTaxable ? amount * taxPercent / 100 : 0;
  double get netAmount => amount + taxAmount;

  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';

  Map<String, dynamic> toMap() => {
    'type': type,
    'title': title,
    'category': category,
    'amount': amount,
    'date': Timestamp.fromDate(date),
    'note': note,
    'paymentMode': paymentMode,
    'whoPaid': whoPaid,
    'isTaxable': isTaxable,
    'taxPercent': taxPercent,
    'netAmount': netAmount,
    'createdAt': FieldValue.serverTimestamp(),
  };

  factory Expense.fromMap(String id, Map<String, dynamic> m) => Expense(
    id: id,
    type: (m['type'] ?? 'expense') as String,
    title: (m['title'] ?? '') as String,
    category: (m['category'] ?? '') as String,
    amount: ((m['amount'] ?? 0) as num).toDouble(),
    date: (m['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
    note: (m['note'] ?? '') as String,
    paymentMode: (m['paymentMode'] ?? 'UPI') as String,
    whoPaid: (m['whoPaid'] ?? '') as String,
    isTaxable: (m['isTaxable'] ?? false) as bool,
    taxPercent: ((m['taxPercent'] ?? 18) as num).toDouble(),
  );
}

// ════════════════════════════════════════════════════════════
//  EXPENSE LIST SCREEN
// ════════════════════════════════════════════════════════════

class ExpenseListScreen extends StatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  State<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends State<ExpenseListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  String _searchQuery = '';
  String _filterCat = 'All';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Stream<QuerySnapshot> _stream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('expenses')
        .orderBy('date', descending: true)
        .snapshots();
  }

  List<Expense> _filter(List<QueryDocumentSnapshot> docs, String tab) {
    return docs
        .map((d) => Expense.fromMap(d.id, d.data() as Map<String, dynamic>))
        .where((e) {
      if (tab == 'expense' && !e.isExpense) return false;
      if (tab == 'income' && !e.isIncome) return false;
      if (_filterCat != 'All' && e.category != _filterCat) return false;
      final q = _searchQuery.toLowerCase();
      if (q.isNotEmpty &&
          !e.title.toLowerCase().contains(q) &&
          !e.category.toLowerCase().contains(q) &&
          !e.note.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  void _openDetail(Expense entry) {
    Get.toNamed(AppRoutes.expenseAdd, arguments: entry);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = AppSettings.currencyFmt();

    return WebScaffold(
      activeRoute: AppRoutes.expenses,
      backgroundColor: BillifyColors.background,
      appBar: AppBar(
        backgroundColor: BillifyColors.background,
        elevation: 0,
        title: Text(
          'EXPENSE LEDGER',
          style: GoogleFonts.poppins(
            fontSize: 11, fontWeight: FontWeight.w900,
            letterSpacing: 2.0, color: BillifyColors.primary,
          ),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: BillifyColors.primary,
          indicatorWeight: 2,
          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 1.2),
          unselectedLabelStyle: GoogleFonts.poppins(fontSize: 9, letterSpacing: 1.0),
          labelColor: BillifyColors.primary,
          unselectedLabelColor: BillifyColors.textSecondary,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(text: 'ALL'),
            Tab(text: 'EXPENSES'),
            Tab(text: 'INCOME'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.toNamed(AppRoutes.expenseAdd),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(
          'ADD ENTRY',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.2),
        ),
        backgroundColor: BillifyColors.primary,
        foregroundColor: const Color(0xFFF7F7FF),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(
              child:
              CircularProgressIndicator(color: BillifyColors.primary),
            );
          }

          final docs = snap.data?.docs ?? [];
          final allEntries = docs
              .map((d) =>
              Expense.fromMap(d.id, d.data() as Map<String, dynamic>))
              .toList();

          final totalIncome = allEntries
              .where((e) => e.isIncome)
              .fold(0.0, (s, e) => s + e.netAmount);
          final totalExpense = allEntries
              .where((e) => e.isExpense)
              .fold(0.0, (s, e) => s + e.netAmount);
          final netBalance = totalIncome - totalExpense;

          return Column(
            children: [
              _SummaryStrip(
                totalIncome: totalIncome,
                totalExpense: totalExpense,
                netBalance: netBalance,
                fmt: fmt,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: _buildSearchBar(),
              ),
              _CategoryChips(
                selected: _filterCat,
                onSelect: (c) => setState(() => _filterCat = c),
              ),
              Expanded(
                child: _buildTabViews(docs, fmt),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (v) => setState(() => _searchQuery = v),
      decoration: InputDecoration(
        hintText: 'SEARCH TITLE, CATEGORY, NOTE…',
        hintStyle: GoogleFonts.poppins(fontSize: 9, letterSpacing: 0.8, color: BillifyColors.outlineVariant),
        prefixIcon: const Icon(Icons.search_rounded, color: BillifyColors.primary, size: 18),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
          icon: const Icon(Icons.clear_rounded, size: 16, color: BillifyColors.textSecondary),
          onPressed: () {
            _searchCtrl.clear();
            setState(() => _searchQuery = '');
          },
        )
            : null,
        fillColor: BillifyColors.surface,
        filled: true,
        border: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: BillifyColors.outlineVariant, width: 0.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: BillifyColors.outlineVariant.withOpacity(0.4), width: 0.5)),
        focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: BillifyColors.primary, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        isDense: true,
      ),
    );
  }

  Widget _buildTabViews(List<QueryDocumentSnapshot> docs, NumberFormat fmt) {
    return TabBarView(
      controller: _tabCtrl,
      children: ['all', 'expense', 'income'].map((tab) {
        final items = _filter(docs, tab);
        if (items.isEmpty) return _EmptyExpenseState(tab: tab);
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 100),
          itemCount: items.length,
          itemBuilder: (_, i) => _ExpenseCard(
            entry: items[i],
            fmt: fmt,
            onTap: () => _openDetail(items[i]),
          ),
        );
      }).toList(),
    );
  }
}

// ── Summary Strip ─────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final double totalIncome;
  final double totalExpense;
  final double netBalance;
  final NumberFormat fmt;

  const _SummaryStrip({
    required this.totalIncome,
    required this.totalExpense,
    required this.netBalance,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BillifyColors.primary,
        border: Border(bottom: BorderSide(color: BillifyColors.primaryDark, width: 1)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _StripItem(
              label: 'INCOME',
              value: fmt.format(totalIncome),
              color: const Color(0xFF90EEC0),
            ),
            Container(width: 0.5, color: const Color(0xFFF7F7FF).withOpacity(0.2)),
            _StripItem(
              label: 'EXPENSE',
              value: fmt.format(totalExpense),
              color: const Color(0xFFFFAA99),
            ),
            Container(width: 0.5, color: const Color(0xFFF7F7FF).withOpacity(0.2)),
            _StripItem(
              label: 'NET BALANCE',
              value: fmt.format(netBalance),
              color: netBalance >= 0 ? const Color(0xFF90EEC0) : const Color(0xFFFFAA99),
              highlight: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _StripItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool highlight;

  const _StripItem({
    required this.label,
    required this.value,
    required this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 7, fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: const Color(0xFFF7F7FF).withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              style: GoogleFonts.poppins(
                fontSize: highlight ? 14 : 12,
                fontWeight: FontWeight.w900,
                color: color,
                letterSpacing: -0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// Kept for API compatibility — not rendered
class _StripDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ── Category filter chips ─────────────────────────────────────

class _CategoryChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _CategoryChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cats = ['All', ...kExpenseCategories, ...kIncomeCategories];
    return Container(
      height: 38,
      color: BillifyColors.surfaceContainer,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: cats.map((c) {
          final active = selected == c;
          return GestureDetector(
            onTap: () => onSelect(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              margin: const EdgeInsets.only(right: 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: active ? BillifyColors.primary : Colors.transparent,
                border: active ? null : Border.all(
                  color: BillifyColors.outlineVariant.withOpacity(0.4), width: 0.5,
                ),
              ),
              child: Text(
                c.toUpperCase(),
                style: GoogleFonts.poppins(
                  fontSize: 8, fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: active ? const Color(0xFFF7F7FF) : BillifyColors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Expense Card ──────────────────────────────────────────────

class _ExpenseCard extends StatelessWidget {
  final Expense entry;
  final NumberFormat fmt;
  final VoidCallback onTap;

  const _ExpenseCard({
    required this.entry,
    required this.fmt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = entry.isIncome;
    final color    = isIncome ? BillifyColors.paid : BillifyColors.unpaid;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          color: BillifyColors.surface,
          border: Border(
            left: BorderSide(color: color, width: 3),
            bottom: BorderSide(color: BillifyColors.outlineVariant.withOpacity(0.2), width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Type indicator
            Container(
              padding: const EdgeInsets.all(8),
              color: color.withOpacity(0.08),
              child: Icon(
                isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                color: color, size: 16,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildEntryInfo(context)),
            _buildAmountInfo(context, color),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryInfo(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.title.isEmpty ? entry.category : entry.title,
          style: GoogleFonts.poppins(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: BillifyColors.textPrimary,
          ),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            _Chip(label: entry.category, color: BillifyColors.primary),
            const SizedBox(width: 4),
            _Chip(label: entry.paymentMode, color: BillifyColors.textSecondary),
            if (entry.whoPaid.isNotEmpty) ...[
              const SizedBox(width: 4),
              _Chip(label: entry.whoPaid, color: const Color(0xFF1976D2)),
            ],
            const SizedBox(width: 4),
            Text(
              AppSettings.formatDate(entry.date).toUpperCase(),
              style: GoogleFonts.poppins(
                fontSize: 7, color: BillifyColors.textSecondary.withOpacity(0.7),
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAmountInfo(BuildContext context, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (AppSettings.showAmountOnList)
          Text(
            '${entry.isIncome ? '+' : '-'}${fmt.format(entry.amount)}',
            style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w900,
              color: color, letterSpacing: -0.3,
            ),
          ),
        if (AppSettings.showAmountOnList && entry.isTaxable)
          Text(
            '+${fmt.format(entry.taxAmount)} tax',
            style: GoogleFonts.poppins(
              fontSize: 8, color: BillifyColors.textSecondary, letterSpacing: 0.3,
            ),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      color: color.withOpacity(0.08),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 7, fontWeight: FontWeight.w800,
          letterSpacing: 0.5, color: color,
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────

class _EmptyExpenseState extends StatelessWidget {
  final String tab;
  const _EmptyExpenseState({required this.tab});

  @override
  Widget build(BuildContext context) {
    final isIncome = tab == 'income';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 3, height: 40, color: BillifyColors.outlineVariant.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text(
            tab == 'all' ? 'NO ENTRIES YET' : isIncome ? 'NO INCOME ENTRIES' : 'NO EXPENSE ENTRIES',
            style: GoogleFonts.poppins(
              fontSize: 9, fontWeight: FontWeight.w800,
              letterSpacing: 2.0, color: BillifyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap "Add Entry" to record your first entry',
            style: GoogleFonts.nunito(
              color: BillifyColors.textSecondary, fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Get.toNamed(AppRoutes.expenseAdd),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(160, 44),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              elevation: 0,
            ),
            child: Text(
              'ADD ENTRY',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  ADD / EDIT EXPENSE SCREEN
// ════════════════════════════════════════════════════════════

class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  late Expense _entry;
  bool _saving = false;
  bool _isEdit = false;

  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _whoPaidCtrl = TextEditingController();

  // Formats a raw digit string into comma-separated Indian numbering
  // e.g. "150000" → "1,50,000"
  static String _formatWithCommas(String raw) {
    final digits = raw.replaceAll(',', '');
    if (digits.isEmpty) return '';
    // Split on decimal point
    final parts = digits.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? '.${parts[1]}' : '';
    // Indian comma style: last 3 then every 2
    if (intPart.length <= 3) return '$intPart$decPart';
    final last3 = intPart.substring(intPart.length - 3);
    final rest = intPart.substring(0, intPart.length - 3);
    final commaRest = rest.replaceAllMapped(
      RegExp(r'(\d{1,2})(?=(\d{2})+$)'),
          (m) => '${m[1]},',
    );
    return '$commaRest,$last3$decPart';
  }

  // Strips commas and returns plain numeric string for parsing
  static double _parseCommaAmount(String text) {
    return double.tryParse(text.replaceAll(',', '')) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    final arg = Get.arguments;
    if (arg is Expense) {
      _entry = arg;
      _isEdit = true;
    } else {
      _entry = Expense();
    }
    _titleCtrl.text = _entry.title;
    _amountCtrl.text = _entry.amount == 0
        ? ''
        : _formatWithCommas(_entry.amount.toStringAsFixed(0));
    _noteCtrl.text = _entry.note;
    _whoPaidCtrl.text = _entry.whoPaid;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _whoPaidCtrl.dispose();
    super.dispose();
  }

  void _sync() {
    _entry.title = _titleCtrl.text.trim();
    _entry.amount = _parseCommaAmount(_amountCtrl.text);
    _entry.note = _noteCtrl.text.trim();
    _entry.whoPaid = _whoPaidCtrl.text.trim();
  }

  Future<void> _save() async {
    _sync();
    if (_entry.title.isEmpty) {
      Get.snackbar(
        'Missing Title',
        'Please enter a title for this entry',
        backgroundColor: BillifyColors.overdue,
        colorText: Colors.white,
      );
      return;
    }
    if (_entry.amount <= 0) {
      Get.snackbar(
        'Invalid Amount',
        'Please enter a valid amount',
        backgroundColor: BillifyColors.overdue,
        colorText: Colors.white,
      );
      return;
    }
    if (_entry.category.isEmpty) {
      Get.snackbar(
        'Missing Category',
        'Please select a category',
        backgroundColor: BillifyColors.overdue,
        colorText: Colors.white,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('expenses');
      if (_isEdit && _entry.id.isNotEmpty) {
        await col.doc(_entry.id).update(_entry.toMap());
      } else {
        await col.add(_entry.toMap());
      }
      Get.back();
      Get.snackbar(
        'Saved ✓',
        '${_entry.isIncome ? 'Income' : 'Expense'} entry saved',
        backgroundColor: BillifyColors.paid,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        e.toString(),
        backgroundColor: BillifyColors.unpaid,
        colorText: Colors.white,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await Get.dialog<bool>(
      BillifyDialog(
        icon: Icons.delete_outline_rounded,
        iconColor: BillifyColors.unpaid,
        title: 'Delete Entry?',
        body: 'This entry will be permanently removed from your records.',
        confirmLabel: 'Delete',
        confirmColor: BillifyColors.unpaid,
        onConfirm: () => Get.back(result: true),
      ),
    );
    if (confirm != true) return;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('expenses')
          .doc(_entry.id)
          .delete();
      Get.back();
      Get.snackbar(
        'Deleted',
        'Entry removed',
        backgroundColor: BillifyColors.paid,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Could not delete entry',
        backgroundColor: BillifyColors.unpaid,
        colorText: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = _entry.type == 'income';
    final categories = isIncome ? kIncomeCategories : kExpenseCategories;

    return Scaffold(
      backgroundColor: BillifyColors.background,
      appBar: AppBar(
        backgroundColor: BillifyColors.background,
        elevation: 0,
        title: Text(
          _isEdit
              ? 'EDIT ENTRY'
              : (_entry.type == 'income' ? 'ADD INCOME' : 'ADD EXPENSE'),
          style: GoogleFonts.poppins(
            fontSize: 11, fontWeight: FontWeight.w900,
            letterSpacing: 2.0, color: BillifyColors.primary,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: BillifyColors.outlineVariant.withOpacity(0.4)),
        ),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: BillifyColors.unpaid, size: 20),
              onPressed: _delete,
              tooltip: 'Delete',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTypeToggle(isIncome),
            const SizedBox(height: 16),
            _buildEntryDetailsCard(context, isIncome, categories),
            const SizedBox(height: 12),
            _buildDatePaymentCard(context),
            const SizedBox(height: 12),
            _buildTaxNotesCard(context),
            const SizedBox(height: 20),
            _buildSaveButton(isIncome),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeToggle(bool isIncome) {
    return Row(
      children: [
        Expanded(
          child: _TypeBtn(
            label: 'EXPENSE',
            icon: Icons.arrow_upward_rounded,
            active: !isIncome,
            activeColor: BillifyColors.unpaid,
            onTap: () => setState(() {
              _entry.type = 'expense';
              _entry.category = '';
            }),
          ),
        ),
        const SizedBox(width: 1),
        Expanded(
          child: _TypeBtn(
            label: 'INCOME',
            icon: Icons.arrow_downward_rounded,
            active: isIncome,
            activeColor: BillifyColors.paid,
            onTap: () => setState(() {
              _entry.type = 'income';
              _entry.category = '';
            }),
          ),
        ),
      ],
    );
  }

  // ── Entry details card ───────────────────────────────────────

  Widget _buildEntryDetailsCard(
      BuildContext context,
      bool isIncome,
      List<String> categories,
      ) {
    return _FormCard(
      title: 'Entry Details',
      icon: Icons.edit_note_rounded,
      children: [
        _field(
          ctrl: _titleCtrl,
          label: 'Title *',
          icon: Icons.label_rounded,
          hint: isIncome
              ? 'e.g. Client Payment — Reel Project'
              : 'e.g. Adobe Premiere License',
          onChanged: (_) {},
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _amountCtrl,
          keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d,.]')),
          ],
          onChanged: (raw) {
            final plain = raw.replaceAll(',', '');
            final formatted = _formatWithCommas(plain);
            if (formatted != raw) {
              _amountCtrl.value = TextEditingValue(
                text: formatted,
                selection: TextSelection.collapsed(offset: formatted.length),
              );
            }
          },
          decoration: InputDecoration(
            labelText: 'Amount (₹) *',
            prefixIcon: const Icon(
              Icons.currency_rupee_rounded,
              color: BillifyColors.primary,
            ),
            prefixText: '₹  ',
            prefixStyle: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        _SectionLabel('Category *'),
        const SizedBox(height: 8),
        _buildCategoryChips(context, isIncome, categories),
      ],
    );
  }

  Widget _buildCategoryChips(
      BuildContext context,
      bool isIncome,
      List<String> categories,
      ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: categories.map((cat) {
        final active = _entry.category == cat;
        return GestureDetector(
          onTap: () => setState(() => _entry.category = cat),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: active
                  ? (isIncome ? BillifyColors.paid : BillifyColors.primary)
                  : Theme.of(context).cardColor,
              borderRadius: BorderRadius.zero,
              border: Border.all(
                color: active
                    ? (isIncome
                    ? BillifyColors.paid
                    : BillifyColors.primary)
                    : BillifyColors.divider,
              ),
              boxShadow: active
                  ? [
                BoxShadow(
                  color: (isIncome
                      ? BillifyColors.paid
                      : BillifyColors.primary)
                      .withOpacity(0.2),
                  blurRadius: 6,
                ),
              ]
                  : [],
            ),
            child: Text(
              cat,
              style: GoogleFonts.nunito(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color:
                active ? Colors.white : BillifyColors.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Date & payment card ──────────────────────────────────────

  Widget _buildDatePaymentCard(BuildContext context) {
    return _FormCard(
      title: 'Date & Payment',
      icon: Icons.calendar_today_rounded,
      children: [
        _buildDatePicker(context),
        const SizedBox(height: 14),
        _SectionLabel('Payment Mode'),
        const SizedBox(height: 8),
        _buildPaymentModeChips(context),
        const SizedBox(height: 14),
        _field(
          ctrl: _whoPaidCtrl,
          label: 'Who Paid',
          icon: Icons.person_outline_rounded,
          hint: 'e.g. Self, Company, John…',
          onChanged: (_) {},
        ),
      ],
    );
  }

  Widget _buildDatePicker(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _entry.date,
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: const ColorScheme.light(
                primary: BillifyColors.primary,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) setState(() => _entry.date = picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: BillifyColors.background,
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: Theme.of(context).dividerColor,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              color: BillifyColors.primary,
              size: 18,
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Date',
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  AppSettings.formatDate(_entry.date),
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const Spacer(),
            const Icon(
              Icons.edit_calendar_rounded,
              color: BillifyColors.primary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentModeChips(BuildContext context) {
    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: ['Cash', 'UPI', 'Bank Transfer', 'Card', 'Cheque'].map((mode) {
        final active = _entry.paymentMode == mode;
        return GestureDetector(
          onTap: () => setState(() => _entry.paymentMode = mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: active ? BillifyColors.primary : BillifyColors.surfaceLow,
              border: active ? null : Border.all(
                color: BillifyColors.outlineVariant.withOpacity(0.4), width: 0.5,
              ),
            ),
            child: Text(
              mode.toUpperCase(),
              style: GoogleFonts.poppins(
                fontSize: 8, fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: active ? const Color(0xFFF7F7FF) : BillifyColors.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTaxNotesCard(BuildContext context) {
    return _FormCard(
      title: 'Tax & Notes',
      icon: Icons.notes_rounded,
      children: [
        _buildTaxToggle(context),
        if (_entry.isTaxable) ...[
          const SizedBox(height: 8),
          _buildTaxPreview(context),
        ],
        const SizedBox(height: 14),
        _field(
          ctrl: _noteCtrl,
          label: 'Note (optional)',
          icon: Icons.sticky_note_2_rounded,
          hint: 'Any extra detail…',
          lines: 2,
          onChanged: (_) {},
        ),
      ],
    );
  }

  Widget _buildTaxToggle(BuildContext context) {
    return Row(
      children: [
        Switch(
          value: _entry.isTaxable,
          onChanged: (v) => setState(() => _entry.isTaxable = v),
          activeColor: BillifyColors.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'INCLUDE GST / TAX',
            style: GoogleFonts.poppins(
              fontSize: 9, fontWeight: FontWeight.w800,
              letterSpacing: 1.0, color: BillifyColors.textPrimary,
            ),
          ),
        ),
        if (_entry.isTaxable)
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: _entry.taxPercent.toString(),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
              onChanged: (v) => setState(() => _entry.taxPercent = double.tryParse(v) ?? 18),
              decoration: InputDecoration(
                labelText: 'TAX %',
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: BillifyColors.outlineVariant.withOpacity(0.5))),
                focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: BillifyColors.primary, width: 2)),
              ),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildTaxPreview(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: BillifyColors.primary.withOpacity(0.06),
        border: Border(left: BorderSide(color: BillifyColors.primary, width: 2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'TAX AMOUNT',
            style: GoogleFonts.poppins(
              fontSize: 8, fontWeight: FontWeight.w800,
              letterSpacing: 1.0, color: BillifyColors.textSecondary,
            ),
          ),
          Text(
            '${AppSettings.currency}${(_entry.amount * _entry.taxPercent / 100).toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
              fontSize: 13, fontWeight: FontWeight.w900,
              color: BillifyColors.primary, letterSpacing: -0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton(bool isIncome) {
    if (_saving) {
      return const Center(child: CircularProgressIndicator(color: BillifyColors.primary));
    }
    return ElevatedButton(
      onPressed: _save,
      style: ElevatedButton.styleFrom(
        backgroundColor: isIncome ? BillifyColors.paid : BillifyColors.primary,
        minimumSize: const Size(double.infinity, 52),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        elevation: 0,
      ),
      child: Text(
        _isEdit ? 'UPDATE ENTRY' : 'COMMIT TO LEDGER',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.5),
      ),
    );
  }

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required IconData icon,
    String? hint,
    int lines = 1,
    required ValueChanged<String> onChanged,
  }) =>
      TextField(
        controller: ctrl,
        maxLines: lines,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, color: BillifyColors.primary),
          alignLabelWithHint: lines > 1,
        ),
      );
}

// ── Form helpers ──────────────────────────────────────────────

class _FormCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _FormCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BillifyColors.surface,
        border: Border.all(color: BillifyColors.outlineVariant.withOpacity(0.3), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: BillifyColors.primary.withOpacity(0.06),
              border: Border(bottom: BorderSide(color: BillifyColors.outlineVariant.withOpacity(0.3), width: 0.5)),
            ),
            child: Row(
              children: [
                Container(width: 3, height: 12, color: BillifyColors.primary),
                const SizedBox(width: 8),
                Icon(icon, size: 13, color: BillifyColors.primary),
                const SizedBox(width: 6),
                Text(
                  title.toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 9, fontWeight: FontWeight.w800,
                    letterSpacing: 1.5, color: BillifyColors.primary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _TypeBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? activeColor : BillifyColors.surfaceLow,
          border: Border.all(
            color: active ? activeColor : BillifyColors.outlineVariant.withOpacity(0.4),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: active ? const Color(0xFFF7F7FF) : BillifyColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: 10, fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
                color: active ? const Color(0xFFF7F7FF) : BillifyColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.poppins(
          fontSize: 8, fontWeight: FontWeight.w800,
          letterSpacing: 1.2, color: BillifyColors.textSecondary,
        ),
      ),
    );
  }
}