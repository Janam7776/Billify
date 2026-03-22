// ════════════════════════════════════════════════════════════
//  invoice_screens.dart — Billify (Content Creation Edition)
//  Invoice List, Create/Edit, Detail + TRUE PDF Generation
// ════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'main.dart' show BillifyColors, AppRoutes, BillifyDrawer, AppSettings, BillifyC,
BillifyDialog, BillifyImageSourceSheet;
import 'dashboard_screen.dart' show invoiceStatusColor, invoiceStatusBg, showStatusPicker;

// ════════════════════════════════════════════════════════════
//  HELPERS
// ════════════════════════════════════════════════════════════

String _randomId(String prefix) {
  final rng = Random();
  final n   = 100000 + rng.nextInt(900000);
  return '$prefix-$n';
}

/// Generate an invoice number using the settings prefix
String _invoiceId()  => _randomId(AppSettings.invoicePrefix);

/// Generate an order ID using the settings prefix
String _orderId()    => _randomId(AppSettings.orderPrefix);

// ════════════════════════════════════════════════════════════
//  DATA MODEL
// ════════════════════════════════════════════════════════════

/// A single line-item on a content creation invoice.
class ContentItem {
  String  title;
  bool    hasQty;
  int     qty;
  double  grossAmount;
  bool    hasDiscount;
  double  discount;        // flat ₹ discount
  bool    hasTax;
  double  taxPercent;      // e.g. 18 for 18 %
  bool    hasIgst;
  double  igstPercent;     // e.g. 18 for 18 %

  ContentItem({
    this.title       = '',
    this.hasQty      = false,
    this.qty         = 1,
    this.grossAmount = 0,
    this.hasDiscount = false,
    this.discount    = 0,
    this.hasTax      = false,
    double? taxPercent,
    this.hasIgst     = false,
    double? igstPercent,
  }) : taxPercent  = taxPercent  ?? AppSettings.defaultGst,
        igstPercent = igstPercent ?? AppSettings.defaultGst;

  /// Net = grossAmount − discount
  double get net => (grossAmount - discount).clamp(0, double.infinity);

  /// Tax amount on the net
  double get taxAmount => hasTax ? net * taxPercent / 100 : 0;

  /// IGST amount on the net
  double get igstAmount => hasIgst ? net * igstPercent / 100 : 0;

  /// Final line total
  double get lineTotal => net * (hasQty ? qty : 1) + taxAmount + igstAmount;

  Map<String, dynamic> toMap() => {
    'title':       title,
    'hasQty':      hasQty,
    'qty':         qty,
    'grossAmount': grossAmount,
    'hasDiscount': hasDiscount,
    'discount':    discount,
    'hasTax':      hasTax,
    'taxPercent':  taxPercent,
    'hasIgst':     hasIgst,
    'igstPercent': igstPercent,
  };

  factory ContentItem.fromMap(Map<String, dynamic> m) => ContentItem(
    title:       m['title']       ?? '',
    hasQty:      m['hasQty']      ?? false,
    qty:         (m['qty']        as num? ?? 1).toInt(),
    grossAmount: (m['grossAmount'] as num? ?? 0.0).toDouble(),
    hasDiscount: m['hasDiscount'] ?? false,
    discount:    (m['discount']   as num? ?? 0.0).toDouble(),
    hasTax:      m['hasTax']      ?? false,
    taxPercent:  ((m['taxPercent'] ?? AppSettings.defaultGst) as num).toDouble(),
    hasIgst:     m['hasIgst']     ?? false,
    igstPercent: ((m['igstPercent'] ?? AppSettings.defaultGst) as num).toDouble(),
  );
}

class Invoice {
  String   id;
  String   invoiceNumber;   // random, e.g. INV-839201
  String   orderId;         // random, e.g. ORD-294710
  DateTime orderDate;
  String   pan;             // optional
  String   gstNumber;       // optional

  // Bill To
  String   clientName;
  String   clientPhone;
  String   clientAddress;
  String   shootAddress;    // location of the shoot

  List<ContentItem> items;

  String   status;          // draft / unpaid / paid / overdue
  String   termsConditions;
  String   thankYouNote;

  // Payment
  String   companyName;
  String   companyAddress;
  String   companyPhone;
  String   companyEmail;
  String   bankName;
  String   accountName;
  String   accountNumber;
  String   ifscCode;
  String   logoPath;        // local file path (legacy)
  String   logoBase64;      // base64 from SharedPreferences (preferred)

  Invoice({
    this.id              = '',
    String? invoiceNumber,
    String? orderId,
    DateTime? orderDate,
    this.pan             = '',
    this.gstNumber       = '',
    this.clientName      = '',
    this.clientPhone     = '',
    this.clientAddress   = '',
    this.shootAddress    = '',
    List<ContentItem>? items,
    this.status          = 'draft',
    this.termsConditions = 'Payment due within 7 days of invoice date.\nAll creative assets remain property of the creator until full payment.',
    this.thankYouNote    = 'Thank you for your business!',
    this.companyName     = '',
    this.companyAddress  = '',
    this.companyPhone    = '',
    this.companyEmail    = '',
    this.bankName        = '',
    this.accountName     = '',
    this.accountNumber   = '',
    this.ifscCode        = '',
    this.logoPath        = '',
    this.logoBase64      = '',
  })  : invoiceNumber = invoiceNumber ?? _invoiceId(),
        orderId       = orderId       ?? _orderId(),
        orderDate     = orderDate     ?? DateTime.now(),
        items         = items         ?? [ContentItem()];

  double get subTotal    => items.fold(0, (s, i) => s + i.net * (i.hasQty ? i.qty : 1));
  double get totalTax    => items.fold(0, (s, i) => s + i.taxAmount);
  double get totalIgst   => items.fold(0, (s, i) => s + i.igstAmount);
  double get totalAmount => subTotal + totalTax + totalIgst;

  Map<String, dynamic> toMap() => {
    'invoiceNumber':   invoiceNumber,
    'orderId':         orderId,
    'orderDate':       Timestamp.fromDate(orderDate),
    'pan':             pan,
    'gstNumber':       gstNumber,
    'clientName':      clientName,
    'clientPhone':     clientPhone,
    'clientAddress':   clientAddress,
    'shootAddress':    shootAddress,
    'items':           items.map((i) => i.toMap()).toList(),
    'status':          status,
    'termsConditions': termsConditions,
    'thankYouNote':    thankYouNote,
    'companyName':     companyName,
    'companyAddress':  companyAddress,
    'companyPhone':    companyPhone,
    'companyEmail':    companyEmail,
    'bankName':        bankName,
    'accountName':     accountName,
    'accountNumber':   accountNumber,
    'ifscCode':        ifscCode,
    'logoPath':        logoPath,
    'logoBase64':      logoBase64,
    'totalAmount':     totalAmount,
    'createdAt':       FieldValue.serverTimestamp(),
  };

