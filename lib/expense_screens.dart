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

import 'main.dart' show BillifyColors, AppRoutes, BillifyDrawer, AppSettings, BillifyC,
BillifyDialog;

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
  String   id;
  String   type;        // 'expense' | 'income'
  String   title;
  String   category;
  double   amount;
  DateTime date;
  String   note;
  String   paymentMode; // Cash / UPI / Bank Transfer / Card / Cheque
  bool     isTaxable;
  double   taxPercent;

  Expense({
    this.id          = '',
    this.type        = 'expense',
    this.title       = '',
    this.category    = '',
    this.amount      = 0,
    DateTime? date,
    this.note        = '',
    this.paymentMode = 'UPI',
    this.isTaxable   = false,
    this.taxPercent  = 18,
  }) : date = date ?? DateTime.now();

  double get taxAmount  => isTaxable ? amount * taxPercent / 100 : 0;
  double get netAmount  => amount + taxAmount;

  bool get isIncome  => type == 'income';
  bool get isExpense => type == 'expense';

  Map<String, dynamic> toMap() => {
    'type':        type,
    'title':       title,
    'category':    category,
    'amount':      amount,
    'date':        Timestamp.fromDate(date),
    'note':        note,
    'paymentMode': paymentMode,
    'isTaxable':   isTaxable,
    'taxPercent':  taxPercent,
    'netAmount':   netAmount,
    'createdAt':   FieldValue.serverTimestamp(),
  };

  factory Expense.fromMap(String id, Map<String, dynamic> m) => Expense(
    id:          id,
    type:        (m['type']        ?? 'expense') as String,
    title:       (m['title']       ?? '')        as String,
    category:    (m['category']    ?? '')        as String,
    amount:      ((m['amount']     ?? 0) as num).toDouble(),
    date:        (m['date']        as Timestamp?)?.toDate() ?? DateTime.now(),
    note:        (m['note']        ?? '') as String,
    paymentMode: (m['paymentMode'] ?? 'UPI') as String,
    isTaxable:   (m['isTaxable']   ?? false) as bool,
    taxPercent:  ((m['taxPercent'] ?? 18) as num).toDouble(),
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
  String _filterCat   = 'All';
  final _searchCtrl   = TextEditingController();

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
        .collection('users').doc(uid).collection('expenses')
        .orderBy('date', descending: true)
        .snapshots();
  }

  List<Expense> _filter(List<QueryDocumentSnapshot> docs, String tab) {
    return docs
        .map((d) => Expense.fromMap(d.id, d.data() as Map<String, dynamic>))
        .where((e) {
      if (tab == 'expense' && !e.isExpense) return false;
      if (tab == 'income'  && !e.isIncome)  return false;
      if (_filterCat != 'All' && e.category != _filterCat) return false;
      final q = _searchQuery.toLowerCase();
      if (q.isNotEmpty &&
          !e.title.toLowerCase().contains(q) &&
          !e.category.toLowerCase().contains(q) &&
          !e.note.toLowerCase().contains(q)) return false;
      return true;
    })
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final fmt = AppSettings.currencyFmt();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: const BillifyDrawer(activeRoute: AppRoutes.expenses),
      appBar: AppBar(
        title: const Text('Expenses & Income'),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: BillifyColors.accent,
          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
          unselectedLabelStyle: GoogleFonts.nunito(fontSize: 13),
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Expenses'),
            Tab(text: 'Income'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.toNamed(AppRoutes.expenseAdd),
        icon:  const Icon(Icons.add_rounded),
        label: Text('Add Entry', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(color: BillifyColors.primary));
          }
          final docs = snap.data?.docs ?? [];

          // Compute totals for the summary strip
          final allEntries = docs
              .map((d) => Expense.fromMap(d.id, d.data() as Map<String, dynamic>))
              .toList();
          final totalIncome  = allEntries.where((e) => e.isIncome).fold(0.0, (s, e) => s + e.netAmount);
          final totalExpense = allEntries.where((e) => e.isExpense).fold(0.0, (s, e) => s + e.netAmount);
          final netBalance   = totalIncome - totalExpense;

          return Column(
            children: [
              // ── Summary strip ─────────────────────────────
              _SummaryStrip(
                totalIncome:  totalIncome,
                totalExpense: totalExpense,
                netBalance:   netBalance,
                fmt:          fmt,
              ),

              // ── Search bar ────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText:   'Search title, category, note…',
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: BillifyColors.primary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        })
                        : null,
                    isDense: true,
                  ),
                ),
              ),

              // ── Category filter chips ─────────────────────
              _CategoryChips(
                selected: _filterCat,
                onSelect: (c) => setState(() => _filterCat = c),
              ),

              // ── Tab views ─────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: ['all', 'expense', 'income'].map((tab) {
                    final items = _filter(docs, tab);
                    if (items.isEmpty) {
                      return _EmptyExpenseState(tab: tab);
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 100),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _ExpenseCard(
                        entry: items[i],
                        fmt:   fmt,
                        onTap: () => _openDetail(items[i]),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _openDetail(Expense entry) {
    Get.toNamed(AppRoutes.expenseAdd, arguments: entry);
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
      margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [BillifyColors.primary, BillifyColors.primaryLight],
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color:      BillifyColors.primary.withOpacity(0.3),
            blurRadius: 12,
            offset:     const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          _StripItem(
            label: 'Income',
            value: fmt.format(totalIncome),
            icon:  Icons.arrow_downward_rounded,
            color: const Color(0xFF69F0AE),
          ),
          _StripDivider(),
          _StripItem(
            label: 'Expense',
            value: fmt.format(totalExpense),
            icon:  Icons.arrow_upward_rounded,
            color: const Color(0xFFFF8A80),
          ),
          _StripDivider(),
          _StripItem(
            label: 'Net',
            value: fmt.format(netBalance),
            icon:  Icons.account_balance_rounded,
            color: netBalance >= 0
                ? const Color(0xFF69F0AE)
                : const Color(0xFFFF8A80),
            highlight: true,
          ),
        ],
      ),
    );
  }
}

