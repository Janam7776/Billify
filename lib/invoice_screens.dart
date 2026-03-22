// ════════════════════════════════════════════════════════════
//  invoice_screens.dart — Billify
//  Full Invoice List, Create/Edit, Detail + PDF Generation
// ════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'main.dart' show BillifyColors, AppRoutes, BillifyDrawer;

// ════════════════════════════════════════════════════════════
//  DATA MODEL
// ════════════════════════════════════════════════════════════

class InvoiceItem {
  String description;
  int    quantity;
  double price;

  InvoiceItem({
    this.description = '',
    this.quantity    = 1,
    this.price       = 0.0,
  });

  double get total => quantity * price;

  Map<String, dynamic> toMap() => {
    'description': description,
    'quantity':    quantity,
    'price':       price,
  };

  factory InvoiceItem.fromMap(Map<String, dynamic> m) => InvoiceItem(
    description: m['description'] ?? '',
    quantity:    (m['quantity'] ?? 1) as int,
    price:       (m['price'] ?? 0.0) as double,
  );
}

class Invoice {
  String  id;
  String  invoiceNumber;
  String  clientName;
  String  clientEmail;
  String  clientPhone;
  String  clientAddress;
  String  shipToName;
  String  shipToAddress;
  String  shipToEmail;
  String  shipToPhone;
  String  poNumber;
  DateTime invoiceDate;
  DateTime dueDate;
  List<InvoiceItem> items;
  double  taxPercent;
  double  discountAmount;
  double  shippingAmount;
  double  amountPaid;
  String  status;   // draft / unpaid / paid / overdue
  String  paymentTerms;
  String  termsConditions;
  String  companyName;
  String  companyAddress;
  String  companyEmail;
  String  companyPhone;
  String  bankName;
  String  accountName;
  String  accountNumber;
  String  thankYouNote;

  Invoice({
    this.id              = '',
    this.invoiceNumber   = '',
    this.clientName      = '',
    this.clientEmail     = '',
    this.clientPhone     = '',
    this.clientAddress   = '',
    this.shipToName      = '',
    this.shipToAddress   = '',
    this.shipToEmail     = '',
    this.shipToPhone     = '',
    this.poNumber        = '',
    DateTime? invoiceDate,
    DateTime? dueDate,
    List<InvoiceItem>? items,
    this.taxPercent      = 0,
    this.discountAmount  = 0,
    this.shippingAmount  = 0,
    this.amountPaid      = 0,
    this.status          = 'draft',
    this.paymentTerms    = 'Please pay within 30 days.',
    this.termsConditions = 'Payment will be made via bank transfer.\nPlease ensure it is made within the due date.',
    this.companyName     = '',
    this.companyAddress  = '',
    this.companyEmail    = '',
    this.companyPhone    = '',
    this.bankName        = '',
    this.accountName     = '',
    this.accountNumber   = '',
    this.thankYouNote    = 'Thank you!',
  })  : invoiceDate = invoiceDate ?? DateTime.now(),
        dueDate     = dueDate     ?? DateTime.now().add(const Duration(days: 30)),
        items       = items       ?? [InvoiceItem()];

  double get subTotal      => items.fold(0, (s, i) => s + i.total);
  double get taxAmount     => subTotal * taxPercent / 100;
  double get totalAmount   => subTotal + taxAmount - discountAmount + shippingAmount;
  double get balanceDue    => totalAmount - amountPaid;

  Map<String, dynamic> toMap() => {
    'invoiceNumber':   invoiceNumber,
    'clientName':      clientName,
    'clientEmail':     clientEmail,
    'clientPhone':     clientPhone,
    'clientAddress':   clientAddress,
    'shipToName':      shipToName,
    'shipToAddress':   shipToAddress,
    'shipToEmail':     shipToEmail,
    'shipToPhone':     shipToPhone,
    'poNumber':        poNumber,
    'invoiceDate':     Timestamp.fromDate(invoiceDate),
    'dueDate':         Timestamp.fromDate(dueDate),
    'items':           items.map((i) => i.toMap()).toList(),
    'taxPercent':      taxPercent,
    'discountAmount':  discountAmount,
    'shippingAmount':  shippingAmount,
    'amountPaid':      amountPaid,
    'totalAmount':     totalAmount,
    'status':          status,
    'paymentTerms':    paymentTerms,
    'termsConditions': termsConditions,
    'companyName':     companyName,
    'companyAddress':  companyAddress,
    'companyEmail':    companyEmail,
    'companyPhone':    companyPhone,
    'bankName':        bankName,
    'accountName':     accountName,
    'accountNumber':   accountNumber,
    'thankYouNote':    thankYouNote,
    'createdAt':       FieldValue.serverTimestamp(),
  };