  factory Invoice.fromMap(String id, Map<String, dynamic> m) {
    final rawItems = (m['items'] as List? ?? []);
    return Invoice(
      id:              id,
      invoiceNumber:   m['invoiceNumber']   ?? _invoiceId(),
      orderId:         m['orderId']         ?? _orderId(),
      orderDate:       (m['orderDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      pan:             m['pan']             ?? '',
      gstNumber:       m['gstNumber']       ?? '',
      clientName:      m['clientName']      ?? '',
      clientPhone:     m['clientPhone']     ?? '',
      clientAddress:   m['clientAddress']   ?? '',
      shootAddress:    m['shootAddress']    ?? '',
      items:           rawItems.map((e) => ContentItem.fromMap(e as Map<String, dynamic>)).toList(),
      status:          m['status']          ?? 'draft',
      termsConditions: m['termsConditions'] ?? '',
      thankYouNote:    m['thankYouNote']    ?? 'Thank you!',
      companyName:     m['companyName']     ?? '',
      companyAddress:  m['companyAddress']  ?? '',
      companyPhone:    m['companyPhone']    ?? '',
      companyEmail:    m['companyEmail']    ?? '',
      bankName:        m['bankName']        ?? '',
      accountName:     m['accountName']     ?? '',
      accountNumber:   m['accountNumber']   ?? '',
      ifscCode:        m['ifscCode']        ?? '',
      logoPath:        m['logoPath']        ?? '',
      logoBase64:      m['logoBase64']      ?? '',
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
  final _searchCtrl    = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Accept a pre-set filter from dashboard navigation arguments
    final arg = Get.arguments;
    if (arg is Map && arg.containsKey('filter')) {
      _filterStatus = arg['filter'] as String;
    }
  }

  Stream<QuerySnapshot> _stream() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users').doc(uid).collection('invoices')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  List<Invoice> _applyFilter(List<QueryDocumentSnapshot> docs) {
    return docs.map((d) => Invoice.fromMap(d.id, d.data() as Map<String, dynamic>)).where((inv) {
      // 'paid_only' = paid invoices (revenue / completed)
      // 'pending_only' = unpaid + overdue
      bool matchStatus;
      if (_filterStatus == 'all') {
        matchStatus = true;
      } else if (_filterStatus == 'paid_only') {
        matchStatus = inv.status == 'paid';
      } else if (_filterStatus == 'pending_only') {
        matchStatus = inv.status == 'unpaid' || inv.status == 'overdue';
      } else {
        matchStatus = inv.status == _filterStatus;
      }
      final q = _searchQuery.toLowerCase();
      final matchSearch = q.isEmpty ||
          inv.clientName.toLowerCase().contains(q) ||
          inv.invoiceNumber.toLowerCase().contains(q) ||
          inv.orderId.toLowerCase().contains(q);
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
    final fmt = AppSettings.currencyFmt();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: const BillifyDrawer(activeRoute: AppRoutes.invoices),
      appBar: AppBar(
        title: Text(_filterStatus == 'paid_only'
            ? 'Paid Invoices'
            : _filterStatus == 'pending_only'
            ? 'Pending Invoices'
            : 'Invoices'),
        leading: _filterStatus != 'all'
            ? IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            setState(() => _filterStatus = 'all');
            Get.back();
          },
        )
            : null,
        actions: [
          if (_filterStatus != 'all')
            TextButton(
              onPressed: () => setState(() => _filterStatus = 'all'),
              child: Text('Show All',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.w600,
                      fontSize: 13)),
            )
          else
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText:   'Search by client, invoice or order no.',
                prefixIcon: const Icon(Icons.search_rounded, color: BillifyColors.primary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear_rounded),
                  onPressed: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                )
                    : null,
              ),
            ),
          ),