class _StripItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool highlight;
  const _StripItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 4),
              Text(label,
                  style: GoogleFonts.nunito(
                      fontSize: 11,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.poppins(
              fontSize:   highlight ? 14 : 13,
              fontWeight: FontWeight.w700,
              color:      highlight ? color : Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _StripDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 1, height: 36,
    color: Colors.white.withOpacity(0.2),
    margin: const EdgeInsets.symmetric(horizontal: 4),
  );
}

// ── Category filter chips ────────────────────────────────────
class _CategoryChips extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _CategoryChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cats = ['All', ...kExpenseCategories, ...kIncomeCategories];
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        children: cats.map((c) {
          final active = selected == c;
          return GestureDetector(
            onTap: () => onSelect(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: active ? BillifyColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: active ? BillifyColors.primary : BillifyColors.divider),
                boxShadow: active
                    ? [BoxShadow(
                    color: BillifyColors.primary.withOpacity(0.2),
                    blurRadius: 6, offset: const Offset(0, 2))]
                    : [],
              ),
              child: Text(
                c,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? Colors.white : BillifyColors.textSecondary,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Expense Card ─────────────────────────────────────────────
class _ExpenseCard extends StatelessWidget {
  final Expense      entry;
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
    final bgColor  = isIncome ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.all(AppSettings.compactCards ? 10 : 14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppSettings.compactCards ? 12 : 14),
          boxShadow: [
            BoxShadow(
              color:      BillifyColors.primary.withOpacity(0.05),
              blurRadius: 8,
              offset:     const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                  color: bgColor, borderRadius: BorderRadius.circular(12)),
              child: Icon(
                isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                color: color, size: 22,
              ),
            ),
            const SizedBox(width: 12),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title.isEmpty ? entry.category : entry.title,
                    style: GoogleFonts.poppins(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _Chip(label: entry.category, color: BillifyColors.primary),
                      SizedBox(width: 6),
                      _Chip(label: entry.paymentMode, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppSettings.formatDate(entry.date),
                    style: GoogleFonts.nunito(
                        fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),

            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (AppSettings.showAmountOnList)
                  Text(
                    '${isIncome ? '+' : '-'}${fmt.format(entry.amount)}',
                    style: GoogleFonts.poppins(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                if (AppSettings.showAmountOnList && entry.isTaxable)
                  Text(
                    'Tax: ${fmt.format(entry.taxAmount)}',
                    style: GoogleFonts.nunito(
                        fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color  color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color:        color.withOpacity(0.09),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(label,
        style: GoogleFonts.nunito(
            fontSize: 10, fontWeight: FontWeight.w700, color: color)),
  );
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
          Icon(
            isIncome
                ? Icons.savings_outlined
                : Icons.receipt_outlined,
            size: 64,
            color: BillifyColors.primary.withOpacity(0.2),
          ),
          const SizedBox(height: 14),
          Text(
            tab == 'all'
                ? 'No entries yet'
                : isIncome
                ? 'No income entries'
                : 'No expense entries',
            style: GoogleFonts.poppins(
                fontSize: 16, fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "Add Entry" to record your first entry',
            style: GoogleFonts.nunito(
                color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Get.toNamed(AppRoutes.expenseAdd),
            icon:  const Icon(Icons.add_rounded, size: 18),
            label: Text('Add Entry',
                style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600, fontSize: 13)),
            style: ElevatedButton.styleFrom(
                minimumSize: const Size(140, 42)),
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
  bool _saving   = false;
  bool _isEdit   = false;

  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl  = TextEditingController();

  @override
  void initState() {
    super.initState();
    final arg = Get.arguments;
    if (arg is Expense) {
      _entry  = arg;
      _isEdit = true;
    } else {
      _entry = Expense();
    }
    _titleCtrl.text  = _entry.title;
    _amountCtrl.text = _entry.amount == 0 ? '' : _entry.amount.toString();
    _noteCtrl.text   = _entry.note;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _sync() {
    _entry.title  = _titleCtrl.text.trim();
    _entry.amount = double.tryParse(_amountCtrl.text) ?? 0;
    _entry.note   = _noteCtrl.text.trim();
  }

  Future<void> _save() async {
    _sync();
    if (_entry.title.isEmpty) {
      Get.snackbar('Missing Title', 'Please enter a title for this entry',
          backgroundColor: BillifyColors.overdue, colorText: Colors.white);
      return;
    }
    if (_entry.amount <= 0) {
      Get.snackbar('Invalid Amount', 'Please enter a valid amount',
          backgroundColor: BillifyColors.overdue, colorText: Colors.white);
      return;
    }
    if (_entry.category.isEmpty) {
      Get.snackbar('Missing Category', 'Please select a category',
          backgroundColor: BillifyColors.overdue, colorText: Colors.white);
      return;
    }

    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final col = FirebaseFirestore.instance
          .collection('users').doc(uid).collection('expenses');
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
      Get.snackbar('Error', e.toString(),
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirm = await Get.dialog<bool>(
      BillifyDialog(
        icon:         Icons.delete_outline_rounded,
        iconColor:    BillifyColors.unpaid,
        title:        'Delete Entry?',
        body:         'This entry will be permanently removed from your records.',
        confirmLabel: 'Delete',
        confirmColor: BillifyColors.unpaid,
        onConfirm:    () => Get.back(result: true),
      ),
    );
    if (confirm != true) return;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('expenses').doc(_entry.id)
          .delete();
      Get.back();
      Get.snackbar('Deleted', 'Entry removed',
          backgroundColor: BillifyColors.paid,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP);
    } catch (e) {
      Get.snackbar('Error', 'Could not delete entry',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncome    = _entry.type == 'income';
    final categories  = isIncome ? kIncomeCategories : kExpenseCategories;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_isEdit
            ? 'Edit Entry'
            : (_entry.type == 'income' ? 'Add Income' : 'Add Expense')),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
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

            // ── Type toggle ────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: BillifyColors.primary.withOpacity(0.07),
                      blurRadius: 8, offset: const Offset(0, 3)),
                ],
              ),
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  _TypeBtn(
                    label: 'Expense',
                    icon:  Icons.arrow_upward_rounded,
                    active: !isIncome,
                    activeColor: BillifyColors.unpaid,
                    onTap: () => setState(() {
                      _entry.type     = 'expense';
                      _entry.category = '';
                    }),
                  ),
                  _TypeBtn(
                    label: 'Income',
                    icon:  Icons.arrow_downward_rounded,
                    active: isIncome,
                    activeColor: BillifyColors.paid,
                    onTap: () => setState(() {
                      _entry.type     = 'income';
                      _entry.category = '';
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Title ──────────────────────────────────────
            _FormCard(
              title: 'Entry Details',
              icon: Icons.edit_note_rounded,
              children: [
                _field(
                  ctrl:  _titleCtrl,
                  label: 'Title *',
                  icon:  Icons.label_rounded,
                  hint:  isIncome
                      ? 'e.g. Client Payment — Reel Project'
                      : 'e.g. Adobe Premiere License',
                  onChanged: (_) {},
                ),
                const SizedBox(height: 14),

                // Amount
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  onChanged: (_) {},
                  decoration: InputDecoration(
                    labelText: 'Amount (₹) *',
                    prefixIcon: const Icon(Icons.currency_rupee_rounded,
                        color: BillifyColors.primary),
                    prefixText: '₹  ',
                    prefixStyle: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface),
                  ),
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),

                // Category picker
                _SectionLabel('Category *'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: categories.map((cat) {
                    final active = _entry.category == cat;
                    return GestureDetector(
                      onTap: () => setState(() => _entry.category = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: active ? (isIncome ? BillifyColors.paid : BillifyColors.primary) : Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: active
                                ? (isIncome ? BillifyColors.paid : BillifyColors.primary)
                                : BillifyColors.divider,
                          ),
                          boxShadow: active
                              ? [BoxShadow(
                              color: (isIncome ? BillifyColors.paid : BillifyColors.primary)
                                  .withOpacity(0.2),
                              blurRadius: 6)]
                              : [],
                        ),
                        child: Text(
                          cat,
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: active ? Colors.white : BillifyColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Date & Payment ─────────────────────────────
            _FormCard(
              title: 'Date & Payment',
              icon: Icons.calendar_today_rounded,
              children: [
                // Date picker
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _entry.date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                      builder: (ctx, child) => Theme(
                        data: Theme.of(ctx).copyWith(
                          colorScheme: const ColorScheme.light(
                              primary: BillifyColors.primary),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) setState(() => _entry.date = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: BillifyColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).dividerColor, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today_rounded,
                            color: BillifyColors.primary, size: 18),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Date',
                                style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            Text(
                              AppSettings.formatDate(_entry.date),
                              style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const Spacer(),
                        const Icon(Icons.edit_calendar_rounded,
                            color: BillifyColors.primary, size: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Payment mode
                _SectionLabel('Payment Mode'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: ['Cash', 'UPI', 'Bank Transfer', 'Card', 'Cheque']
                      .map((mode) {
                    final active = _entry.paymentMode == mode;
                    return GestureDetector(
                      onTap: () => setState(() => _entry.paymentMode = mode),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: active
                              ? BillifyColors.primary.withOpacity(0.1)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: active
                                  ? BillifyColors.primary
                                  : BillifyColors.divider),
                        ),
                        child: Text(
                          mode,
                          style: GoogleFonts.nunito(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: active
                                ? BillifyColors.primary
                                : BillifyColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Tax & Notes ────────────────────────────────
            _FormCard(
              title: 'Tax & Notes',
              icon: Icons.notes_rounded,
              children: [
                // Tax toggle
                Row(
                  children: [
                    Switch(
                      value:     _entry.isTaxable,
                      onChanged: (v) => setState(() => _entry.isTaxable = v),
                      activeColor: BillifyColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Include GST / Tax',
                        style: GoogleFonts.nunito(
                            fontSize: 14, fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.onSurface),
                      ),
                    ),
                    if (_entry.isTaxable)
                      SizedBox(
                        width: 90,
                        child: TextFormField(
                          initialValue: _entry.taxPercent.toString(),
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                          ],
                          onChanged: (v) => setState(() =>
                          _entry.taxPercent = double.tryParse(v) ?? 18),
                          decoration: InputDecoration(
                            labelText: 'Tax %',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                              BorderSide(color: Theme.of(context).dividerColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: BillifyColors.primary, width: 2),
                            ),
                          ),
                          style: GoogleFonts.nunito(
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),

                if (_entry.isTaxable) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: BillifyColors.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Tax Amount:',
                            style: GoogleFonts.nunito(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        Text(
                          '₹${(_entry.amount * _entry.taxPercent / 100).toStringAsFixed(2)}',
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: BillifyColors.primary),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                _field(
                  ctrl:  _noteCtrl,
                  label: 'Note (optional)',
                  icon:  Icons.sticky_note_2_rounded,
                  hint:  'Any extra detail…',
                  lines: 2,
                  onChanged: (_) {},
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Save button ────────────────────────────────
            _saving
                ? const Center(
                child: CircularProgressIndicator(
                    color: BillifyColors.primary))
                : ElevatedButton.icon(
              onPressed: _save,
              icon:  const Icon(Icons.save_rounded),
              label: Text(
                _isEdit ? 'Update Entry' : 'Save Entry',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isIncome
                    ? BillifyColors.paid
                    : BillifyColors.primary,
                minimumSize: const Size(double.infinity, 52),
              ),
            ),
          ],
        ),
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
        maxLines:   lines,
        onChanged:  onChanged,
        decoration: InputDecoration(
          labelText:          label,
          hintText:           hint,
          prefixIcon:         Icon(icon, color: BillifyColors.primary),
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
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
            color: BillifyColors.primary.withOpacity(0.06),
            blurRadius: 12, offset: const Offset(0, 4)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.07),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: BillifyColors.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: BillifyColors.primary)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    ),
  );
}

class _TypeBtn extends StatelessWidget {
  final String   label;
  final IconData icon;
  final bool     active;
  final Color    activeColor;
  final VoidCallback onTap;
  const _TypeBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color:        active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active
              ? [BoxShadow(
              color: activeColor.withOpacity(0.25),
              blurRadius: 8, offset: const Offset(0, 3))]
              : [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size:  18,
                color: active ? Colors.white : BillifyColors.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.poppins(
                  fontSize:   14,
                  fontWeight: FontWeight.w700,
                  color:      active ? Colors.white : BillifyColors.textSecondary,
                )),
          ],
        ),
      ),
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: GoogleFonts.poppins(
        fontSize: 12, fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}