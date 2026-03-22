// ════════════════════════════════════════════════════════════
//  dashboard_screen.dart — Billify Phase 2
//  Full Dashboard with summary cards, bar chart, recent invoices
//  and quick-action FABs. Reads live data from Firestore.
// ════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'main.dart' show BillifyColors, AppRoutes, BillifyDrawer;

// ────────────────────────────────────────────────────────────
//  DATA MODELS (lightweight, dashboard-only)
// ────────────────────────────────────────────────────────────
class _DashboardData {
  final double totalRevenue;
  final int    pendingCount;
  final int    paidCount;
  final double netBalance;
  final List<_MonthBar> monthBars;   // last 4 months
  final List<_RecentInvoice> recent; // last 5 invoices

  const _DashboardData({
    required this.totalRevenue,
    required this.pendingCount,
    required this.paidCount,
    required this.netBalance,
    required this.monthBars,
    required this.recent,
  });
}

class _MonthBar {
  final String label;   // e.g. "Jan"
  final double income;
  final double expense;
  const _MonthBar(this.label, this.income, this.expense);
}

class _RecentInvoice {
  final String invoiceNumber;
  final String clientName;
  final double totalAmount;
  final String status; // paid / unpaid / draft / overdue
  final DateTime date;
  final String invoiceId;
  const _RecentInvoice({
    required this.invoiceNumber,
    required this.clientName,
    required this.totalAmount,
    required this.status,
    required this.date,
    required this.invoiceId,
  });
}

// ────────────────────────────────────────────────────────────
//  DASHBOARD CONTROLLER (GetX)
// ────────────────────────────────────────────────────────────
class DashboardController extends GetxController {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final isLoading = true.obs;
  final data      = Rxn<_DashboardData>();
  final userName  = ''.obs;

  @override
  void onInit() {
    super.onInit();
    _loadUserName();
    _loadDashboard();
  }