          // Status chips
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
                          color: active ? BillifyColors.primary : Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: active
                              ? [BoxShadow(color: BillifyColors.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]
                              : [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 4)],
                        ),
                        child: Text(
                          s == 'all' ? 'All' : s[0].toUpperCase() + s.substring(1),
                          style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700, fontSize: 13,
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
                        Icon(Icons.video_camera_front_outlined, size: 72, color: BillifyColors.primary.withOpacity(0.2)),
                        SizedBox(height: 16),
                        Text('No invoices yet', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                        SizedBox(height: 6),
                        Text('Tap "New Invoice" to get started', style: GoogleFonts.nunito(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                        padding: EdgeInsets.all(AppSettings.compactCards ? 10 : 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppSettings.compactCards ? 12 : 16),
                          boxShadow: [BoxShadow(color: BillifyColors.primary.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46, height: 46,
                              decoration: BoxDecoration(
                                color: BillifyColors.primary.withOpacity(0.09),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.video_camera_front_rounded, color: BillifyColors.primary, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    inv.clientName.isEmpty ? 'Unknown Client' : inv.clientName,
                                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text('${inv.invoiceNumber}  •  ${inv.orderId}',
                                      style: GoogleFonts.nunito(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                  Text(AppSettings.formatDate(inv.orderDate),
                                      style: GoogleFonts.nunito(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (AppSettings.showAmountOnList)
                                  Text(fmt.format(inv.totalAmount),
                                      style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w700, color: BillifyColors.primary)),
                                if (AppSettings.showAmountOnList)
                                  const SizedBox(height: 4),
                                // Tappable status badge — opens status picker
                                GestureDetector(
                                  onTap: () => showStatusPicker(context, inv.id, inv.status),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: invoiceStatusBg(inv.status),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: invoiceStatusColor(inv.status).withOpacity(0.4)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          inv.status[0].toUpperCase() + inv.status.substring(1),
                                          style: GoogleFonts.nunito(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: invoiceStatusColor(inv.status)),
                                        ),
                                        const SizedBox(width: 3),
                                        Icon(Icons.expand_more_rounded,
                                            size: 13,
                                            color: invoiceStatusColor(inv.status)),
                                      ],
                                    ),
                                  ),
                                ),
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
//  CREATE / EDIT SCREEN  (2-step stepper)
// ════════════════════════════════════════════════════════════

class InvoiceCreateScreen extends StatefulWidget {
  const InvoiceCreateScreen({super.key});
  @override
  State<InvoiceCreateScreen> createState() => _InvoiceCreateScreenState();
}

class _InvoiceCreateScreenState extends State<InvoiceCreateScreen> {
  // null = still loading profile for new invoices
  Invoice? _inv;
  int  _step         = 0;
  bool _saving       = false;
  bool _prefilled    = false; // shows the "prefilled from profile" banner
  bool _isNewInvoice = false;

  @override
  void initState() {
    super.initState();
    final arg = Get.arguments;
    if (arg is Invoice) {
      // Editing existing — no prefill needed
      _inv          = arg;
      _isNewInvoice = false;
    } else {
      // New invoice — wait for profile data before building the form
      _isNewInvoice = true;
      _prefillFromProfile();
    }
  }

  /// Fetches profile from SharedPreferences (fast) + Firestore fallback,
  /// builds a fresh Invoice with all fields prefilled, then triggers a
  /// single rebuild so _DetailsStep / _ItemsStep receive the correct data.
  Future<void> _prefillFromProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid   = FirebaseAuth.instance.currentUser?.uid;

      // ── SharedPreferences — instant, offline-safe ──────────
      String sp(String key) => prefs.getString(key) ?? '';

      final name     = sp('profile_fullName');
      final biz      = sp('profile_businessName');
      final phone    = sp('profile_phone');
      final address  = sp('profile_address');
      final gstin    = sp('profile_gstNumber');
      final pan      = sp('profile_panNumber');
      final logo64   = sp('profile_logoBase64');
      final email    = sp('profile_email').isNotEmpty
          ? sp('profile_email')
          : (FirebaseAuth.instance.currentUser?.email ?? '');
      final bankName = sp('profile_bankName');
      final accName  = sp('profile_accountName');
      final accNum   = sp('profile_accountNumber');
      final ifsc     = sp('profile_ifscCode');
      final terms    = sp('profile_termsConditions');
      final tyNote   = sp('profile_thankYouNote');

      // ── Firestore fallback — only when prefs are empty ─────
      Map<String, dynamic> fs = {};
      final needsFirestore = biz.isEmpty && name.isEmpty;
      if (uid != null && needsFirestore) {
        final doc = await FirebaseFirestore.instance
            .collection('users').doc(uid).get();
        fs = doc.data() ?? {};
      }

      // Prefer SharedPreferences; fall back to Firestore field
      String pf(String prefValue, String fsKey) =>
          prefValue.isNotEmpty ? prefValue : ((fs[fsKey] as String?) ?? '');

      if (!mounted) return;

      // Build a brand new Invoice with all profile fields applied
      final inv = Invoice();

      final bizName = pf(biz, 'businessName');
      inv.companyName    = bizName.isNotEmpty ? bizName : pf(name, 'fullName');
      inv.companyAddress = pf(address, 'address');
      inv.companyPhone   = pf(phone,   'phone');
      inv.companyEmail   = pf(email,   'email');
      inv.gstNumber      = pf(gstin,   'gstNumber');
      inv.pan            = pf(pan,     'panNumber');
      inv.logoBase64     = logo64;

      inv.bankName      = pf(bankName, 'bankName');
      inv.accountName   = pf(accName,  'accountName');
      inv.accountNumber = pf(accNum,   'accountNumber');
      inv.ifscCode      = pf(ifsc,     'ifscCode');

      if (terms.isNotEmpty)  inv.termsConditions = terms;
      if (tyNote.isNotEmpty) inv.thankYouNote    = tyNote;

      inv.status = 'unpaid';

      final anyPrefilled = inv.companyName.isNotEmpty  ||
          inv.companyPhone.isNotEmpty ||
          inv.gstNumber.isNotEmpty    ||
          inv.bankName.isNotEmpty     ||
          inv.logoBase64.isNotEmpty;

      setState(() {
        _inv       = inv;
        _prefilled = anyPrefilled;
      });
    } catch (_) {
      if (mounted) setState(() { _inv = Invoice(); _prefilled = false; });
    }
  }

  Future<void> _save() async {
    final inv = _inv;
    if (inv == null) return;
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final col = FirebaseFirestore.instance
          .collection('users').doc(uid).collection('invoices');
      if (inv.id.isEmpty) {
        final doc = await col.add(inv.toMap());
        inv.id = doc.id;
      } else {
        await col.doc(inv.id).update(inv.toMap());
      }
      Get.back();
      Get.snackbar('Saved ✓', 'Invoice saved successfully',
          backgroundColor: BillifyColors.paid, colorText: Colors.white,
          snackPosition: SnackPosition.TOP);
    } catch (e) {
      Get.snackbar('Error', e.toString(),
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show a full-screen loader while profile is being fetched for new invoices
    if (_inv == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('New Invoice')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: BillifyColors.primary),
              const SizedBox(height: 16),
              Text('Loading your profile…',
                  style: GoogleFonts.nunito(
                      color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 14)),
            ],
          ),
        ),
      );
    }

    final inv   = _inv!;
    final steps = ['Details & Client', 'Items & Summary'];

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(inv.id.isEmpty ? 'New Invoice' : 'Edit Invoice'),
      ),
      body: Column(
        children: [

          // ── Prefilled-from-profile banner (new invoices only) ──
          if (_isNewInvoice && _prefilled)
            _PrefilledBanner(
              onDismiss: () => setState(() => _prefilled = false),
            ),

          // ── Step indicator ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: List.generate(steps.length, (i) {
                final active = i == _step;
                final done   = i < _step;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _step = i),
                    child: Padding(
                      padding: EdgeInsets.only(
                          right: i < steps.length - 1 ? 8 : 0),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: active
                              ? BillifyColors.primary
                              : (done
                              ? BillifyColors.primary.withOpacity(0.12)
                              : Colors.white),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: active
                                  ? BillifyColors.primary
                                  : BillifyColors.divider),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              done
                                  ? Icons.check_circle_rounded
                                  : (i == 0
                                  ? Icons.person_rounded
                                  : Icons.receipt_rounded),
                              color: active
                                  ? Colors.white
                                  : (done
                                  ? BillifyColors.primary
                                  : BillifyColors.textSecondary),
                              size: 18,
                            ),
                            const SizedBox(height: 4),
                            Text(steps[i],
                                textAlign: TextAlign.center,
                                style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: active
                                        ? Colors.white
                                        : (done
                                        ? BillifyColors.primary
                                        : BillifyColors.textSecondary))),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // ── Step content ────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              // Key forces widget to reconstruct when invoice object changes,
              // ensuring controllers pick up the prefilled values.
              key: ValueKey(inv.invoiceNumber),
              child: _step == 0
                  ? _DetailsStep(inv: inv, onChanged: () => setState(() {}))
                  : _ItemsStep(inv: inv, onChanged: () => setState(() {})),
            ),
          ),

          // ── Bottom navigation ───────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _step--),
                        icon:  const Icon(Icons.arrow_back_rounded),
                        label: const Text('Back'),
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 50)),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _saving
                        ? const Center(
                        child: CircularProgressIndicator(
                            color: BillifyColors.primary))
                        : ElevatedButton.icon(
                      onPressed: _step < steps.length - 1
                          ? () => setState(() => _step++)
                          : _save,
                      icon: Icon(_step < steps.length - 1
                          ? Icons.arrow_forward_rounded
                          : Icons.save_rounded),
                      label: Text(
                          _step < steps.length - 1
                              ? 'Next'
                              : 'Save Invoice',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 50)),
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

// ── Prefilled banner widget ───────────────────────────────────
class _PrefilledBanner extends StatelessWidget {
  final VoidCallback onDismiss;
  const _PrefilledBanner({required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            BillifyColors.paid.withOpacity(0.12),
            const Color(0xFFE8F5E9),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BillifyColors.paid.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color:  BillifyColors.paid.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_pin_rounded,
                color: BillifyColors.paid, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                text: 'Auto-filled from ',
                style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    color: BillifyColors.paid,
                    fontWeight: FontWeight.w600),
                children: [
                  TextSpan(
                    text: 'My Profile',
                    style: GoogleFonts.poppins(
                        fontSize: 12.5,
                        color: BillifyColors.paid,
                        fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: ' · Business, bank & tax details applied',
                    style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        color: BillifyColors.paid.withOpacity(0.8),
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Icon(Icons.close_rounded,
                color: BillifyColors.paid.withOpacity(0.6), size: 16),
          ),
        ],
      ),
    );
  }
}

// ── Step 0: Details & Client ─────────────────────────────────

class _DetailsStep extends StatefulWidget {
  final Invoice     inv;
  final VoidCallback onChanged;
  const _DetailsStep({required this.inv, required this.onChanged});
  @override
  State<_DetailsStep> createState() => _DetailsStepState();
}

class _DetailsStepState extends State<_DetailsStep> {
  late final _invNumCtrl    = TextEditingController(text: widget.inv.invoiceNumber);
  late final _orderIdCtrl   = TextEditingController(text: widget.inv.orderId);
  late final _panCtrl       = TextEditingController(text: widget.inv.pan);
  late final _gstCtrl       = TextEditingController(text: widget.inv.gstNumber);
  late final _cliNameCtrl   = TextEditingController(text: widget.inv.clientName);
  late final _cliPhoneCtrl  = TextEditingController(text: widget.inv.clientPhone);
  late final _cliAddrCtrl   = TextEditingController(text: widget.inv.clientAddress);
  late final _shootAddrCtrl = TextEditingController(text: widget.inv.shootAddress);
  late final _compNameCtrl  = TextEditingController(text: widget.inv.companyName);
  late final _compAddrCtrl  = TextEditingController(text: widget.inv.companyAddress);
  late final _compPhoneCtrl = TextEditingController(text: widget.inv.companyPhone);
  late final _compEmailCtrl = TextEditingController(text: widget.inv.companyEmail);
  late DateTime _orderDate  = widget.inv.orderDate;