  factory Invoice.fromMap(String id, Map<String, dynamic> m) {
    final rawItems = (m['items'] as List? ?? []);
    return Invoice(
      id:              id,
      invoiceNumber:   m['invoiceNumber']   ?? '',
      clientName:      m['clientName']      ?? '',
      clientEmail:     m['clientEmail']     ?? '',
      clientPhone:     m['clientPhone']     ?? '',
      clientAddress:   m['clientAddress']   ?? '',
      shipToName:      m['shipToName']      ?? '',
      shipToAddress:   m['shipToAddress']   ?? '',
      shipToEmail:     m['shipToEmail']     ?? '',
      shipToPhone:     m['shipToPhone']     ?? '',
      poNumber:        m['poNumber']        ?? '',
      invoiceDate:     (m['invoiceDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      dueDate:         (m['dueDate']     as Timestamp?)?.toDate() ?? DateTime.now(),
      items:           rawItems.map((e) => InvoiceItem.fromMap(e as Map<String, dynamic>)).toList(),
      taxPercent:      (m['taxPercent']     ?? 0.0) as double,
      discountAmount:  (m['discountAmount'] ?? 0.0) as double,
      shippingAmount:  (m['shippingAmount'] ?? 0.0) as double,
      amountPaid:      (m['amountPaid']     ?? 0.0) as double,
      status:          m['status']          ?? 'draft',
      paymentTerms:    m['paymentTerms']    ?? 'Please pay within 30 days.',
      termsConditions: m['termsConditions'] ?? '',
      companyName:     m['companyName']     ?? '',
      companyAddress:  m['companyAddress']  ?? '',
      companyEmail:    m['companyEmail']    ?? '',
      companyPhone:    m['companyPhone']    ?? '',
      bankName:        m['bankName']        ?? '',
      accountName:     m['accountName']     ?? '',
      accountNumber:   m['accountNumber']   ?? '',
      thankYouNote:    m['thankYouNote']    ?? 'Thank you!',
    );
  }
}

// ════════════════════════════════════════════════════════════
//  INVOICE LIST SCREEN
// ════════════════════════════════════════════════════════════

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key});
  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  String _filterStatus = 'all';
  String _searchQuery  = '';
  final _searchCtrl = TextEditingController();

  Stream<QuerySnapshot> _stream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('invoices')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  List<Invoice> _applyFilter(List<QueryDocumentSnapshot> docs) {
    return docs.map((d) => Invoice.fromMap(d.id, d.data() as Map<String, dynamic>)).where((inv) {
      final matchStatus = _filterStatus == 'all' || inv.status == _filterStatus;
      final q = _searchQuery.toLowerCase();
      final matchSearch = q.isEmpty ||
          inv.clientName.toLowerCase().contains(q) ||
          inv.invoiceNumber.toLowerCase().contains(q);
      return matchStatus && matchSearch;
    }).toList();
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'paid':    return BillifyColors.paid;
      case 'unpaid':  return BillifyColors.unpaid;
      case 'overdue': return BillifyColors.overdue;
      default:        return BillifyColors.draft;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: BillifyColors.background,
      drawer: const BillifyDrawer(activeRoute: AppRoutes.invoices),
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => Get.toNamed(AppRoutes.invoiceCreate),
            tooltip: 'New Invoice',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Get.toNamed(AppRoutes.invoiceCreate),
        icon:  const Icon(Icons.receipt_long_rounded),
        label: Text('New Invoice', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          // ── Search bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText:    'Search by client or invoice no.',
                prefixIcon:  const Icon(Icons.search_rounded, color: BillifyColors.primary),
                suffixIcon:  _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),

          // ── Status Filter chips ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['all', 'draft', 'unpaid', 'paid', 'overdue'].map((s) {
                  final active = _filterStatus == s;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _filterStatus = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: active ? BillifyColors.primary : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: active
                              ? [BoxShadow(color: BillifyColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]
                              : [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)],
                        ),
                        child: Text(
                          s == 'all' ? 'All' : s[0].toUpperCase() + s.substring(1),
                          style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: active ? Colors.white : BillifyColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // ── Invoice list ──
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _stream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: BillifyColors.primary));
                }
                final invoices = _applyFilter(snap.data?.docs ?? []);

                if (invoices.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 72, color: BillifyColors.primary.withOpacity(0.2)),
                        const SizedBox(height: 16),
                        Text('No invoices found',
                            style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: BillifyColors.textPrimary)),
                        const SizedBox(height: 6),
                        Text('Tap "New Invoice" to get started',
                            style: GoogleFonts.nunito(color: BillifyColors.textSecondary)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: invoices.length,
                  itemBuilder: (_, i) {
                    final inv = invoices[i];
                    return GestureDetector(
                      onTap: () => Get.toNamed(AppRoutes.invoiceDetail, arguments: inv),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: BillifyColors.primary.withOpacity(0.06),
                              blurRadius: 8, offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Icon
                            Container(
                              width: 46, height: 46,
                              decoration: BoxDecoration(
                                color: BillifyColors.primary.withOpacity(0.09),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.receipt_long_rounded, color: BillifyColors.primary, size: 22),
                            ),
                            const SizedBox(width: 12),
                            // Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    inv.clientName.isEmpty ? 'Unknown Client' : inv.clientName,
                                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: BillifyColors.textPrimary),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${inv.invoiceNumber}  •  ${DateFormat('d MMM yyyy').format(inv.invoiceDate)}',
                                    style: GoogleFonts.nunito(fontSize: 12, color: BillifyColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Amount + badge
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  fmt.format(inv.totalAmount),
                                  style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: BillifyColors.textPrimary),
                                ),
                                const SizedBox(height: 4),
                                _StatusBadge(status: inv.status),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  INVOICE CREATE / EDIT SCREEN
// ════════════════════════════════════════════════════════════

class InvoiceCreateScreen extends StatefulWidget {
  const InvoiceCreateScreen({super.key});
  @override
  State<InvoiceCreateScreen> createState() => _InvoiceCreateScreenState();
}

class _InvoiceCreateScreenState extends State<InvoiceCreateScreen> {
  late Invoice _inv;
  bool _saving = false;
  int  _step   = 0; // 0=Company/Client, 1=Items, 2=Summary

  @override
  void initState() {
    super.initState();
    // Check if we're editing
    final arg = Get.arguments;
    if (arg is Invoice) {
      _inv = arg;
    } else {
      _inv = Invoice();
      _generateInvoiceNumber();
      _loadCompanyData();
    }
  }

  Future<void> _generateInvoiceNumber() async {
    final uid  = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance
        .collection('users').doc(uid).collection('invoices').get();
    final n = snap.docs.length + 1;
    setState(() => _inv.invoiceNumber = 'INV-${n.toString().padLeft(4, '0')}');
  }

  Future<void> _loadCompanyData() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final d   = doc.data() ?? {};
    setState(() {
      _inv.companyName    = d['businessName'] ?? d['fullName'] ?? '';
      _inv.companyAddress = d['address']      ?? '';
      _inv.companyEmail   = d['email']        ?? '';
      _inv.companyPhone   = d['phone']        ?? '';
      _inv.accountName    = d['accountName']  ?? '';
      _inv.bankName       = d['bankName']     ?? '';
      _inv.accountNumber  = d['accountNumber'] ?? '';
    });
  }

  Future<void> _save() async {
    if (_inv.clientName.trim().isEmpty) {
      Get.snackbar('Required', 'Please enter client name',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final col = FirebaseFirestore.instance.collection('users').doc(uid).collection('invoices');

      if (_inv.id.isEmpty) {
        final ref = await col.add(_inv.toMap());
        _inv.id   = ref.id;
      } else {
        await col.doc(_inv.id).update(_inv.toMap());
      }

      Get.snackbar('Saved', 'Invoice saved successfully',
          backgroundColor: BillifyColors.paid, colorText: Colors.white);
      Get.offNamed(AppRoutes.invoiceDetail, arguments: _inv);
    } catch (e) {
      Get.snackbar('Error', 'Could not save invoice. Please try again.',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillifyColors.background,
      appBar: AppBar(
        title: Text(_inv.id.isEmpty ? 'New Invoice' : 'Edit Invoice'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_rounded),
              onPressed: _save,
              tooltip: 'Save Invoice',
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Step indicator ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(
              children: [
                _StepTab(index: 0, label: 'Parties',   active: _step == 0, onTap: () => setState(() => _step = 0)),
                _StepTab(index: 1, label: 'Items',     active: _step == 1, onTap: () => setState(() => _step = 1)),
                _StepTab(index: 2, label: 'Summary',   active: _step == 2, onTap: () => setState(() => _step = 2)),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _step == 0
                  ? _PartiesStep(inv: _inv, onChanged: () => setState(() {}))
                  : _step == 1
                      ? _ItemsStep(inv: _inv, onChanged: () => setState(() {}))
                      : _SummaryStep(inv: _inv, onChanged: () => setState(() {})),
            ),
          ),

          // ── Bottom nav ──
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _step--),
                      icon:  const Icon(Icons.arrow_back_rounded),
                      label: const Text('Previous'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _step < 2
                      ? ElevatedButton.icon(
                          onPressed: () => setState(() => _step++),
                          icon:  const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Next'),
                          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
                        )
                      : ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon:  const Icon(Icons.save_rounded),
                          label: Text(_inv.id.isEmpty ? 'Save Invoice' : 'Update Invoice'),
                          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTab extends StatelessWidget {
  final int    index;
  final String label;
  final bool   active;
  final VoidCallback onTap;
  const _StepTab({required this.index, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? BillifyColors.primary : BillifyColors.background,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${index + 1}. $label',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : BillifyColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Step 0: Parties ──────────────────────────────────────────
class _PartiesStep extends StatefulWidget {
  final Invoice inv;
  final VoidCallback onChanged;
  const _PartiesStep({required this.inv, required this.onChanged});

  @override
  State<_PartiesStep> createState() => _PartiesStepState();
}

class _PartiesStepState extends State<_PartiesStep> {
  late final _invNumCtrl    = TextEditingController(text: widget.inv.invoiceNumber);
  late final _poCtrl        = TextEditingController(text: widget.inv.poNumber);
  late final _compNameCtrl  = TextEditingController(text: widget.inv.companyName);
  late final _compAddrCtrl  = TextEditingController(text: widget.inv.companyAddress);
  late final _compEmailCtrl = TextEditingController(text: widget.inv.companyEmail);
  late final _compPhoneCtrl = TextEditingController(text: widget.inv.companyPhone);
  late final _cliNameCtrl   = TextEditingController(text: widget.inv.clientName);
  late final _cliEmailCtrl  = TextEditingController(text: widget.inv.clientEmail);
  late final _cliPhoneCtrl  = TextEditingController(text: widget.inv.clientPhone);
  late final _cliAddrCtrl   = TextEditingController(text: widget.inv.clientAddress);
  late final _shipNameCtrl  = TextEditingController(text: widget.inv.shipToName);
  late final _shipAddrCtrl  = TextEditingController(text: widget.inv.shipToAddress);
  late final _shipEmailCtrl = TextEditingController(text: widget.inv.shipToEmail);
  late final _shipPhoneCtrl = TextEditingController(text: widget.inv.shipToPhone);
  late DateTime _invDate    = widget.inv.invoiceDate;
  late DateTime _dueDate    = widget.inv.dueDate;

  void _sync() {
    widget.inv.invoiceNumber = _invNumCtrl.text;
    widget.inv.poNumber      = _poCtrl.text;
    widget.inv.companyName   = _compNameCtrl.text;
    widget.inv.companyAddress= _compAddrCtrl.text;
    widget.inv.companyEmail  = _compEmailCtrl.text;
    widget.inv.companyPhone  = _compPhoneCtrl.text;
    widget.inv.clientName    = _cliNameCtrl.text;
    widget.inv.clientEmail   = _cliEmailCtrl.text;
    widget.inv.clientPhone   = _cliPhoneCtrl.text;
    widget.inv.clientAddress = _cliAddrCtrl.text;
    widget.inv.shipToName    = _shipNameCtrl.text;
    widget.inv.shipToAddress = _shipAddrCtrl.text;
    widget.inv.shipToEmail   = _shipEmailCtrl.text;
    widget.inv.shipToPhone   = _shipPhoneCtrl.text;
    widget.inv.invoiceDate   = _invDate;
    widget.inv.dueDate       = _dueDate;
    widget.onChanged();
  }

  Future<void> _pickDate(bool isDue) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isDue ? _dueDate : _invDate,
      firstDate:   DateTime(2020),
      lastDate:    DateTime(2035),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: BillifyColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isDue) { _dueDate = picked; } else { _invDate = picked; }
        _sync();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Invoice Details'),
        _row2(
          _field(_invNumCtrl, 'Invoice No.', Icons.tag_rounded, onChanged: (_) => _sync()),
          _field(_poCtrl,     'P.O. Number', Icons.numbers_rounded, onChanged: (_) => _sync()),
        ),
        const SizedBox(height: 12),
        _row2(
          _dateTile('Invoice Date', _invDate, false),
          _dateTile('Due Date',     _dueDate, true),
        ),

        const SizedBox(height: 20),
        _SectionTitle('Your Company'),
        _field(_compNameCtrl,  'Company Name',    Icons.business_rounded,           onChanged: (_) => _sync()),
        const SizedBox(height: 10),
        _field(_compAddrCtrl,  'Company Address', Icons.location_on_rounded,        onChanged: (_) => _sync(), lines: 2),
        const SizedBox(height: 10),
        _row2(
          _field(_compEmailCtrl, 'Email', Icons.email_rounded,  onChanged: (_) => _sync()),
          _field(_compPhoneCtrl, 'Phone', Icons.phone_rounded,  onChanged: (_) => _sync()),
        ),

        const SizedBox(height: 20),
        _SectionTitle('Bill To (Client)'),
        _field(_cliNameCtrl,  'Client Name',    Icons.person_rounded,       onChanged: (_) => _sync()),
        const SizedBox(height: 10),
        _field(_cliAddrCtrl,  'Client Address', Icons.location_on_rounded,  onChanged: (_) => _sync(), lines: 2),
        const SizedBox(height: 10),
        _row2(
          _field(_cliEmailCtrl, 'Email', Icons.email_rounded,  onChanged: (_) => _sync()),
          _field(_cliPhoneCtrl, 'Phone', Icons.phone_rounded,  onChanged: (_) => _sync()),
        ),

        const SizedBox(height: 20),
        _SectionTitle('Ship To (Optional)'),
        _field(_shipNameCtrl,  'Ship To Name',    Icons.local_shipping_rounded, onChanged: (_) => _sync()),
        const SizedBox(height: 10),
        _field(_shipAddrCtrl,  'Ship To Address', Icons.location_on_outlined,   onChanged: (_) => _sync(), lines: 2),
        const SizedBox(height: 10),
        _row2(
          _field(_shipEmailCtrl, 'Email', Icons.email_outlined,  onChanged: (_) => _sync()),
          _field(_shipPhoneCtrl, 'Phone', Icons.phone_outlined,  onChanged: (_) => _sync()),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _dateTile(String label, DateTime dt, bool isDue) {
    return GestureDetector(
      onTap: () => _pickDate(isDue),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color:  Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BillifyColors.divider, width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, color: BillifyColors.primary, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.nunito(fontSize: 11, color: BillifyColors.textSecondary)),
                Text(DateFormat('d MMM yyyy').format(dt),
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: BillifyColors.textPrimary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 1: Items ─────────────────────────────────────────────
class _ItemsStep extends StatefulWidget {
  final Invoice inv;
  final VoidCallback onChanged;
  const _ItemsStep({required this.inv, required this.onChanged});

  @override
  State<_ItemsStep> createState() => _ItemsStepState();
}

class _ItemsStepState extends State<_ItemsStep> {
  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Invoice Items'),
        ...widget.inv.items.asMap().entries.map((e) => _ItemRow(
          index: e.key,
          item:  e.value,
          onChanged: () { setState(() {}); widget.onChanged(); },
          onDelete: widget.inv.items.length > 1
              ? () { setState(() { widget.inv.items.removeAt(e.key); widget.onChanged(); }); }
              : null,
        )),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            setState(() { widget.inv.items.add(InvoiceItem()); widget.onChanged(); });
          },
          icon:  const Icon(Icons.add_rounded),
          label: const Text('Add Item'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
        ),

        const SizedBox(height: 24),
        _SectionTitle('Payment Terms'),
        _multilineField(
          widget.inv.paymentTerms,
          'Payment Terms',
          Icons.info_outline_rounded,
          (v) { widget.inv.paymentTerms = v; widget.onChanged(); },
        ),
        const SizedBox(height: 12),
        _multilineField(
          widget.inv.termsConditions,
          'Terms & Conditions',
          Icons.description_outlined,
          (v) { widget.inv.termsConditions = v; widget.onChanged(); },
          lines: 3,
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _multilineField(String init, String label, IconData icon, ValueChanged<String> onChanged, {int lines = 2}) {
    final ctrl = TextEditingController(text: init);
    return TextField(
      controller:  ctrl,
      maxLines:    lines,
      onChanged:   onChanged,
      decoration:  InputDecoration(
        labelText:  label,
        prefixIcon: Icon(icon, color: BillifyColors.primary),
        alignLabelWithHint: true,
      ),
    );
  }
}

class _ItemRow extends StatefulWidget {
  final int       index;
  final InvoiceItem item;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;
  const _ItemRow({required this.index, required this.item, required this.onChanged, this.onDelete});

  @override
  State<_ItemRow> createState() => _ItemRowState();
}

class _ItemRowState extends State<_ItemRow> {
  late final _descCtrl = TextEditingController(text: widget.item.description);
  late final _qtyCtrl  = TextEditingController(text: widget.item.quantity.toString());
  late final _priceCtrl= TextEditingController(text: widget.item.price == 0 ? '' : widget.item.price.toString());

  @override
  Widget build(BuildContext context) {
    final total = widget.item.total;
    final fmt   = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BillifyColors.divider),
        boxShadow: [BoxShadow(color: BillifyColors.primary.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(color: BillifyColors.primary, borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text('${widget.index + 1}',
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _descCtrl,
                  onChanged: (v) { widget.item.description = v; widget.onChanged(); },
                  decoration: InputDecoration(
                    hintText:       'Item description',
                    hintStyle:      GoogleFonts.nunito(color: BillifyColors.textSecondary),
                    border:         InputBorder.none,
                    enabledBorder:  InputBorder.none,
                    focusedBorder:  InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w600, color: BillifyColors.textPrimary),
                ),
              ),
              if (widget.onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: BillifyColors.unpaid, size: 20),
                  onPressed: widget.onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Qty
              Expanded(
                child: _NumField(
                  ctrl: _qtyCtrl,
                  label: 'Qty',
                  onChanged: (v) {
                    widget.item.quantity = int.tryParse(v) ?? 1;
                    widget.onChanged();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),
              // Price
              Expanded(
                flex: 2,
                child: _NumField(
                  ctrl: _priceCtrl,
                  label: 'Price (₹)',
                  decimal: true,
                  onChanged: (v) {
                    widget.item.price = double.tryParse(v) ?? 0;
                    widget.onChanged();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),
              // Total
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Total', style: GoogleFonts.nunito(fontSize: 11, color: BillifyColors.textSecondary)),
                  Text(fmt.format(total),
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: BillifyColors.primary)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final bool   decimal;
  final ValueChanged<String> onChanged;
  const _NumField({required this.ctrl, required this.label, this.decimal = false, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:  ctrl,
      onChanged:   onChanged,
      keyboardType: decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(decimal ? RegExp(r'[\d.]') : RegExp(r'\d')),
      ],
      decoration: InputDecoration(
        labelText:      label,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense:        true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: BillifyColors.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: BillifyColors.divider, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: BillifyColors.primary, width: 2)),
        filled:    true,
        fillColor: BillifyColors.background,
      ),
      style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w600, color: BillifyColors.textPrimary),
    );
  }
}

// ── Step 2: Summary ───────────────────────────────────────────
class _SummaryStep extends StatefulWidget {
  final Invoice inv;
  final VoidCallback onChanged;
  const _SummaryStep({required this.inv, required this.onChanged});

  @override
  State<_SummaryStep> createState() => _SummaryStepState();
}

class _SummaryStepState extends State<_SummaryStep> {
  late final _taxCtrl      = TextEditingController(text: widget.inv.taxPercent == 0    ? '' : widget.inv.taxPercent.toString());
  late final _discCtrl     = TextEditingController(text: widget.inv.discountAmount == 0 ? '' : widget.inv.discountAmount.toString());
  late final _shipCtrl     = TextEditingController(text: widget.inv.shippingAmount == 0 ? '' : widget.inv.shippingAmount.toString());
  late final _paidCtrl     = TextEditingController(text: widget.inv.amountPaid == 0     ? '' : widget.inv.amountPaid.toString());
  late final _bankCtrl     = TextEditingController(text: widget.inv.bankName);
  late final _accNameCtrl  = TextEditingController(text: widget.inv.accountName);
  late final _accNumCtrl   = TextEditingController(text: widget.inv.accountNumber);
  late final _tyCtrl       = TextEditingController(text: widget.inv.thankYouNote);
  String _status           = '';

  @override
  void initState() {
    super.initState();
    _status = widget.inv.status;
  }

  void _sync() { widget.onChanged(); setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final inv = widget.inv;
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Totals & Tax'),
        _row2(
          _NumField(ctrl: _taxCtrl,  label: 'Tax %',        onChanged: (v) { inv.taxPercent     = double.tryParse(v) ?? 0; _sync(); }, decimal: true),
          _NumField(ctrl: _discCtrl, label: 'Discount (₹)', onChanged: (v) { inv.discountAmount = double.tryParse(v) ?? 0; _sync(); }, decimal: true),
        ),
        const SizedBox(height: 10),
        _row2(
          _NumField(ctrl: _shipCtrl, label: 'Shipping (₹)', onChanged: (v) { inv.shippingAmount = double.tryParse(v) ?? 0; _sync(); }, decimal: true),
          _NumField(ctrl: _paidCtrl, label: 'Amount Paid (₹)', onChanged: (v) { inv.amountPaid  = double.tryParse(v) ?? 0; _sync(); }, decimal: true),
        ),
        const SizedBox(height: 20),

        // Totals preview
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: BillifyColors.divider),
          ),
          child: Column(
            children: [
              _TotalRow('Sub Total',    fmt.format(inv.subTotal),    bold: false),
              _TotalRow('Tax (${inv.taxPercent}%)', fmt.format(inv.taxAmount), bold: false),
              _TotalRow('Discount',     '- ${fmt.format(inv.discountAmount)}', bold: false),
              _TotalRow('Shipping',     fmt.format(inv.shippingAmount), bold: false),
              const Divider(),
              _TotalRow('Total Amount', fmt.format(inv.totalAmount), bold: true),
              _TotalRow('Amount Paid',  fmt.format(inv.amountPaid),  bold: false),
              const Divider(),
              _TotalRow('Balance Due',  fmt.format(inv.balanceDue),  bold: true, highlight: true),
            ],
          ),
        ),

        const SizedBox(height: 20),
        _SectionTitle('Status'),
        Wrap(
          spacing: 8,
          children: ['draft', 'unpaid', 'paid', 'overdue'].map((s) {
            final active = _status == s;
            return GestureDetector(
              onTap: () {
                setState(() { _status = s; inv.status = s; });
                widget.onChanged();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _statusColor(s) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: active ? _statusColor(s) : BillifyColors.divider),
                ),
                child: Text(
                  s[0].toUpperCase() + s.substring(1),
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : BillifyColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 20),
        _SectionTitle('Payment Information'),
        _field2(_bankCtrl,    'Bank Name',    Icons.account_balance_rounded, (v) { inv.bankName = v; }),
        const SizedBox(height: 10),
        _field2(_accNameCtrl, 'Account Name', Icons.person_rounded,          (v) { inv.accountName = v; }),
        const SizedBox(height: 10),
        _field2(_accNumCtrl,  'Account No.',  Icons.credit_card_rounded,     (v) { inv.accountNumber = v; }),
        const SizedBox(height: 10),
        _field2(_tyCtrl,      'Thank You Note', Icons.favorite_rounded,      (v) { inv.thankYouNote = v; }),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _field2(TextEditingController ctrl, String label, IconData icon, ValueChanged<String> onChanged) {
    return TextField(
      controller: ctrl,
      onChanged:  onChanged,
      decoration: InputDecoration(
        labelText:  label,
        prefixIcon: Icon(icon, color: BillifyColors.primary),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'paid':    return BillifyColors.paid;
      case 'unpaid':  return BillifyColors.unpaid;
      case 'overdue': return BillifyColors.overdue;
      default:        return BillifyColors.draft;
    }
  }
}

class _TotalRow extends StatelessWidget {
  final String label, value;
  final bool   bold, highlight;
  const _TotalRow(this.label, this.value, {this.bold = false, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: GoogleFonts.nunito(
            fontSize:   13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color:      bold ? BillifyColors.textPrimary : BillifyColors.textSecondary,
          ))),
          Text(value, style: GoogleFonts.poppins(
            fontSize:   13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color:      highlight ? BillifyColors.unpaid : (bold ? BillifyColors.textPrimary : BillifyColors.textSecondary),
          )),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  INVOICE DETAIL SCREEN  +  INVOICE WIDGET (for screenshot)
// ════════════════════════════════════════════════════════════

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key});
  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  late Invoice _inv;
  bool _generating = false;
  final GlobalKey _repaintKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final arg = Get.arguments;
    if (arg is Invoice) {
      _inv = arg;
    } else {
      _inv = Invoice();
    }
  }

  Future<void> _deleteInvoice() async {
    final confirm = await Get.dialog<bool>(AlertDialog(
      title: const Text('Delete Invoice'),
      content: const Text('Are you sure you want to delete this invoice? This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: BillifyColors.unpaid),
          onPressed: () => Get.back(result: true),
          child: const Text('Delete'),
        ),
      ],
    ));

    if (confirm != true) return;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users').doc(uid).collection('invoices').doc(_inv.id).delete();
      Get.offNamed(AppRoutes.invoices);
      Get.snackbar('Deleted', 'Invoice deleted successfully',
          backgroundColor: BillifyColors.paid, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Error', 'Could not delete invoice',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    }
  }

  Future<void> _generateAndShareImage() async {
    setState(() => _generating = true);
    try {
      // Wait for a frame so the widget is rendered
      await Future.delayed(const Duration(milliseconds: 100));

      final boundary = _repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Widget not rendered');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Could not convert to image');

      final bytes = byteData.buffer.asUint8List();
      final dir   = await getTemporaryDirectory();
      final file  = File('${dir.path}/invoice_${_inv.invoiceNumber.replaceAll('-', '_')}.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Invoice ${_inv.invoiceNumber} from ${_inv.companyName}',
        text:    'Please find the invoice attached.',
      );
    } catch (e) {
      Get.snackbar('Error', 'Could not generate invoice image: ${e.toString()}',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillifyColors.background,
      appBar: AppBar(
        title: Text(_inv.invoiceNumber.isEmpty ? 'Invoice Detail' : _inv.invoiceNumber),
        actions: [
          // Edit
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => Get.toNamed(AppRoutes.invoiceEdit, arguments: _inv),
            tooltip: 'Edit',
          ),
          // Delete
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: _deleteInvoice,
            tooltip: 'Delete',
          ),
          // More
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'share') _generateAndShareImage();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'share', child: Row(children: [
                Icon(Icons.share_rounded, color: BillifyColors.primary, size: 20),
                SizedBox(width: 10),
                Text('Share Image'),
              ])),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // ── Status Banner ──
                _StatusBanner(status: _inv.status),
                const SizedBox(height: 12),

                // ── Invoice widget — wrapped with RepaintBoundary for screenshot ──
                RepaintBoundary(
                  key: _repaintKey,
                  child: _InvoiceTemplate(inv: _inv),
                ),

                const SizedBox(height: 20),

                // ── Action buttons ──
                _generating
                    ? const Center(child: CircularProgressIndicator(color: BillifyColors.primary))
                    : Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _generateAndShareImage,
                            icon:  const Icon(Icons.image_rounded),
                            label: const Text('Save / Share as Image'),
                            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            onPressed: () => Get.toNamed(AppRoutes.invoiceEdit, arguments: _inv),
                            icon:  const Icon(Icons.edit_rounded),
                            label: const Text('Edit Invoice'),
                            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                          ),
                        ],
                      ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String status;
  const _StatusBanner({required this.status});

  Color get _bg {
    switch (status) {
      case 'paid':    return const Color(0xFFE8F5E9);
      case 'unpaid':  return const Color(0xFFFFEBEE);
      case 'overdue': return const Color(0xFFFFF3E0);
      default:        return const Color(0xFFF5F5F5);
    }
  }

  Color get _fg {
    switch (status) {
      case 'paid':    return BillifyColors.paid;
      case 'unpaid':  return BillifyColors.unpaid;
      case 'overdue': return BillifyColors.overdue;
      default:        return BillifyColors.draft;
    }
  }

  IconData get _icon {
    switch (status) {
      case 'paid':    return Icons.check_circle_rounded;
      case 'unpaid':  return Icons.schedule_rounded;
      case 'overdue': return Icons.warning_rounded;
      default:        return Icons.edit_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(_icon, color: _fg, size: 20),
          const SizedBox(width: 8),
          Text(
            'Status: ${status[0].toUpperCase()}${status.substring(1)}',
            style: GoogleFonts.poppins(color: _fg, fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  INVOICE TEMPLATE  (exact match to the design image)
// ════════════════════════════════════════════════════════════

class _InvoiceTemplate extends StatelessWidget {
  final Invoice inv;
  const _InvoiceTemplate({required this.inv});

  @override
  Widget build(BuildContext context) {
    final fmt     = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
    final dateFmt = DateFormat('d/MM/yyyy');

    return Container(
      width:  double.infinity,
      color:  Colors.white,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── TOP ROW: Logo + Invoice Number ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo placeholder
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  shape:       BoxShape.circle,
                  border: Border.all(color: const Color(0xFFCCCCCC), width: 1.5, style: BorderStyle.solid),
                ),
                child: Center(child: Text('LOGO',
                    style: GoogleFonts.poppins(fontSize: 11, color: const Color(0xFFAAAAAA), fontWeight: FontWeight.w600))),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('INVOICE NO. #${inv.invoiceNumber}',
                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black)),
                  const SizedBox(height: 4),
                  Text('Date: ${dateFmt.format(inv.invoiceDate)}',
                      style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
                  Text('Due Date: ${dateFmt.format(inv.dueDate)}',
                      style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
                  Text('P.O. Number: ${inv.poNumber}',
                      style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Company name ──
          Text(
            inv.companyName.isEmpty ? 'Your Company Name' : inv.companyName,
            style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black),
          ),
          const SizedBox(height: 4),
          if (inv.companyAddress.isNotEmpty)
            Text(inv.companyAddress, style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
          if (inv.companyEmail.isNotEmpty)
            Text(inv.companyEmail,   style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
          if (inv.companyPhone.isNotEmpty)
            Text(inv.companyPhone,   style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),

          const SizedBox(height: 18),
          const Divider(color: Color(0xFFDDDDDD)),
          const SizedBox(height: 12),

          // ── Bill To + Ship To ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('INVOICE TO:', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black)),
                  const SizedBox(height: 4),
                  Text(inv.clientName.isEmpty    ? 'Client Name'    : inv.clientName,    style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
                  Text(inv.clientAddress.isEmpty ? 'Client Address' : inv.clientAddress, style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
                  Text(inv.clientEmail.isEmpty   ? ''               : inv.clientEmail,   style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
                  Text(inv.clientPhone.isEmpty   ? ''               : inv.clientPhone,   style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
                ],
              )),
              const SizedBox(width: 16),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SHIP TO:', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black)),
                  const SizedBox(height: 4),
                  Text(inv.shipToName.isEmpty    ? 'Client/Company Name' : inv.shipToName,    style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
                  Text(inv.shipToAddress.isEmpty ? 'Client Address'      : inv.shipToAddress, style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
                  Text(inv.shipToEmail.isEmpty   ? 'Client/Company Email': inv.shipToEmail,   style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
                  Text(inv.shipToPhone.isEmpty   ? 'Phone No.'           : inv.shipToPhone,   style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87)),
                ],
              )),
            ],
          ),

          const SizedBox(height: 16),

          // ── Payment Terms ──
          Center(
            child: RichText(
              text: TextSpan(
                text: 'Payment Terms: ',
                style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black),
                children: [
                  TextSpan(
                    text: inv.paymentTerms,
                    style: GoogleFonts.nunito(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.black87, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Items Table ──
          Table(
            border: TableBorder(
              top:    BorderSide(color: Colors.black, width: 1.5),
              bottom: BorderSide(color: Colors.black, width: 1.5),
            ),
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1.3),
              3: FlexColumnWidth(1.3),
            },
            children: [
              // Header
              TableRow(
                decoration: const BoxDecoration(color: Colors.black),
                children: ['Description', 'Quantity', 'Price', 'Total'].map((h) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Text(h, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                )).toList(),
              ),
              // Items
              ...inv.items.asMap().entries.map((e) => TableRow(
                decoration: BoxDecoration(
                  color: e.key.isEven ? Colors.white : const Color(0xFFF9F9F9),
                  border: const Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
                ),
                children: [
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      child: Text(e.value.description.isEmpty ? 'Item ${e.key + 1}' : e.value.description,
                          style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      child: Text('${e.value.quantity}',
                          style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      child: Text(fmt.format(e.value.price),
                          style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87))),
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                      child: Text(fmt.format(e.value.total),
                          style: GoogleFonts.nunito(fontSize: 11, color: Colors.black87))),
                ],
              )),
            ],
          ),
          const SizedBox(height: 12),

          // ── Totals (right aligned) ──
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 220,
              child: Column(
                children: [
                  _InvTotalRow('Sub Total:',   fmt.format(inv.subTotal)),
                  _InvTotalRow('Tax %:',       fmt.format(inv.taxAmount)),
                  _InvTotalRow('Discount:',    fmt.format(inv.discountAmount)),
                  _InvTotalRow('Shipping:',    fmt.format(inv.shippingAmount)),
                  _InvTotalRow('Total Amount:',fmt.format(inv.totalAmount),    bold: true),
                  _InvTotalRow('Amount Paid:', fmt.format(inv.amountPaid)),
                  const SizedBox(height: 4),
                  // Balance Due box
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    color: Colors.black,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Balance Due', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                        Text(fmt.format(inv.balanceDue), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),
          const Divider(color: Color(0xFFCCCCCC)),
          const SizedBox(height: 12),

          // ── Terms & Conditions + Payment Info ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Terms & Conditions:', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black)),
                    const SizedBox(height: 4),
                    Text(
                      inv.termsConditions.isEmpty ? 'Payment will be made via bank transfer.\nPlease ensure it is made within the due date.' : inv.termsConditions,
                      style: GoogleFonts.nunito(fontSize: 10, color: Colors.black87, height: 1.6),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      inv.thankYouNote.isEmpty ? 'Thank you!' : inv.thankYouNote,
                      style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Payment Information', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black)),
                  const SizedBox(height: 4),
                  Text(inv.bankName.isEmpty      ? 'Bank Name'      : inv.bankName,      style: GoogleFonts.nunito(fontSize: 10, color: Colors.black87)),
                  Text(inv.accountName.isEmpty   ? 'Account Name'   : 'Account Name: ${inv.accountName}',   style: GoogleFonts.nunito(fontSize: 10, color: Colors.black87)),
                  Text(inv.accountNumber.isEmpty ? 'Account No.'    : 'Account No.: ${inv.accountNumber}',  style: GoogleFonts.nunito(fontSize: 10, color: Colors.black87)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _InvTotalRow extends StatelessWidget {
  final String label, value;
  final bool   bold;
  const _InvTotalRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.poppins(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          color: Colors.black,
        )),
        Text(value, style: GoogleFonts.nunito(
          fontSize: 11,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          color: Colors.black87,
        )),
      ],
    ),
  );
}

// ════════════════════════════════════════════════════════════
//  INVOICE EDIT SCREEN  (wraps create with pre-filled data)
// ════════════════════════════════════════════════════════════

class InvoiceEditScreen extends StatelessWidget {
  const InvoiceEditScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Re-use InvoiceCreateScreen — it checks Get.arguments
    return const InvoiceCreateScreen();
  }
}

// ════════════════════════════════════════════════════════════
//  SHARED HELPERS
// ════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: BillifyColors.primary)),
  );
}

Widget _row2(Widget a, Widget b) => Row(
  children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)],
);

Widget _field(
  TextEditingController ctrl,
  String label,
  IconData icon, {
  ValueChanged<String>? onChanged,
  int lines = 1,
}) => TextField(
  controller: ctrl,
  onChanged:  onChanged,
  maxLines:   lines,
  decoration: InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon, color: BillifyColors.primary),
    alignLabelWithHint: lines > 1,
  ),
);

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color get _fg {
    switch (status) {
      case 'paid':    return BillifyColors.paid;
      case 'unpaid':  return BillifyColors.unpaid;
      case 'overdue': return BillifyColors.overdue;
      default:        return BillifyColors.draft;
    }
  }

  Color get _bg {
    switch (status) {
      case 'paid':    return const Color(0xFFE8F5E9);
      case 'unpaid':  return const Color(0xFFFFEBEE);
      case 'overdue': return const Color(0xFFFFF3E0);
      default:        return const Color(0xFFF5F5F5);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(20)),
    child: Text(
      status[0].toUpperCase() + status.substring(1),
      style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: _fg),
    ),
  );
}
