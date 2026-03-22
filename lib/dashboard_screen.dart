// ════════════════════════════════════════════════════════════
//  dashboard_screen.dart — Billify Phase 2
//  Full Dashboard with summary cards, bar chart, recent invoices
//  and quick-action FABs. Reads live data from Firestore.
// ════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import 'main.dart' show BillifyColors, AppRoutes, BillifyDrawer, AppSettings,
BillifyDialog;
import 'expense_screens.dart' show ExpenseListScreen, AddExpenseScreen;

// ────────────────────────────────────────────────────────────
//  DATA MODELS (lightweight, dashboard-only)
// ────────────────────────────────────────────────────────────
class _DashboardData {
  final double totalRevenue;
  final int    pendingCount;
  final int    paidCount;
  final double totalExpense;   // from expenses collection
  final double netBalance;
  final List<_MonthBar> monthBars;   // last 4 months
  final List<_RecentInvoice> recent; // last 5 invoices

  const _DashboardData({
    required this.totalRevenue,
    required this.pendingCount,
    required this.paidCount,
    required this.totalExpense,
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
//  DASHBOARD SCREEN  — pure StreamBuilder, no GetX controller
// ────────────────────────────────────────────────────────────
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  // Combine invoice + expense snapshots into dashboard metrics
  static _DashboardData _compute(
      QuerySnapshot invoiceSnap, QuerySnapshot expenseSnap) {
    double totalRevenue = 0;
    int    pendingCount = 0;
    int    paidCount    = 0;
    final  List<_RecentInvoice> allInvoices = [];

    final now = DateTime.now();
    final Map<String, double> incomeByMonth  = {};
    final Map<String, double> expenseByMonth = {};
    for (int i = 3; i >= 0; i--) {
      final m   = DateTime(now.year, now.month - i, 1);
      final key = DateFormat('MMM').format(m);
      incomeByMonth[key]  = 0;
      expenseByMonth[key] = 0;
    }

    // Process invoices
    for (final doc in invoiceSnap.docs) {
      final d      = doc.data() as Map<String, dynamic>;
      final status = (d['status'] ?? 'draft') as String;
      final amount = ((d['totalAmount'] ?? 0) as num).toDouble();
      final ts     = (d['createdAt'] ?? d['orderDate'] ?? d['invoiceDate'])
      as Timestamp?;
      final date   = ts?.toDate() ?? DateTime.now();

      if (status == 'paid')   { totalRevenue += amount; paidCount++; }
      if (status == 'unpaid' || status == 'overdue') pendingCount++;

      final mKey = DateFormat('MMM').format(date);
      if (incomeByMonth.containsKey(mKey) && status == 'paid') {
        incomeByMonth[mKey] = incomeByMonth[mKey]! + amount;
      }

      allInvoices.add(_RecentInvoice(
        invoiceId:     doc.id,
        invoiceNumber: (d['invoiceNumber'] ?? '') as String,
        clientName:    (d['clientName']    ?? '') as String,
        totalAmount:   amount,
        status:        status,
        date:          date,
      ));
    }

    // Process expense / income entries
    double totalExpense = 0;
    for (final doc in expenseSnap.docs) {
      final d    = doc.data() as Map<String, dynamic>;
      final type = (d['type'] ?? 'expense') as String;
      final amt  = ((d['netAmount'] ?? d['amount'] ?? 0) as num).toDouble();
      final ts   = (d['date'] ?? d['createdAt']) as Timestamp?;
      final date = ts?.toDate() ?? DateTime.now();
      final mKey = DateFormat('MMM').format(date);

      if (type == 'expense') {
        totalExpense += amt;
        if (expenseByMonth.containsKey(mKey)) {
          expenseByMonth[mKey] = expenseByMonth[mKey]! + amt;
        }
      } else if (type == 'income') {
        if (incomeByMonth.containsKey(mKey)) {
          incomeByMonth[mKey] = incomeByMonth[mKey]! + amt;
        }
      }
    }

    allInvoices.sort((a, b) => b.date.compareTo(a.date));
    final monthBars = incomeByMonth.keys
        .map((k) => _MonthBar(k, incomeByMonth[k]!, expenseByMonth[k]!))
        .toList();

    return _DashboardData(
      totalRevenue: totalRevenue,
      pendingCount: pendingCount,
      paidCount:    paidCount,
      totalExpense: totalExpense,
      netBalance:   totalRevenue - totalExpense,
      monthBars:    monthBars,
      recent:       allInvoices.take(5).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final fmt = AppSettings.currencyFmt();

    // ── Invoice stream ──
    final invoiceStream = FirebaseFirestore.instance
        .collection('users').doc(uid).collection('invoices')
        .orderBy('createdAt', descending: true)
        .snapshots();

    // ── Expense / income stream ──
    final expenseStream = FirebaseFirestore.instance
        .collection('users').doc(uid).collection('expenses')
        .orderBy('date', descending: true)
        .snapshots();

    // ── User profile stream (for greeting) ──
    final userStream = FirebaseFirestore.instance
        .collection('users').doc(uid)
        .snapshots();

    return PopScope(
      // Intercept back — show exit dialog instead of closing app
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => BillifyDialog(
            icon:         Icons.exit_to_app_rounded,
            iconColor:    BillifyColors.primary,
            title:        'Exit Billify?',
            body:         'Are you sure you want to exit the app?',
            confirmLabel: 'Exit',
            confirmColor: BillifyColors.unpaid,
            onConfirm:    () => Navigator.of(ctx).pop(true),
          ),
        );
        if (shouldExit == true) {
          // Actually exit the app
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: BillifyColors.background,
        drawer: const BillifyDrawer(activeRoute: AppRoutes.dashboard),

        // ── AppBar ──
        appBar: AppBar(
          backgroundColor: BillifyColors.primary,
          elevation: 0,
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.white),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          title: Text(
            'Billify',
            style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          actions: [
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
              heroTag:         'fab_expense',
              onPressed:       () => Get.toNamed(AppRoutes.expenseAdd),
              icon:            const Icon(Icons.add),
              label:           Text('Add Expense',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              backgroundColor: BillifyColors.accent,
              foregroundColor: BillifyColors.textPrimary,
              elevation:       3,
            ),
            const SizedBox(height: 10),
            FloatingActionButton.extended(
              heroTag:         'fab_invoice',
              onPressed:       () => Get.toNamed(AppRoutes.invoiceCreate),
              icon:            const Icon(Icons.receipt_long_rounded),
              label:           Text('New Invoice',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              backgroundColor: BillifyColors.primary,
              foregroundColor: Colors.white,
              elevation:       3,
            ),
          ],
        ),

        // ── Body: nested StreamBuilders (invoices + expenses + user) ──
        body: StreamBuilder<QuerySnapshot>(
          stream: invoiceStream,
          builder: (context, invoiceSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: expenseStream,
              builder: (context, expenseSnap) {

                // Compute dashboard data when both snapshots are ready
                final _DashboardData? d =
                (invoiceSnap.hasData && expenseSnap.hasData)
                    ? _compute(invoiceSnap.data!, expenseSnap.data!)
                    : invoiceSnap.hasData
                    ? _compute(invoiceSnap.data!,
                    expenseSnap.data ?? const _EmptyQuerySnapshot())
                    : null;

                return StreamBuilder<DocumentSnapshot>(
                  stream: userStream,
                  builder: (context, userSnap) {
                    final userData =
                        userSnap.data?.data() as Map<String, dynamic>? ?? {};
                    final authUser = FirebaseAuth.instance.currentUser;
                    final fullName = (userData['fullName'] as String?)
                        ?? authUser?.displayName ?? '';
                    final userName = fullName.isNotEmpty
                        ? fullName.split(' ').first : '';

                    // First load — show spinner
                    if (invoiceSnap.connectionState == ConnectionState.waiting &&
                        !invoiceSnap.hasData) {
                      return const Center(
                          child: CircularProgressIndicator(
                              color: BillifyColors.primary));
                    }

                    return RefreshIndicator(
                      color: BillifyColors.primary,
                      onRefresh: () async {
                        await Future.delayed(
                            const Duration(milliseconds: 400));
                      },
                      child: CustomScrollView(
                        slivers: [
                          // ── Header banner ──
                          SliverToBoxAdapter(
                            child: _HeaderBanner(userName: userName),
                          ),

                          // ── Summary Cards (6-card grid) ──
                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                              const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              child: d == null
                                  ? const _EmptyState()
                                  : Column(
                                children: [
                                  // Row 1
                                  Row(children: [
                                    Expanded(
                                      child: _SummaryCard(
                                        label:   'Total Revenue',
                                        value:   fmt.format(d.totalRevenue),
                                        icon:    Icons.trending_up_rounded,
                                        color:   BillifyColors.paid,
                                        bgColor: const Color(0xFFE8F5E9),
                                        onTap: () => Get.toNamed(AppRoutes.invoices,
                                            arguments: {'filter': 'paid_only'}),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _SummaryCard(
                                        label:   'Total Expenses',
                                        value:   fmt.format(d.totalExpense),
                                        icon:    Icons.arrow_upward_rounded,
                                        color:   BillifyColors.unpaid,
                                        bgColor: const Color(0xFFFFEBEE),
                                        onTap: () => Get.toNamed(AppRoutes.expenses),
                                      ),
                                    ),
                                  ]),
                                  const SizedBox(height: 12),
                                  // Row 2
                                  Row(children: [
                                    Expanded(
                                      child: _SummaryCard(
                                        label:   'Net Balance',
                                        value:   fmt.format(d.netBalance),
                                        icon:    Icons.account_balance_wallet_rounded,
                                        color:   d.netBalance >= 0
                                            ? BillifyColors.paid
                                            : BillifyColors.unpaid,
                                        bgColor: d.netBalance >= 0
                                            ? const Color(0xFFE8F5E9)
                                            : const Color(0xFFFFEBEE),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _SummaryCard(
                                        label:   'Pending',
                                        value:   '${d.pendingCount} invoices',
                                        icon:    Icons.hourglass_bottom_rounded,
                                        color:   BillifyColors.overdue,
                                        bgColor: const Color(0xFFFFF3E0),
                                        onTap: () => Get.toNamed(AppRoutes.invoices,
                                            arguments: {'filter': 'pending_only'}),
                                      ),
                                    ),
                                  ]),
                                  const SizedBox(height: 12),
                                  // Row 3
                                  Row(children: [
                                    Expanded(
                                      child: _SummaryCard(
                                        label:   'Paid Invoices',
                                        value:   '${d.paidCount} invoices',
                                        icon:    Icons.check_circle_rounded,
                                        color:   BillifyColors.primary,
                                        bgColor: const Color(0xFFE8EAF6),
                                        onTap: () => Get.toNamed(AppRoutes.invoices,
                                            arguments: {'filter': 'paid_only'}),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _SummaryCard(
                                        label:   'Expenses & Income',
                                        value:   'View All',
                                        icon:    Icons.bar_chart_rounded,
                                        color:   BillifyColors.primaryLight,
                                        bgColor: const Color(0xFFEDE7F6),
                                        onTap: () => Get.toNamed(AppRoutes.expenses),
                                      ),
                                    ),
                                  ]),
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
                          const SliverToBoxAdapter(
                              child: SizedBox(height: 120)),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ), // Scaffold
    ); // PopScope
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
  final String    label;
  final String    value;
  final IconData  icon;
  final Color     color;
  final Color     bgColor;
  final VoidCallback? onTap;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:    const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: bgColor, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 20),
                ),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded,
                      size: 16, color: BillifyColors.textSecondary.withOpacity(0.5)),
              ],
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
                      final fmt = AppSettings.currencyFmt();
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
//  SHARED STATUS HELPERS  (used by dashboard + invoice list)
// ────────────────────────────────────────────────────────────
Color invoiceStatusColor(String s) {
  switch (s) {
    case 'paid':    return BillifyColors.paid;
    case 'unpaid':  return BillifyColors.unpaid;
    case 'overdue': return BillifyColors.overdue;
    default:        return BillifyColors.draft;
  }
}

Color invoiceStatusBg(String s) {
  switch (s) {
    case 'paid':    return const Color(0xFFE8F5E9);
    case 'unpaid':  return const Color(0xFFFFEBEE);
    case 'overdue': return const Color(0xFFFFF3E0);
    default:        return const Color(0xFFF5F5F5);
  }
}

IconData invoiceStatusIcon(String s) {
  switch (s) {
    case 'paid':    return Icons.check_circle_rounded;
    case 'unpaid':  return Icons.schedule_rounded;
    case 'overdue': return Icons.warning_amber_rounded;
    default:        return Icons.edit_rounded;
  }
}

/// Shows a bottom sheet to change invoice status, then writes to Firestore.
Future<void> showStatusPicker(BuildContext context, String invoiceId, String current) async {
  final statuses = ['draft', 'unpaid', 'paid', 'overdue'];
  await showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _StatusPickerSheet(
      invoiceId: invoiceId,
      current:   current,
      statuses:  statuses,
    ),
  );
}

class _StatusPickerSheet extends StatefulWidget {
  final String       invoiceId;
  final String       current;
  final List<String> statuses;
  const _StatusPickerSheet({
    required this.invoiceId,
    required this.current,
    required this.statuses,
  });
  @override
  State<_StatusPickerSheet> createState() => _StatusPickerSheetState();
}

class _StatusPickerSheetState extends State<_StatusPickerSheet> {
  late String _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  Future<void> _apply() async {
    if (_selected == widget.current) { Navigator.of(context).pop(); return; }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('invoices').doc(widget.invoiceId)
          .update({'status': _selected});
      if (mounted) Navigator.of(context).pop();
      Get.snackbar(
        'Status Updated',
        'Invoice marked as ${_selected[0].toUpperCase()}${_selected.substring(1)}',
        backgroundColor: invoiceStatusColor(_selected),
        colorText:       Colors.white,
        snackPosition:   SnackPosition.TOP,
        duration:        const Duration(seconds: 2),
      );
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      Get.snackbar('Error', 'Could not update status',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: BillifyColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: BillifyColors.primary.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.swap_horiz_rounded,
                        color: BillifyColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Change Status',
                          style: GoogleFonts.poppins(
                              fontSize: 16, fontWeight: FontWeight.w700,
                              color: BillifyColors.textPrimary)),
                      Text('Select a status below, then tap Apply',
                          style: GoogleFonts.nunito(
                              fontSize: 12, color: BillifyColors.textSecondary)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Status options
              ...widget.statuses.map((s) {
                final isActive = _selected == s;
                return GestureDetector(
                  onTap: () => setState(() => _selected = s),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: isActive
                          ? invoiceStatusBg(s)
                          : BillifyColors.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isActive
                            ? invoiceStatusColor(s)
                            : BillifyColors.divider,
                        width: isActive ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: invoiceStatusBg(s),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(invoiceStatusIcon(s),
                              color: invoiceStatusColor(s), size: 16),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            s[0].toUpperCase() + s.substring(1),
                            style: GoogleFonts.poppins(
                              fontSize:   14,
                              fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                              color: isActive
                                  ? invoiceStatusColor(s)
                                  : BillifyColors.textPrimary,
                            ),
                          ),
                        ),
                        if (isActive)
                          Icon(Icons.check_circle_rounded,
                              color: invoiceStatusColor(s), size: 20),
                        if (s == widget.current && !isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: BillifyColors.divider,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text('current',
                                style: GoogleFonts.nunito(
                                    fontSize: 10,
                                    color: BillifyColors.textSecondary,
                                    fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                  ),
                );
              }),

              const SizedBox(height: 4),

              // Apply button
              const SizedBox(height: 4),
              _saving
                  ? const Center(
                  child: CircularProgressIndicator(color: BillifyColors.primary))
                  : ElevatedButton.icon(
                onPressed: _apply,
                icon:  const Icon(Icons.check_rounded),
                label: Text('Apply',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selected == widget.current
                      ? BillifyColors.textSecondary
                      : invoiceStatusColor(_selected),
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ),
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Get.toNamed(
        AppRoutes.invoiceDetail,
        arguments: {'invoiceId': invoice.invoiceId},
      ),
      child: Container(
        padding: EdgeInsets.all(AppSettings.compactCards ? 10 : 14),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(AppSettings.compactCards ? 12 : 14),
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
                        '${AppSettings.formatDate(invoice.date)}',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      color:    BillifyColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Amount + tappable status badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (AppSettings.showAmountOnList)
                  Text(
                    fmt.format(invoice.totalAmount),
                    style: GoogleFonts.poppins(
                      fontSize:   14,
                      fontWeight: FontWeight.w700,
                      color:      BillifyColors.textPrimary,
                    ),
                  ),
                if (AppSettings.showAmountOnList)
                  const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => showStatusPicker(
                      context, invoice.invoiceId, invoice.status),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:        invoiceStatusBg(invoice.status),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: invoiceStatusColor(invoice.status).withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          invoice.status[0].toUpperCase() + invoice.status.substring(1),
                          style: GoogleFonts.nunito(
                            fontSize:   11,
                            fontWeight: FontWeight.w700,
                            color:      invoiceStatusColor(invoice.status),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.expand_more_rounded,
                            size: 13,
                            color: invoiceStatusColor(invoice.status)),
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

// ─────────────────────────────────────────────────────────────
//  EMPTY QUERY SNAPSHOT — used as placeholder while expense
//  stream hasn't emitted yet, so dashboard renders immediately.
// ─────────────────────────────────────────────────────────────
class _EmptyQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  const _EmptyQuerySnapshot();

  @override List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];
  @override List<DocumentChange<Map<String, dynamic>>>  get docChanges => [];
  @override SnapshotMetadata get metadata => _EmptyMetadata();
  @override int get size => 0;

  @override
  bool operator ==(Object other) => other is _EmptyQuerySnapshot;
  @override
  int get hashCode => 0;
}

class _EmptyMetadata implements SnapshotMetadata {
  @override bool get hasPendingWrites => false;
  @override bool get isFromCache      => true;
}