  void _sync() {
    widget.inv.invoiceNumber = _invNumCtrl.text;
    widget.inv.orderId       = _orderIdCtrl.text;
    widget.inv.pan           = _panCtrl.text;
    widget.inv.gstNumber     = _gstCtrl.text;
    widget.inv.clientName    = _cliNameCtrl.text;
    widget.inv.clientPhone   = _cliPhoneCtrl.text;
    widget.inv.clientAddress = _cliAddrCtrl.text;
    widget.inv.shootAddress  = _shootAddrCtrl.text;
    widget.inv.companyName   = _compNameCtrl.text;
    widget.inv.companyAddress= _compAddrCtrl.text;
    widget.inv.companyPhone  = _compPhoneCtrl.text;
    widget.inv.companyEmail  = _compEmailCtrl.text;
    widget.inv.orderDate     = _orderDate;
    widget.onChanged();
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final source = await Get.dialog<ImageSource>(
      const BillifyImageSourceSheet(title: 'Choose Logo'),
    );
    if (source == null) return;
    final picked = await picker.pickImage(
        source: source, maxWidth: 512, maxHeight: 512, imageQuality: 85);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        widget.inv.logoBase64 = base64Encode(bytes);
        widget.inv.logoPath   = picked.path; // keep path for PDF fallback
      });
      widget.onChanged();
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context, initialDate: _orderDate,
      firstDate: DateTime(2020), lastDate: DateTime(2035),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: BillifyColors.primary)),
        child: child!,
      ),
    );
    if (picked != null) setState(() { _orderDate = picked; _sync(); });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Invoice Details'),
        _row2(
          _field(_invNumCtrl,  'Invoice No.',  Icons.tag_rounded,         onChanged: (_) => _sync()),
          _field(_orderIdCtrl, 'Order ID',     Icons.confirmation_number_rounded, onChanged: (_) => _sync()),
        ),
        const SizedBox(height: 12),

        // Order Date
        GestureDetector(
          onTap: _pickDate,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).dividerColor, width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_rounded, color: BillifyColors.primary, size: 18),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Order Date', style: GoogleFonts.nunito(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  Text(AppSettings.formatDate(_orderDate),
                      style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        _row2(
          _field(_panCtrl, 'PAN (optional)', Icons.credit_card_rounded,        onChanged: (_) => _sync()),
          _field(_gstCtrl, 'GST No. (optional)', Icons.receipt_long_rounded,   onChanged: (_) => _sync()),
        ),

        const SizedBox(height: 20),
        _SectionTitle('Bill To — Client'),
        _field(_cliNameCtrl,   'Client Name',     Icons.person_rounded,         onChanged: (_) => _sync()),
        const SizedBox(height: 10),
        _field(_cliPhoneCtrl,  'Client Phone',    Icons.phone_rounded,           onChanged: (_) => _sync()),
        const SizedBox(height: 10),
        _field(_cliAddrCtrl,   'Client Address',  Icons.location_on_rounded,     onChanged: (_) => _sync(), lines: 2),
        const SizedBox(height: 10),
        _field(_shootAddrCtrl, 'Shoot Address',   Icons.videocam_rounded,        onChanged: (_) => _sync(), lines: 2),

        const SizedBox(height: 20),
        _SectionTitle('Your Business'),
        _field(_compNameCtrl,  'Business / Studio Name', Icons.business_rounded,     onChanged: (_) => _sync()),
        const SizedBox(height: 10),
        // ── Logo picker ──
        GestureDetector(
          onTap: _pickLogo,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (widget.inv.logoBase64.isNotEmpty || widget.inv.logoPath.isNotEmpty)
                    ? BillifyColors.primary : BillifyColors.divider,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                // Thumbnail or placeholder
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: BillifyColors.primary.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: widget.inv.logoBase64.isNotEmpty
                      ? Image.memory(base64Decode(widget.inv.logoBase64), fit: BoxFit.cover)
                      : widget.inv.logoPath.isNotEmpty
                      ? Image.file(File(widget.inv.logoPath), fit: BoxFit.cover)
                      : const Icon(Icons.add_photo_alternate_rounded,
                      color: BillifyColors.primary, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (widget.inv.logoBase64.isNotEmpty || widget.inv.logoPath.isNotEmpty)
                            ? 'Logo selected ✓' : 'Add Company Logo',
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: (widget.inv.logoBase64.isNotEmpty || widget.inv.logoPath.isNotEmpty)
                                ? BillifyColors.primary : BillifyColors.textPrimary),
                      ),
                      Text(
                        widget.inv.logoBase64.isNotEmpty
                            ? 'From profile — tap to change'
                            : 'Tap to choose from gallery/camera',
                        style: GoogleFonts.nunito(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (widget.inv.logoBase64.isNotEmpty || widget.inv.logoPath.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: BillifyColors.unpaid, size: 20),
                    onPressed: () {
                      setState(() {
                        widget.inv.logoBase64 = '';
                        widget.inv.logoPath   = '';
                      });
                      widget.onChanged();
                    },
                    padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        const SizedBox(height: 10),
        _field(_compAddrCtrl,  'Your Address',     Icons.location_on_outlined,   onChanged: (_) => _sync(), lines: 2),
        const SizedBox(height: 10),
        _row2(
          _field(_compPhoneCtrl, 'Phone', Icons.phone_outlined, onChanged: (_) => _sync()),
          _field(_compEmailCtrl, 'Email', Icons.email_outlined, onChanged: (_) => _sync()),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Step 1: Items & Summary ──────────────────────────────────

class _ItemsStep extends StatefulWidget {
  final Invoice inv;
  final VoidCallback onChanged;
  const _ItemsStep({required this.inv, required this.onChanged});
  @override
  State<_ItemsStep> createState() => _ItemsStepState();
}

class _ItemsStepState extends State<_ItemsStep> {
  late final _bankCtrl    = TextEditingController(text: widget.inv.bankName);
  late final _accNameCtrl = TextEditingController(text: widget.inv.accountName);
  late final _accNumCtrl  = TextEditingController(text: widget.inv.accountNumber);
  late final _ifscCtrl    = TextEditingController(text: widget.inv.ifscCode);
  late final _termsCtrl   = TextEditingController(text: widget.inv.termsConditions);
  late final _tyCtrl      = TextEditingController(text: widget.inv.thankYouNote);
  String _status          = '';

  @override
  void initState() { super.initState(); _status = widget.inv.status; }

  void _syncPayment() {
    widget.inv.bankName      = _bankCtrl.text;
    widget.inv.accountName   = _accNameCtrl.text;
    widget.inv.accountNumber = _accNumCtrl.text;
    widget.inv.ifscCode      = _ifscCtrl.text;
    widget.inv.termsConditions = _termsCtrl.text;
    widget.inv.thankYouNote  = _tyCtrl.text;
    widget.onChanged();
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
    final inv = widget.inv;
    final fmt = AppSettings.currencyFmt(decimals: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Content / Services'),
        ...inv.items.asMap().entries.map((e) => _ContentItemRow(
          index: e.key,
          item: e.value,
          onChanged: () { setState(() {}); widget.onChanged(); },
          onDelete: inv.items.length > 1
              ? () { setState(() { inv.items.removeAt(e.key); widget.onChanged(); }); }
              : null,
        )),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () { setState(() { inv.items.add(ContentItem()); widget.onChanged(); }); },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add Service / Item'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
        ),
        const SizedBox(height: 20),

        // Totals preview
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Column(
            children: [
              _TotalRow('Sub Total',   fmt.format(inv.subTotal)),
              if (inv.totalTax  > 0) _TotalRow('GST / Tax',   fmt.format(inv.totalTax)),
              if (inv.totalIgst > 0) _TotalRow('IGST',        fmt.format(inv.totalIgst)),
              const Divider(),
              _TotalRow('Total',       fmt.format(inv.totalAmount), bold: true, highlight: true),
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
              onTap: () { setState(() { _status = s; inv.status = s; }); widget.onChanged(); },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? _statusColor(s) : Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: active ? _statusColor(s) : Theme.of(context).dividerColor),
                ),
                child: Text(s[0].toUpperCase() + s.substring(1),
                    style: GoogleFonts.nunito(fontWeight: FontWeight.w700,
                        color: active ? Colors.white : BillifyColors.textSecondary)),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 20),
        _SectionTitle('Payment Information'),
        _field2(_bankCtrl,    'Bank Name',    Icons.account_balance_rounded, (v) => _syncPayment()),
        const SizedBox(height: 10),
        _field2(_accNameCtrl, 'Account Name', Icons.person_rounded,          (v) => _syncPayment()),
        const SizedBox(height: 10),
        _field2(_accNumCtrl,  'Account No.',  Icons.credit_card_rounded,     (v) => _syncPayment()),
        const SizedBox(height: 10),
        _field2(_ifscCtrl,    'IFSC Code',    Icons.code_rounded,            (v) => _syncPayment()),

        const SizedBox(height: 20),
        _SectionTitle('Terms & Note'),
        TextField(
          controller: _termsCtrl, maxLines: 3, onChanged: (_) => _syncPayment(),
          decoration: const InputDecoration(labelText: 'Terms & Conditions', prefixIcon: Icon(Icons.description_outlined, color: BillifyColors.primary), alignLabelWithHint: true),
        ),
        const SizedBox(height: 10),
        _field2(_tyCtrl, 'Thank You Note', Icons.favorite_rounded, (v) => _syncPayment()),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _field2(TextEditingController ctrl, String label, IconData icon, ValueChanged<String> onChanged) =>
      TextField(
        controller: ctrl, onChanged: onChanged,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, color: BillifyColors.primary)),
      );
}

// ── Content Item Row ──────────────────────────────────────────

class _ContentItemRow extends StatefulWidget {
  final int          index;
  final ContentItem  item;
  final VoidCallback onChanged;
  final VoidCallback? onDelete;
  const _ContentItemRow({required this.index, required this.item, required this.onChanged, this.onDelete});
  @override
  State<_ContentItemRow> createState() => _ContentItemRowState();
}

class _ContentItemRowState extends State<_ContentItemRow> {
  late final _titleCtrl = TextEditingController(text: widget.item.title);
  late final _qtyCtrl   = TextEditingController(text: widget.item.qty.toString());
  late final _grossCtrl = TextEditingController(text: widget.item.grossAmount == 0 ? '' : widget.item.grossAmount.toString());
  late final _discCtrl  = TextEditingController(text: widget.item.discount == 0 ? '' : widget.item.discount.toString());
  late final _taxCtrl   = TextEditingController(text: widget.item.taxPercent.toString());
  late final _igstCtrl  = TextEditingController(text: widget.item.igstPercent.toString());

  void _changed() { widget.onChanged(); setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final fmt  = AppSettings.currencyFmt(decimals: 2);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [BoxShadow(color: BillifyColors.primary.withOpacity(0.04), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
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
                  controller: _titleCtrl,
                  onChanged: (v) { item.title = v; _changed(); },
                  decoration: InputDecoration(
                    hintText: 'Service title (e.g. Reel Shoot — 2hrs)',
                    hintStyle: GoogleFonts.nunito(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: BillifyColors.primary, width: 2),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                  ),
                  style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                ),
              ),
              if (widget.onDelete != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: BillifyColors.unpaid, size: 20),
                  onPressed: widget.onDelete,
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Gross amount (always shown)
          _numField(_grossCtrl, 'Gross Amount (₹)', (v) { item.grossAmount = double.tryParse(v) ?? 0; _changed(); }, decimal: true),
          const SizedBox(height: 10),

          // Optional toggles
          Wrap(
            spacing: 8, runSpacing: 8,
            children: [
              _toggle('Qty', item.hasQty, (v) { setState(() { item.hasQty = v; }); _changed(); }),
              _toggle('Discount', item.hasDiscount, (v) { setState(() { item.hasDiscount = v; }); _changed(); }),
              _toggle('Tax / GST', item.hasTax, (v) { setState(() { item.hasTax = v; }); _changed(); }),
              _toggle('IGST', item.hasIgst, (v) { setState(() { item.hasIgst = v; }); _changed(); }),
            ],
          ),
          const SizedBox(height: 10),

          // Conditional fields
          if (item.hasQty) ...[
            _numField(_qtyCtrl, 'Quantity', (v) { item.qty = int.tryParse(v) ?? 1; _changed(); }),
            const SizedBox(height: 8),
          ],
          if (item.hasDiscount) ...[
            _numField(_discCtrl, 'Discount (₹)', (v) { item.discount = double.tryParse(v) ?? 0; _changed(); }, decimal: true),
            const SizedBox(height: 8),
          ],
          if (item.hasTax) ...[
            _numField(_taxCtrl, 'Tax / GST %', (v) { item.taxPercent = double.tryParse(v) ?? AppSettings.defaultGst; _changed(); }, decimal: true),
            const SizedBox(height: 8),
          ],
          if (item.hasIgst) ...[
            _numField(_igstCtrl, 'IGST %', (v) { item.igstPercent = double.tryParse(v) ?? AppSettings.defaultGst; _changed(); }, decimal: true),
            const SizedBox(height: 8),
          ],

          // Line total
          Align(
            alignment: Alignment.centerRight,
            child: Text('Line Total: ${fmt.format(item.lineTotal)}',
                style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700, color: BillifyColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value ? BillifyColors.primary.withOpacity(0.1) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: value ? BillifyColors.primary : Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(value ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                color: value ? BillifyColors.primary : BillifyColors.textSecondary, size: 14),
            const SizedBox(width: 4),
            Text(label, style: GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w700,
                color: value ? BillifyColors.primary : BillifyColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _numField(TextEditingController ctrl, String label, ValueChanged<String> onChanged, {bool decimal = false}) =>
      TextField(
        controller: ctrl, onChanged: onChanged,
        keyboardType: decimal ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(decimal ? RegExp(r'[\d.]') : RegExp(r'\d'))],
        decoration: InputDecoration(
          labelText: label, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
          border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Theme.of(context).dividerColor)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Theme.of(context).dividerColor, width: 1.5)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: BillifyColors.primary, width: 2)),
          filled: true, fillColor: Theme.of(context).scaffoldBackgroundColor,
        ),
        style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
      );
}