  void _loadUserName() {
    final user = _auth.currentUser;
    if (user != null) {
      // Use first word of displayName, else fetch from Firestore
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        userName.value = user.displayName!.split(' ').first;
      } else {
        _db.collection('users').doc(user.uid).get().then((doc) {
          final full = doc.data()?['fullName'] ?? '';
          userName.value = (full as String).split(' ').first;
        });
      }
    }
  }

  Future<void> _loadDashboard() async {
    isLoading.value = true;
    try {
      final uid = _auth.currentUser!.uid;

      // ── Invoices ──
      final invoiceSnap = await _db
          .collection('users')
          .doc(uid)
          .collection('invoices')
          .get();

      double totalRevenue = 0;
      int    pendingCount = 0;
      int    paidCount    = 0;
      final List<_RecentInvoice> allInvoices = [];

      for (final doc in invoiceSnap.docs) {
        final d      = doc.data();
        final status = (d['status'] ?? 'draft') as String;
        final amount = (d['totalAmount'] ?? 0.0) as num;
        final ts     = d['invoiceDate'] as Timestamp?;
        final date   = ts?.toDate() ?? DateTime.now();

        if (status == 'paid')   { totalRevenue += amount.toDouble(); paidCount++; }
        if (status == 'unpaid' || status == 'overdue') pendingCount++;

        allInvoices.add(_RecentInvoice(
          invoiceId:     doc.id,
          invoiceNumber: d['invoiceNumber'] ?? '',
          clientName:    d['clientName'] ?? '',
          totalAmount:   amount.toDouble(),
          status:        status,
          date:          date,
        ));
      }

      // Sort by date desc, take last 5
      allInvoices.sort((a, b) => b.date.compareTo(a.date));
      final recent = allInvoices.take(5).toList();

      // ── Expenses ──
      final expenseSnap = await _db
          .collection('users')
          .doc(uid)
          .collection('expenses')
          .get();

      // Build monthly bars — current month + 3 previous
      final now = DateTime.now();
      final Map<String, double> incomeByMonth  = {};
      final Map<String, double> expenseByMonth = {};

      for (int i = 3; i >= 0; i--) {
        final m    = DateTime(now.year, now.month - i, 1);
        final key  = DateFormat('MMM').format(m);
        incomeByMonth[key]  = 0;
        expenseByMonth[key] = 0;
      }

      double totalIncome  = 0;
      double totalExpense = 0;

      for (final doc in expenseSnap.docs) {
        final d      = doc.data();
        final type   = (d['type'] ?? 'expense') as String;
        final amount = (d['amount'] ?? 0.0) as num;
        final ts     = d['date'] as Timestamp?;
        final date   = ts?.toDate() ?? DateTime.now();
        final key    = DateFormat('MMM').format(date);

        if (incomeByMonth.containsKey(key)) {
          if (type == 'income') {
            incomeByMonth[key] = incomeByMonth[key]! + amount.toDouble();
            totalIncome += amount.toDouble();
          } else {
            expenseByMonth[key] = expenseByMonth[key]! + amount.toDouble();
            totalExpense += amount.toDouble();
          }
        }
      }

      final monthBars = incomeByMonth.keys.map((k) =>
          _MonthBar(k, incomeByMonth[k]!, expenseByMonth[k]!)).toList();

      data.value = _DashboardData(
        totalRevenue: totalRevenue,
        pendingCount: pendingCount,
        paidCount:    paidCount,
        netBalance:   totalIncome - totalExpense,
        monthBars:    monthBars,
        recent:       recent,
      );
    } catch (e) {
      debugPrint('Dashboard load error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void refresh() => _loadDashboard();
}

// ────────────────────────────────────────────────────────────
//  DASHBOARD SCREEN
// ────────────────────────────────────────────────────────────
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.put(DashboardController());
    final fmt  = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Scaffold(
      backgroundColor: BillifyColors.background,
      drawer: const BillifyDrawer(activeRoute: AppRoutes.dashboard),

      // ── Custom AppBar ──
      appBar: AppBar(
        backgroundColor: BillifyColors.primary,
        elevation:       0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Image.asset(
          'assets/images/billify_logo_white.png',
          height: 28,
          errorBuilder: (_, __, ___) => Text(
            'Billify',
            style: GoogleFonts.poppins(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800,
            ),
          ),
        ),
        actions: [
          // Refresh button
          Obx(() => ctrl.isLoading.value
              ? const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            ),
          )
              : IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: ctrl.refresh,
          )),
          // Notification placeholder
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),

      // ── FABs ──
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag:     'fab_expense',
            onPressed:   () => Get.toNamed(AppRoutes.expenseAdd),
            icon:        const Icon(Icons.add),
            label:       Text('Add Expense',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            backgroundColor: BillifyColors.accent,
            foregroundColor: BillifyColors.textPrimary,
            elevation:   3,
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            heroTag:     'fab_invoice',
            onPressed:   () => Get.toNamed(AppRoutes.invoiceCreate),
            icon:        const Icon(Icons.receipt_long_rounded),
            label:       Text('New Invoice',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            backgroundColor: BillifyColors.primary,
            foregroundColor: Colors.white,
            elevation:   3,
          ),
        ],
      ),

      // ── Body ──
      body: Obx(() {
        if (ctrl.isLoading.value) {
          return const Center(
            child: CircularProgressIndicator(color: BillifyColors.primary),
          );
        }

        final d = ctrl.data.value;

        return RefreshIndicator(
          color:       BillifyColors.primary,
          onRefresh:   () async => ctrl.refresh(),
          child: CustomScrollView(
            slivers: [
              // ── Header banner ──
              SliverToBoxAdapter(
                child: _HeaderBanner(userName: ctrl.userName.value),
              ),

              // ── Summary Cards ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: d == null
                      ? const _EmptyState()
                      : GridView.count(
                    crossAxisCount:   2,
                    shrinkWrap:       true,
                    physics:          const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing:  12,
                    childAspectRatio: 1.55,
                    children: [
                      _SummaryCard(
                        label:  'Total Revenue',
                        value:  fmt.format(d.totalRevenue),
                        icon:   Icons.trending_up_rounded,
                        color:  BillifyColors.paid,
                        bgColor: const Color(0xFFE8F5E9),
                      ),
                      _SummaryCard(
                        label:  'Pending',
                        value:  '${d.pendingCount} invoices',
                        icon:   Icons.hourglass_bottom_rounded,
                        color:  BillifyColors.overdue,
                        bgColor: const Color(0xFFFFF3E0),
                      ),
                      _SummaryCard(
                        label:  'Paid',
                        value:  '${d.paidCount} invoices',
                        icon:   Icons.check_circle_rounded,
                        color:  BillifyColors.primary,
                        bgColor: const Color(0xFFE8EAF6),
                      ),
                      _SummaryCard(
                        label:  'Net Balance',
                        value:  fmt.format(d.netBalance),
                        icon:   Icons.account_balance_wallet_rounded,
                        color:  d.netBalance >= 0 ? BillifyColors.paid : BillifyColors.unpaid,
                        bgColor: d.netBalance >= 0
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Bar Chart ──
              if (d != null && d.monthBars.isNotEmpty)
                SliverToBoxAdapter(
                  child: _BarChartCard(bars: d.monthBars),
                ),

              // ── Recent Invoices ──
              SliverToBoxAdapter(
                child: _RecentInvoicesSection(
                  invoices: d?.recent ?? [],
                  fmt:      fmt,
                ),
              ),

              // Bottom padding for FABs
              const SliverToBoxAdapter(child: SizedBox(height: 120)),
            ],
          ),
        );
      }),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  HEADER BANNER
// ────────────────────────────────────────────────────────────
class _HeaderBanner extends StatelessWidget {
  final String userName;
  const _HeaderBanner({required this.userName});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  double.infinity,
      decoration: const BoxDecoration(
        color: BillifyColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft:  Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_greeting()}, ${userName.isEmpty ? 'there' : userName} 👋',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
            style: GoogleFonts.nunito(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  SUMMARY CARD
// ────────────────────────────────────────────────────────────
class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color  color;
  final Color  bgColor;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color:      BillifyColors.primary.withOpacity(0.07),
            blurRadius: 10,
            offset:     const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:  MainAxisAlignment.spaceBetween,
        children: [
          // Icon badge
          Container(
            padding:     const EdgeInsets.all(8),
            decoration:  BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          // Values
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize:   15,
                  fontWeight: FontWeight.w700,
                  color:      BillifyColors.textPrimary,
                ),
              ),
              Text(
                label,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  color:    BillifyColors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  BAR CHART CARD — income vs expense, last 4 months
// ────────────────────────────────────────────────────────────
class _BarChartCard extends StatelessWidget {
  final List<_MonthBar> bars;
  const _BarChartCard({required this.bars});

  @override
  Widget build(BuildContext context) {
    final maxY = bars
        .map((b) => b.income > b.expense ? b.income : b.expense)
        .fold(0.0, (a, b) => a > b ? a : b);
    final chartMax = maxY == 0 ? 1000.0 : (maxY * 1.3).ceilToDouble();

    return Container(
      margin:  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color:      BillifyColors.primary.withOpacity(0.07),
            blurRadius: 10,
            offset:     const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + legend
          Row(
            children: [
              Text(
                'Income vs Expense',
                style: GoogleFonts.poppins(
                  fontSize:   15,
                  fontWeight: FontWeight.w600,
                  color:      BillifyColors.textPrimary,
                ),
              ),
              const Spacer(),
              _LegendDot(color: BillifyColors.paid,   label: 'Income'),
              const SizedBox(width: 12),
              _LegendDot(color: BillifyColors.unpaid, label: 'Expense'),
            ],
          ),
          const SizedBox(height: 16),

          // Chart
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY:           chartMax,
                minY:           0,
                gridData:       FlGridData(
                  show:               true,
                  drawVerticalLine:   false,
                  horizontalInterval: chartMax / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color:       BillifyColors.divider,
                    strokeWidth: 1,
                  ),
                ),
                borderData:  FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles:   AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles:  AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles:    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles:   true,
                      reservedSize: 28,
                      getTitlesWidget: (value, _) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= bars.length) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            bars[idx].label,
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              color:    BillifyColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: List.generate(bars.length, (i) {
                  final b = bars[i];
                  return BarChartGroupData(
                    x:            i,
                    barRods: [
                      BarChartRodData(
                        toY:          b.income,
                        color:        BillifyColors.paid,
                        width:        12,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                      BarChartRodData(
                        toY:          b.expense,
                        color:        BillifyColors.unpaid.withOpacity(0.75),
                        width:        12,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ],
                    barsSpace: 4,
                  );
                }),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, _, rod, rodIndex) {
                      final label = rodIndex == 0 ? 'Income' : 'Expense';
                      final fmt = NumberFormat.compactCurrency(
                          locale: 'en_IN', symbol: '₹', decimalDigits: 0);
                      return BarTooltipItem(
                        '$label\n${fmt.format(rod.toY)}',
                        GoogleFonts.nunito(
                          color:      Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize:   12,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10, height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.nunito(
                fontSize: 12, color: BillifyColors.textSecondary)),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
//  RECENT INVOICES SECTION
// ────────────────────────────────────────────────────────────
class _RecentInvoicesSection extends StatelessWidget {
  final List<_RecentInvoice> invoices;
  final NumberFormat         fmt;
  const _RecentInvoicesSection({required this.invoices, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            children: [
              Text(
                'Recent Invoices',
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600,
                  color: BillifyColors.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Get.toNamed(AppRoutes.invoices),
                child: Text(
                  'See all',
                  style: GoogleFonts.nunito(
                    color: BillifyColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // List
          if (invoices.isEmpty)
            _EmptyInvoiceState()
          else
            ListView.separated(
              shrinkWrap: true,
              physics:    const NeverScrollableScrollPhysics(),
              itemCount:  invoices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _InvoiceCard(
                invoice: invoices[i],
                fmt:     fmt,
              ),
            ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  INVOICE CARD (recent)
// ────────────────────────────────────────────────────────────
class _InvoiceCard extends StatelessWidget {
  final _RecentInvoice invoice;
  final NumberFormat   fmt;
  const _InvoiceCard({required this.invoice, required this.fmt});

  Color _statusColor(String s) {
    switch (s) {
      case 'paid':    return BillifyColors.paid;
      case 'unpaid':  return BillifyColors.unpaid;
      case 'overdue': return BillifyColors.overdue;
      default:        return BillifyColors.draft;
    }
  }

  Color _statusBg(String s) {
    switch (s) {
      case 'paid':    return const Color(0xFFE8F5E9);
      case 'unpaid':  return const Color(0xFFFFEBEE);
      case 'overdue': return const Color(0xFFFFF3E0);
      default:        return const Color(0xFFF5F5F5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Get.toNamed(
        AppRoutes.invoiceDetail,
        arguments: {'invoiceId': invoice.invoiceId},
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color:      BillifyColors.primary.withOpacity(0.06),
              blurRadius: 8,
              offset:     const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left icon
            Container(
              width:  44,
              height: 44,
              decoration: BoxDecoration(
                color:        BillifyColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: BillifyColors.primary,
                size:  22,
              ),
            ),
            const SizedBox(width: 12),

            // Invoice info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoice.clientName.isEmpty ? 'Unknown Client' : invoice.clientName,
                    style: GoogleFonts.poppins(
                      fontSize:   14,
                      fontWeight: FontWeight.w600,
                      color:      BillifyColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${invoice.invoiceNumber}  •  '
                        '${DateFormat('d MMM yyyy').format(invoice.date)}',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      color:    BillifyColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Amount + status badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  fmt.format(invoice.totalAmount),
                  style: GoogleFonts.poppins(
                    fontSize:   14,
                    fontWeight: FontWeight.w700,
                    color:      BillifyColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:        _statusBg(invoice.status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    invoice.status[0].toUpperCase() + invoice.status.substring(1),
                    style: GoogleFonts.nunito(
                      fontSize:   11,
                      fontWeight: FontWeight.w700,
                      color:      _statusColor(invoice.status),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  EMPTY STATES
// ────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Center(
      child: Text(
        'No data yet. Create your first invoice!',
        style: GoogleFonts.nunito(color: BillifyColors.textSecondary),
        textAlign: TextAlign.center,
      ),
    ),
  );
}

class _EmptyInvoiceState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding:     const EdgeInsets.all(28),
      decoration:  BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 52, color: BillifyColors.primary.withOpacity(0.25)),
          const SizedBox(height: 12),
          Text(
            'No invoices yet',
            style: GoogleFonts.poppins(
              fontSize: 15, fontWeight: FontWeight.w600,
              color: BillifyColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "New Invoice" to create your first invoice',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 13, color: BillifyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 160,
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () => Get.toNamed(AppRoutes.invoiceCreate),
              icon:  const Icon(Icons.add, size: 18),
              label: Text('New Invoice',
                  style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                minimumSize: Size.zero,
                padding:     const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}