// ════════════════════════════════════════════════════════════
//  INVOICE DETAIL SCREEN
// ════════════════════════════════════════════════════════════

class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key});
  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  Invoice? _inv;
  bool _loading    = false;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    final arg = Get.arguments;
    if (arg is Invoice) {
      // Came from InvoiceListScreen — full object already
      _inv = arg;
    } else if (arg is Map && arg.containsKey('invoiceId')) {
      // Came from Dashboard — only invoiceId passed; fetch from Firestore
      _fetchById(arg['invoiceId'] as String);
    } else {
      _inv = Invoice();
    }
  }

  Future<void> _fetchById(String invoiceId) async {
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('invoices').doc(invoiceId)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _inv     = Invoice.fromMap(doc.id, doc.data()!);
          _loading = false;
        });
      } else {
        setState(() { _inv = Invoice(); _loading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _inv = Invoice(); _loading = false; });
      Get.snackbar('Error', 'Could not load invoice: $e',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    }
  }

  Future<void> _deleteInvoice() async {
    final inv = _inv;
    if (inv == null) return;
    final confirm = await Get.dialog<bool>(
      BillifyDialog(
        icon:         Icons.delete_outline_rounded,
        iconColor:    BillifyColors.unpaid,
        title:        'Delete Invoice?',
        body:         'This invoice will be permanently removed. This action cannot be undone.',
        confirmLabel: 'Delete',
        confirmColor: BillifyColors.unpaid,
        onConfirm:    () => Get.back(result: true),
      ),
    );
    if (confirm != true) return;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('invoices').doc(inv.id).delete();
      Get.back(); // return to whoever opened this (list or dashboard)
      Get.snackbar('Deleted', 'Invoice deleted',
          backgroundColor: BillifyColors.paid, colorText: Colors.white,
          snackPosition: SnackPosition.TOP);
    } catch (e) {
      Get.snackbar('Error', 'Could not delete invoice', backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    }
  }

  // ── PDF generation — works on Web + Mobile ───────────────
  // Uses package:printing which handles:
  //   • Android → native share sheet via share_plus
  //   • Web     → browser download via Printing.sharePdf
  Future<void> _generateAndSharePdf() async {
    final inv = _inv;
    if (inv == null) return;
    setState(() => _generating = true);
    final filename = 'invoice_${inv.invoiceNumber.replaceAll('-', '_')}.pdf';
    try {
      final pdfDoc = await _buildPdfDocument(inv);
      final bytes  = Uint8List.fromList(await pdfDoc.save());

      if (kIsWeb) {
        // Web: Printing.sharePdf triggers the browser's native Save/Download dialog
        await Printing.sharePdf(bytes: bytes, filename: filename);
      } else {
        // Android / iOS: write PDF to temp file then open native share sheet
        final dir  = await getTemporaryDirectory();
        final file = File('${dir.path}/$filename');
        await file.writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/pdf')],
          subject: filename,
        );
      }
    } catch (e) {
      Get.snackbar('Error', 'Could not generate PDF: ${e.toString()}',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while fetching by ID from dashboard
    if (_loading || _inv == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(title: const Text('Invoice Detail')),
        body: const Center(child: CircularProgressIndicator(color: BillifyColors.primary)),
      );
    }
    final inv = _inv!;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(inv.invoiceNumber.isEmpty ? 'Invoice Detail' : inv.invoiceNumber),
        actions: [
          IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => Get.toNamed(AppRoutes.invoiceEdit, arguments: inv), tooltip: 'Edit'),
          IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: _deleteInvoice, tooltip: 'Delete'),
          PopupMenuButton<String>(
            onSelected: (v) { if (v == 'pdf') _generateAndSharePdf(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pdf', child: Row(children: [
                Icon(Icons.picture_as_pdf_rounded, color: BillifyColors.primary, size: 20),
                SizedBox(width: 10),
                Text('Share as PDF'),
              ])),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Tappable status banner — tap to change status
            GestureDetector(
              onTap: () => showStatusPicker(context, inv.id, inv.status),
              child: _StatusBanner(status: inv.status, showChangeTip: true),
            ),
            const SizedBox(height: 12),
            _InvoicePreview(inv: inv),
            const SizedBox(height: 20),
            _generating
                ? const Center(child: CircularProgressIndicator(color: BillifyColors.primary))
                : Column(
              children: [
                ElevatedButton.icon(
                  onPressed: _generateAndSharePdf,
                  icon:  const Icon(Icons.picture_as_pdf_rounded),
                  label: Text(kIsWeb ? 'Download PDF' : 'Save / Share as PDF'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Get.toNamed(AppRoutes.invoiceEdit, arguments: inv),
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
    );
  }
}

// ════════════════════════════════════════════════════════════
//  PDF BUILDER  (using pdf package — generates a real PDF)
// ════════════════════════════════════════════════════════════

Future<pw.Document> _buildPdfDocument(Invoice inv) async {
  final pdf     = pw.Document();
  final dateFmt = DateFormat(AppSettings.dateFormat);

  // ── Use "Rs." as currency symbol — Helvetica/NotoSans both render it fine ──
  // ₹ (U+20B9) is not in Helvetica. We use NotoSans which covers it.
  // Load NotoSans from Flutter assets (add to pubspec: assets/fonts/NotoSans-Regular.ttf etc.)
  // Fallback: if font load fails, we use "Rs." so the PDF never shows boxes.
  pw.Font regular, bold;
  try {
    final regData  = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    regular = pw.Font.ttf(regData);
    bold    = pw.Font.ttf(boldData);
  } catch (_) {
    regular = pw.Font.helvetica();
    bold    = pw.Font.helveticaBold();
  }

  // Currency formatter — always use "Rs." so even fallback font renders it
  String fmtRs(double v) {
    final s = NumberFormat('#,##,##0.00', 'en_IN').format(v);
    return 'Rs. $s';
  }

  // colours
  const black   = PdfColors.black;
  const white   = PdfColors.white;
  final grey100 = PdfColor.fromHex('#F5F5F5');
  final grey300 = PdfColor.fromHex('#DDDDDD');
  final grey600 = PdfColor.fromHex('#666666');
  final accent  = PdfColor.fromHex('#1A1A2E');

  pw.TextStyle ts(double size, {PdfColor? color, double? height}) =>
      pw.TextStyle(font: regular, fontSize: size, color: color ?? black, lineSpacing: height);

  pw.TextStyle tsb(double size, {PdfColor? color}) =>
      pw.TextStyle(font: bold, fontSize: size, color: color ?? black);

  // ── Load logo — base64 first, file path fallback ──
  pw.ImageProvider? logoImg;
  if (inv.logoBase64.isNotEmpty) {
    try {
      logoImg = pw.MemoryImage(base64Decode(inv.logoBase64));
    } catch (_) { logoImg = null; }
  } else if (inv.logoPath.isNotEmpty) {
    try {
      final bytes = await File(inv.logoPath).readAsBytes();
      logoImg = pw.MemoryImage(bytes);
    } catch (_) { logoImg = null; }
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      build: (ctx) {
        return [

          // ── HEADER ──────────────────────────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Company block — logo + name + details
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Logo
                    if (logoImg != null) ...[
                      pw.ClipRRect(
                        horizontalRadius: 8, verticalRadius: 8,
                        child: pw.Image(logoImg, width: 72, height: 72, fit: pw.BoxFit.cover),
                      ),
                      pw.SizedBox(height: 8),
                    ],
                    pw.Text(inv.companyName.isEmpty ? 'Your Name / Studio' : inv.companyName,
                        style: tsb(20, color: accent)),
                    if (inv.companyAddress.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text(inv.companyAddress, style: ts(9, color: grey600)),
                    ],
                    if (inv.companyPhone.isNotEmpty)
                      pw.Text(inv.companyPhone, style: ts(9, color: grey600)),
                    if (inv.companyEmail.isNotEmpty)
                      pw.Text(inv.companyEmail, style: ts(9, color: grey600)),
                    if (inv.pan.isNotEmpty) ...[
                      pw.SizedBox(height: 2),
                      pw.Text('PAN: ${inv.pan}', style: ts(9, color: grey600)),
                    ],
                    if (inv.gstNumber.isNotEmpty)
                      pw.Text('GSTIN: ${inv.gstNumber}', style: ts(9, color: grey600)),
                  ],
                ),
              ),
              // Invoice meta block
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('INVOICE', style: tsb(26, color: accent)),
                  pw.SizedBox(height: 4),
                  _pdfMetaRow(bold: bold, regular: regular, label: 'Invoice No.', value: '#${inv.invoiceNumber}'),
                  _pdfMetaRow(bold: bold, regular: regular, label: 'Order ID',    value: inv.orderId),
                  _pdfMetaRow(bold: bold, regular: regular, label: 'Date',        value: dateFmt.format(inv.orderDate)),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 16),
          pw.Divider(color: grey300, thickness: 1),
          pw.SizedBox(height: 14),

          // ── BILL TO ─────────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(color: grey100, borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('BILL TO', style: tsb(9, color: grey600)),
                      pw.SizedBox(height: 4),
                      pw.Text(inv.clientName.isEmpty ? '—' : inv.clientName, style: tsb(12)),
                      if (inv.clientPhone.isNotEmpty)
                        pw.Text(inv.clientPhone, style: ts(9, color: grey600)),
                      if (inv.clientAddress.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Text(inv.clientAddress, style: ts(9, color: grey600)),
                      ],
                    ],
                  ),
                ),
                pw.SizedBox(width: 20),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('SHOOT LOCATION', style: tsb(9, color: grey600)),
                      pw.SizedBox(height: 4),
                      pw.Text(inv.shootAddress.isEmpty ? '—' : inv.shootAddress,
                          style: ts(9, color: grey600)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          pw.SizedBox(height: 20),

          // ── ITEMS TABLE ──────────────────────────────────────────
          pw.Table(
            border: pw.TableBorder(
              top:    pw.BorderSide(color: accent, width: 1.5),
              bottom: pw.BorderSide(color: accent, width: 1.5),
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1.6),
              3: const pw.FlexColumnWidth(1.6),
              4: const pw.FlexColumnWidth(1.4),
              5: const pw.FlexColumnWidth(1.6),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: accent),
                children: ['Description', 'Qty', 'Gross', 'Discount', 'Tax/IGST', 'Total']
                    .map((h) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: pw.Text(h, style: tsb(9, color: white)),
                ))
                    .toList(),
              ),
              ...inv.items.asMap().entries.map((e) {
                final item   = e.value;
                final isEven = e.key.isEven;
                final rowBg  = isEven ? white : PdfColor.fromHex('#F9F9F9');
                final taxLine = [
                  if (item.hasTax)  'GST ${item.taxPercent.toStringAsFixed(0)}%',
                  if (item.hasIgst) 'IGST ${item.igstPercent.toStringAsFixed(0)}%',
                ].join(' + ');

                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: rowBg),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: pw.Text(item.title.isEmpty ? 'Item ${e.key + 1}' : item.title, style: ts(9))),
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: pw.Text(item.hasQty ? '${item.qty}' : '—', style: ts(9))),
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: pw.Text(fmtRs(item.grossAmount), style: ts(9))),
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: pw.Text(item.hasDiscount && item.discount > 0 ? fmtRs(item.discount) : '—', style: ts(9))),
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: pw.Text(taxLine.isEmpty ? '—' : taxLine, style: ts(8))),
                    pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                        child: pw.Text(fmtRs(item.lineTotal), style: tsb(9))),
                  ],
                );
              }),
            ],
          ),

          pw.SizedBox(height: 12),

          // ── TOTALS ───────────────────────────────────────────────
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.SizedBox(
              width: 240,
              child: pw.Column(
                children: [
                  _pdfTotalRow(regular: regular, bold: bold, label: 'Sub Total', value: fmtRs(inv.subTotal)),
                  if (inv.totalTax  > 0) _pdfTotalRow(regular: regular, bold: bold, label: 'Tax / GST', value: fmtRs(inv.totalTax)),
                  if (inv.totalIgst > 0) _pdfTotalRow(regular: regular, bold: bold, label: 'IGST',      value: fmtRs(inv.totalIgst)),
                  pw.SizedBox(height: 4),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    color: accent,
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('TOTAL DUE', style: tsb(11, color: white)),
                        pw.Text(fmtRs(inv.totalAmount), style: tsb(11, color: white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          pw.SizedBox(height: 24),
          pw.Divider(color: grey300),
          pw.SizedBox(height: 12),

          // ── FOOTER: Terms + Payment info ────────────────────────
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Terms & Conditions', style: tsb(10)),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      inv.termsConditions.isEmpty
                          ? 'Payment due within 7 days of invoice date.'
                          : inv.termsConditions,
                      style: ts(8, color: grey600, height: 1.4),
                    ),
                    pw.SizedBox(height: 14),
                    pw.Text(inv.thankYouNote.isEmpty ? 'Thank you!' : inv.thankYouNote,
                        style: tsb(16, color: accent)),
                  ],
                ),
              ),
              pw.SizedBox(width: 24),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Payment Information', style: tsb(10)),
                  pw.SizedBox(height: 4),
                  if (inv.bankName.isNotEmpty)      pw.Text(inv.bankName,                              style: ts(9, color: grey600)),
                  if (inv.accountName.isNotEmpty)   pw.Text('Name: ${inv.accountName}',                style: ts(9, color: grey600)),
                  if (inv.accountNumber.isNotEmpty) pw.Text('A/C: ${inv.accountNumber}',               style: ts(9, color: grey600)),
                  if (inv.ifscCode.isNotEmpty)      pw.Text('IFSC: ${inv.ifscCode}',                   style: ts(9, color: grey600)),
                ],
              ),
            ],
          ),

          pw.SizedBox(height: 8),
          // (footer note removed)
        ];
      },
    ),
  );

  return pdf;
}

// PDF helper widgets
pw.Widget _pdfMetaRow({required pw.Font bold, required pw.Font regular, required String label, required String value}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text('$label: ', style: pw.TextStyle(font: bold, fontSize: 9, color: PdfColor.fromHex('#666666'))),
          pw.Text(value,       style: pw.TextStyle(font: regular, fontSize: 9)),
        ],
      ),
    );

pw.Widget _pdfTotalRow({required pw.Font bold, required pw.Font regular, required String label, required String value}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: bold,    fontSize: 10)),
          pw.Text(value, style: pw.TextStyle(font: regular, fontSize: 10)),
        ],
      ),
    );

// ════════════════════════════════════════════════════════════
//  IN-APP INVOICE PREVIEW  (Flutter widget)
// ════════════════════════════════════════════════════════════

class _InvoicePreview extends StatelessWidget {
  final Invoice inv;
  const _InvoicePreview({required this.inv});

  @override
  Widget build(BuildContext context) {
    final fmt     = AppSettings.currencyFmt(decimals: 2);
    final dateFmt = DateFormat(AppSettings.dateFormat);

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo
                    if (inv.logoPath.isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(File(inv.logoPath), width: 64, height: 64, fit: BoxFit.cover),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(inv.companyName.isEmpty ? 'Your Studio' : inv.companyName,
                        style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A2E))),
                    if (inv.companyAddress.isNotEmpty)
                      Text(inv.companyAddress, style: GoogleFonts.nunito(fontSize: 10, color: Colors.black54)),
                    if (inv.companyPhone.isNotEmpty)
                      Text(inv.companyPhone, style: GoogleFonts.nunito(fontSize: 10, color: Colors.black54)),
                    if (inv.companyEmail.isNotEmpty)
                      Text(inv.companyEmail, style: GoogleFonts.nunito(fontSize: 10, color: Colors.black54)),
                    if (inv.pan.isNotEmpty)
                      Text('PAN: ${inv.pan}', style: GoogleFonts.nunito(fontSize: 10, color: Colors.black54)),
                    if (inv.gstNumber.isNotEmpty)
                      Text('GSTIN: ${inv.gstNumber}', style: GoogleFonts.nunito(fontSize: 10, color: Colors.black54)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('INVOICE', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF1A1A2E))),
                  const SizedBox(height: 4),
                  _metaChip('Invoice No.', '#${inv.invoiceNumber}'),
                  _metaChip('Order ID',    inv.orderId),
                  _metaChip('Date',        dateFmt.format(inv.orderDate)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 12),

          // ── Bill To ──
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF5F5F5), borderRadius: BorderRadius.circular(8)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('BILL TO', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.black54)),
                    const SizedBox(height: 4),
                    Text(inv.clientName.isEmpty ? '—' : inv.clientName,
                        style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w700)),
                    if (inv.clientPhone.isNotEmpty)
                      Text(inv.clientPhone, style: GoogleFonts.nunito(fontSize: 10, color: Colors.black54)),
                    if (inv.clientAddress.isNotEmpty)
                      Text(inv.clientAddress, style: GoogleFonts.nunito(fontSize: 10, color: Colors.black54)),
                  ],
                )),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('SHOOT LOCATION', style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.black54)),
                    const SizedBox(height: 4),
                    Text(inv.shootAddress.isEmpty ? '—' : inv.shootAddress,
                        style: GoogleFonts.nunito(fontSize: 10, color: Colors.black54)),
                  ],
                )),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Items ──
          Table(
            border: TableBorder(top: BorderSide(color: Colors.black, width: 1.5), bottom: BorderSide(color: Colors.black, width: 1.5)),
            columnWidths: const {
              0: FlexColumnWidth(3),
              1: FlexColumnWidth(0.8),
              2: FlexColumnWidth(1.4),
              3: FlexColumnWidth(1.4),
              4: FlexColumnWidth(1.2),
              5: FlexColumnWidth(1.4),
            },
            children: [
              TableRow(
                decoration: const BoxDecoration(color: Color(0xFF1A1A2E)),
                children: ['Description', 'Qty', 'Gross', 'Disc.', 'Tax', 'Total'].map((h) =>
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                        child: Text(h, style: GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)))).toList(),
              ),
              ...inv.items.asMap().entries.map((e) {
                final item   = e.value;
                final isEven = e.key.isEven;
                final taxLine = [
                  if (item.hasTax)  'G${item.taxPercent.toStringAsFixed(0)}%',
                  if (item.hasIgst) 'I${item.igstPercent.toStringAsFixed(0)}%',
                ].join('+');

                return TableRow(
                  decoration: BoxDecoration(
                    color: isEven ? Theme.of(context).cardColor : Theme.of(context).scaffoldBackgroundColor,
                    border: const Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
                  ),
                  children: [
                    _cell(item.title.isEmpty ? 'Item ${e.key + 1}' : item.title),
                    _cell(item.hasQty ? '${item.qty}' : '—'),
                    _cell(fmt.format(item.grossAmount)),
                    _cell(item.hasDiscount && item.discount > 0 ? fmt.format(item.discount) : '—'),
                    _cell(taxLine.isEmpty ? '—' : taxLine),
                    _cell(fmt.format(item.lineTotal), bold: true),
                  ],
                );
              }),
            ],
          ),
          const SizedBox(height: 12),

          // ── Totals ──
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 200,
              child: Column(
                children: [
                  _InvTotalRow('Sub Total', fmt.format(inv.subTotal)),
                  if (inv.totalTax  > 0) _InvTotalRow('GST / Tax',  fmt.format(inv.totalTax)),
                  if (inv.totalIgst > 0) _InvTotalRow('IGST',       fmt.format(inv.totalIgst)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    color: const Color(0xFF1A1A2E),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('TOTAL DUE', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                        Text(fmt.format(inv.totalAmount), style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),
          const Divider(color: Color(0xFFCCCCCC)),
          const SizedBox(height: 12),

          // ── Footer ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Terms & Conditions', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    inv.termsConditions.isEmpty
                        ? 'Payment due within 7 days of invoice date.'
                        : inv.termsConditions,
                    style: GoogleFonts.nunito(fontSize: 9, color: Colors.black54, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Text(inv.thankYouNote.isEmpty ? 'Thank you!' : inv.thankYouNote,
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A2E))),
                ],
              )),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Payment Information', style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  if (inv.bankName.isNotEmpty)      Text(inv.bankName,                              style: GoogleFonts.nunito(fontSize: 9, color: Colors.black54)),
                  if (inv.accountName.isNotEmpty)   Text('Name: ${inv.accountName}',               style: GoogleFonts.nunito(fontSize: 9, color: Colors.black54)),
                  if (inv.accountNumber.isNotEmpty) Text('A/C: ${inv.accountNumber}',              style: GoogleFonts.nunito(fontSize: 9, color: Colors.black54)),
                  if (inv.ifscCode.isNotEmpty)      Text('IFSC: ${inv.ifscCode}',                  style: GoogleFonts.nunito(fontSize: 9, color: Colors.black54)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _metaChip(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: RichText(text: TextSpan(
      text: '$label: ',
      style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.black54),
      children: [TextSpan(text: value, style: GoogleFonts.nunito(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.w600))],
    )),
  );

  Widget _cell(String text, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    child: Text(text, style: bold
        ? GoogleFonts.poppins(fontSize: 9, fontWeight: FontWeight.w700)
        : GoogleFonts.nunito(fontSize: 9, color: Colors.black87)),
  );
}

// ════════════════════════════════════════════════════════════
//  EDIT SCREEN  (re-uses Create)
// ════════════════════════════════════════════════════════════

class InvoiceEditScreen extends StatelessWidget {
  const InvoiceEditScreen({super.key});
  @override
  Widget build(BuildContext context) => const InvoiceCreateScreen();
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

class _StatusBanner extends StatelessWidget {
  final String status;
  final bool   showChangeTip;
  const _StatusBanner({required this.status, this.showChangeTip = false});

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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: _bg,
      borderRadius: BorderRadius.circular(12),
      border: showChangeTip
          ? Border.all(color: _fg.withOpacity(0.3))
          : null,
    ),
    child: Row(children: [
      Icon(_icon, color: _fg, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Status: ${status[0].toUpperCase()}${status.substring(1)}',
          style: GoogleFonts.poppins(
              color: _fg, fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      if (showChangeTip) ...[
        Text('Tap to change',
            style: GoogleFonts.nunito(
                fontSize: 11,
                color: _fg.withOpacity(0.7),
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        Icon(Icons.swap_horiz_rounded, color: _fg.withOpacity(0.7), size: 15),
      ],
    ]),
  );
}

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
    child: Text(status[0].toUpperCase() + status.substring(1),
        style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: _fg)),
  );
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
        Text(label, style: GoogleFonts.poppins(fontSize: 11, fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: Colors.black)),
        Text(value, style: GoogleFonts.nunito(fontSize: 11, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: Colors.black87)),
      ],
    ),
  );
}

class _TotalRow extends StatelessWidget {
  final String label, value;
  final bool   bold, highlight;
  const _TotalRow(this.label, this.value, {this.bold = false, this.highlight = false});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: GoogleFonts.nunito(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: bold ? BillifyColors.textPrimary : BillifyColors.textSecondary,
        ))),
        Text(value, style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: highlight ? BillifyColors.unpaid : (bold ? BillifyColors.textPrimary : BillifyColors.textSecondary),
        )),
      ],
    ),
  );
}