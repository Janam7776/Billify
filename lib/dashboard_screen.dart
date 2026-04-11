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

import 'main.dart'
    show
    BillifyColors,
    AppRoutes,
    BillifyDrawer,
    AppSettings,
    BillifyC,
    BillifyDialog;
import 'expense_screens.dart' show ExpenseListScreen, AddExpenseScreen;
import 'client_screens.dart' show DashboardRecentClients;
import 'web_layout.dart' show WebScaffold;

// ────────────────────────────────────────────────────────────
//  DATA MODELS (lightweight, dashboard-only)
// ────────────────────────────────────────────────────────────

class _DashboardData {
  final double totalRevenue;
  final int pendingCount;
  final int paidCount;
  final double totalExpense;
  final double netBalance;
  final List<_MonthBar> monthBars;
  final List<_RecentInvoice> recent;

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
  final String label;
  final double income;
  final double expense;
  const _MonthBar(this.label, this.income, this.expense);
}

class _RecentInvoice {
  final String invoiceNumber;
  final String clientName;
  final double totalAmount;
  final String status;
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
//  DASHBOARD SCREEN
// ────────────────────────────────────────────────────────────

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static _DashboardData _compute(
      QuerySnapshot invoiceSnap,
      QuerySnapshot expenseSnap,
      ) {
    double totalRevenue = 0;
    int pendingCount = 0;
    int paidCount = 0;
    final List<_RecentInvoice> allInvoices = [];

    final now = DateTime.now();
    final Map<String, double> incomeByMonth = {};
    final Map<String, double> expenseByMonth = {};

    for (int i = 3; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i, 1);
      final key = DateFormat('MMM').format(m);
      incomeByMonth[key] = 0;
      expenseByMonth[key] = 0;
    }

    for (final doc in invoiceSnap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final status = (d['status'] ?? 'draft') as String;
      final amount = ((d['totalAmount'] ?? 0) as num).toDouble();
      final ts =
      (d['createdAt'] ?? d['orderDate'] ?? d['invoiceDate']) as Timestamp?;
      final date = ts?.toDate() ?? DateTime.now();

      if (status == 'paid') {
        totalRevenue += amount;
        paidCount++;
      }
      if (status == 'unpaid' || status == 'overdue') pendingCount++;

      final mKey = DateFormat('MMM').format(date);
      if (incomeByMonth.containsKey(mKey) && status == 'paid') {
        incomeByMonth[mKey] = incomeByMonth[mKey]! + amount;
      }

      allInvoices.add(_RecentInvoice(
        invoiceId: doc.id,
        invoiceNumber: (d['invoiceNumber'] ?? '') as String,
        clientName: (d['clientName'] ?? '') as String,
        totalAmount: amount,
        status: status,
        date: date,
      ));
    }

    double totalExpense = 0;
    for (final doc in expenseSnap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final type = (d['type'] ?? 'expense') as String;
      final amt = ((d['netAmount'] ?? d['amount'] ?? 0) as num).toDouble();
      final ts = (d['date'] ?? d['createdAt']) as Timestamp?;
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
      paidCount: paidCount,
      totalExpense: totalExpense,
      netBalance: totalRevenue - totalExpense,
      monthBars: monthBars,
      recent: allInvoices.take(5).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final fmt = AppSettings.currencyFmt();

    final invoiceStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('invoices')
        .orderBy('createdAt', descending: true)
        .snapshots();

    final expenseStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('expenses')
        .orderBy('date', descending: true)
        .snapshots();

    final userStream =
    FirebaseFirestore.instance.collection('users').doc(uid).snapshots();

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => BillifyDialog(
            icon: Icons.exit_to_app_rounded,
            iconColor: BillifyColors.primary,
            title: 'Exit Billify?',
            body: 'Are you sure you want to exit the app?',
            confirmLabel: 'Exit',
            confirmColor: BillifyColors.unpaid,
            onConfirm: () => Navigator.of(ctx).pop(true),
          ),
        );
        if (shouldExit == true) {
          SystemNavigator.pop();
        }
      },
      child: WebScaffold(
        activeRoute: AppRoutes.dashboard,
        appBar: _buildAppBar(),
        floatingActionButton: _buildFABs(),
        body: _buildBody(
          context: context,
          fmt: fmt,
          invoiceStream: invoiceStream,
          expenseStream: expenseStream,
          userStream: userStream,
        ),
      ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: BillifyColors.background,
      elevation: 0,
      // hamburger is auto-provided by Scaffold on mobile;
      // on desktop WebScaffold renders no Scaffold so no hamburger appears.
      title: Text(
        'DASHBOARD',
        style: GoogleFonts.poppins(
          color: BillifyColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.0,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: BillifyColors.outlineVariant.withOpacity(0.4)),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: BillifyColors.textSecondary, size: 20),
          onPressed: () {},
        ),
      ],
    );
  }

  // ── FABs ────────────────────────────────────────────────────

  Widget _buildFABs() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: 'fab_expense',
          onPressed: () => Get.toNamed(AppRoutes.expenseAdd),
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            'ADD EXPENSE',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.2),
          ),
          backgroundColor: BillifyColors.surfaceHigh,
          foregroundColor: BillifyColors.textPrimary,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
          heroTag: 'fab_invoice',
          onPressed: () => Get.toNamed(AppRoutes.invoiceCreate),
          icon: const Icon(Icons.receipt_long_rounded, size: 18),
          label: Text(
            'NEW INVOICE',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.2),
          ),
          backgroundColor: BillifyColors.primary,
          foregroundColor: const Color(0xFFF7F7FF),
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ],
    );
  }

  // ── Body ────────────────────────────────────────────────────

  Widget _buildBody({
    required BuildContext context,
    required NumberFormat fmt,
    required Stream<QuerySnapshot> invoiceStream,
    required Stream<QuerySnapshot> expenseStream,
    required Stream<DocumentSnapshot> userStream,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: invoiceStream,
      builder: (context, invoiceSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: expenseStream,
          builder: (context, expenseSnap) {
            final _DashboardData? d =
            (invoiceSnap.hasData && expenseSnap.hasData)
                ? _compute(invoiceSnap.data!, expenseSnap.data!)
                : invoiceSnap.hasData
                ? _compute(
              invoiceSnap.data!,
              expenseSnap.data ??
                  const _EmptyQuerySnapshot(),
            )
                : null;

            return StreamBuilder<DocumentSnapshot>(
              stream: userStream,
              builder: (context, userSnap) {
                final userData =
                    userSnap.data?.data() as Map<String, dynamic>? ?? {};
                final authUser = FirebaseAuth.instance.currentUser;
                final fullName = (userData['fullName'] as String?) ??
                    authUser?.displayName ??
                    '';
                final userName =
                fullName.isNotEmpty ? fullName.split(' ').first : '';

                if (invoiceSnap.connectionState == ConnectionState.waiting &&
                    !invoiceSnap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: BillifyColors.primary,
                    ),
                  );
                }

                return RefreshIndicator(
                  color: BillifyColors.primary,
                  onRefresh: () async {
                    await Future.delayed(const Duration(milliseconds: 400));
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _HeaderBanner(userName: userName),
                      ),
                      SliverToBoxAdapter(
                        child: _SummaryCardsSection(d: d, fmt: fmt),
                      ),
                      if (d != null && d.monthBars.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _BarChartCard(bars: d.monthBars),
                        ),
                      SliverToBoxAdapter(
                        child: _RecentInvoicesSection(
                          invoices: d?.recent ?? [],
                          fmt: fmt,
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: DashboardRecentClients(),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 120),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────
//  SUMMARY CARDS SECTION
// ────────────────────────────────────────────────────────────

class _SummaryCardsSection extends StatelessWidget {
  final _DashboardData? d;
  final NumberFormat fmt;

  const _SummaryCardsSection({required this.d, required this.fmt});

  @override
  Widget build(BuildContext context) {
    if (d == null) return const _EmptyState();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(width: 3, height: 14, color: BillifyColors.primary),
                const SizedBox(width: 8),
                Text(
                  'FISCAL SUMMARY',
                  style: GoogleFonts.poppins(
                    fontSize: 9, fontWeight: FontWeight.w800,
                    letterSpacing: 1.8, color: BillifyColors.primary,
                  ),
                ),
              ],
            ),
          ),
          // Bento grid — gap: 1px for seamless ledger look
          Column(
            children: [
              // Row 1
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _SummaryCard(
                        label: 'Total Revenue',
                        value: fmt.format(d!.totalRevenue),
                        icon: Icons.trending_up_rounded,
                        color: BillifyColors.paid,
                        bgColor: const Color(0xFFE8F5E9),
                        onTap: () => Get.toNamed(AppRoutes.invoices, arguments: {'filter': 'paid_only'}),
                      ),
                    ),
                    const SizedBox(width: 1),
                    Expanded(
                      flex: 2,
                      child: _SummaryCard(
                        label: 'Pending',
                        value: '${d!.pendingCount} inv.',
                        icon: Icons.hourglass_bottom_rounded,
                        color: BillifyColors.overdue,
                        bgColor: const Color(0xFFFFF3E0),
                        onTap: () => Get.toNamed(AppRoutes.invoices, arguments: {'filter': 'pending_only'}),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              // Row 2
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: 'Total Expenses',
                        value: fmt.format(d!.totalExpense),
                        icon: Icons.arrow_upward_rounded,
                        color: BillifyColors.unpaid,
                        bgColor: const Color(0xFFFFEBEE),
                        onTap: () => Get.toNamed(AppRoutes.expenses),
                      ),
                    ),
                    const SizedBox(width: 1),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Net Balance',
                        value: fmt.format(d!.netBalance),
                        icon: Icons.account_balance_wallet_rounded,
                        color: d!.netBalance >= 0 ? BillifyColors.paid : BillifyColors.unpaid,
                        bgColor: d!.netBalance >= 0 ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                      ),
                    ),
                    const SizedBox(width: 1),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Paid Invoices',
                        value: '${d!.paidCount} inv.',
                        icon: Icons.check_circle_rounded,
                        color: BillifyColors.primary,
                        bgColor: const Color(0xFFE8EAF6),
                        onTap: () => Get.toNamed(AppRoutes.invoices, arguments: {'filter': 'paid_only'}),
                      ),
                    ),
                  ],
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
      width: double.infinity,
      color: BillifyColors.primary,
      child: Stack(
        children: [
          // Architectural dot grid
          Positioned.fill(
            child: CustomPaint(painter: _DashGridPainter()),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Operational status label
                Text(
                  'OPERATIONAL STATUS',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFF7F7FF).withOpacity(0.5),
                    fontSize: 8, fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 6),
                // Large editorial headline
                Text(
                  userName.isEmpty
                      ? 'Fiscal Summary.'
                      : '${_greeting()},\n${userName.split(' ').first}.',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFF7F7FF),
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()).toUpperCase(),
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFF7F7FF).withOpacity(0.55),
                    fontSize: 9, fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
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

// Dot grid painter for dashboard header
class _DashGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF7F7FF).withOpacity(0.06)
      ..strokeWidth = 1;
    const spacing = 20.0;
    for (double x = 0; x <= size.width; x += spacing) {
      for (double y = 0; y <= size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.8, paint);
      }
    }
  }
  @override
  bool shouldRepaint(_DashGridPainter old) => false;
}

// ────────────────────────────────────────────────────────────
//  SUMMARY CARD
// ────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;
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
          color: BillifyColors.surface,
          border: Border(
            top: BorderSide(color: color, width: 2),
            left: BorderSide(color: BillifyColors.outlineVariant.withOpacity(0.3), width: 0.5),
            right: BorderSide(color: BillifyColors.outlineVariant.withOpacity(0.3), width: 0.5),
            bottom: BorderSide(color: BillifyColors.outlineVariant.withOpacity(0.3), width: 0.5),
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 18),
                if (onTap != null)
                  const Icon(Icons.arrow_forward_rounded, size: 12, color: BillifyColors.outlineVariant),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 15, fontWeight: FontWeight.w900,
                color: BillifyColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.poppins(
                fontSize: 8, fontWeight: FontWeight.w700,
                color: BillifyColors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  BAR CHART CARD
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
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: BillifyColors.surface,
        border: Border.all(color: BillifyColors.outlineVariant.withOpacity(0.3), width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartHeader(context),
          const SizedBox(height: 14),
          _buildChart(context, chartMax),
        ],
      ),
    );
  }

  Widget _buildChartHeader(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: BillifyColors.primary),
        const SizedBox(width: 8),
        Text(
          'INCOME VS EXPENSE',
          style: GoogleFonts.poppins(
            fontSize: 9, fontWeight: FontWeight.w800,
            letterSpacing: 1.8, color: BillifyColors.primary,
          ),
        ),
        const Spacer(),
        _LegendDot(color: BillifyColors.paid, label: 'Income'),
        const SizedBox(width: 12),
        _LegendDot(color: BillifyColors.unpaid, label: 'Expense'),
      ],
    );
  }

  Widget _buildChart(BuildContext context, double chartMax) {
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: chartMax,
          minY: 0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: chartMax / 4,
            getDrawingHorizontalLine: (_) => FlLine(
              color: Theme.of(context).dividerColor,
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
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
                        color:
                        Theme.of(context).colorScheme.onSurfaceVariant,
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
              x: i,
              barRods: [
                BarChartRodData(
                  toY: b.income,
                  color: BillifyColors.paid,
                  width: 12,
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
                ),
                BarChartRodData(
                  toY: b.expense,
                  color: BillifyColors.unpaid.withOpacity(0.75),
                  width: 12,
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
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
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 8, height: 8, color: color),
        const SizedBox(width: 4),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.poppins(
            fontSize: 8, fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: BillifyColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
//  RECENT INVOICES SECTION
// ────────────────────────────────────────────────────────────

class _RecentInvoicesSection extends StatelessWidget {
  final List<_RecentInvoice> invoices;
  final NumberFormat fmt;
  const _RecentInvoicesSection({required this.invoices, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(context),
          const SizedBox(height: 8),
          // Table header row
          if (invoices.isNotEmpty)
            Container(
              color: BillifyColors.surfaceContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Expanded(flex: 3, child: Text('CLIENT ENTITY', style: _hStyle())),
                Expanded(flex: 2, child: Text('AMOUNT', style: _hStyle(), textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text('STATUS', style: _hStyle(), textAlign: TextAlign.center)),
              ]),
            ),
          invoices.isEmpty
              ? _EmptyInvoiceState()
              : Column(
            children: invoices.map((inv) => _InvoiceCard(invoice: inv, fmt: fmt)).toList(),
          ),
        ],
      ),
    );
  }

  TextStyle _hStyle() => GoogleFonts.poppins(
      fontSize: 8, fontWeight: FontWeight.w800,
      letterSpacing: 1.2, color: BillifyColors.textSecondary);

  Widget _buildSectionHeader(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: BillifyColors.primary),
        const SizedBox(width: 8),
        Text(
          'RECENT LEDGER ENTRIES',
          style: GoogleFonts.poppins(
            fontSize: 9, fontWeight: FontWeight.w800,
            letterSpacing: 1.8, color: BillifyColors.primary,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => Get.toNamed(AppRoutes.invoices),
          child: Text(
            'VIEW ALL →',
            style: GoogleFonts.poppins(
              fontSize: 8, fontWeight: FontWeight.w800,
              letterSpacing: 1.2, color: BillifyColors.primary,
            ),
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
//  SHARED STATUS HELPERS
// ────────────────────────────────────────────────────────────

Color invoiceStatusColor(String s) {
  switch (s) {
    case 'paid':
      return BillifyColors.paid;
    case 'unpaid':
      return BillifyColors.unpaid;
    case 'overdue':
      return BillifyColors.overdue;
    default:
      return BillifyColors.draft;
  }
}

Color invoiceStatusBg(String s) {
  switch (s) {
    case 'paid':
      return const Color(0xFFE8F5E9);
    case 'unpaid':
      return const Color(0xFFFFEBEE);
    case 'overdue':
      return const Color(0xFFFFF3E0);
    default:
      return const Color(0xFFF5F5F5);
  }
}

IconData invoiceStatusIcon(String s) {
  switch (s) {
    case 'paid':
      return Icons.check_circle_rounded;
    case 'unpaid':
      return Icons.schedule_rounded;
    case 'overdue':
      return Icons.warning_amber_rounded;
    default:
      return Icons.edit_rounded;
  }
}

Future<void> showStatusPicker(
    BuildContext context,
    String invoiceId,
    String current,
    ) async {
  final statuses = ['draft', 'unpaid', 'paid', 'overdue'];
  await showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    builder: (ctx) => _StatusPickerSheet(
      invoiceId: invoiceId,
      current: current,
      statuses: statuses,
    ),
  );
}

class _StatusPickerSheet extends StatefulWidget {
  final String invoiceId;
  final String current;
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
    if (_selected == widget.current) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('invoices')
          .doc(widget.invoiceId)
          .update({'status': _selected});
      if (mounted) Navigator.of(context).pop();
      Get.snackbar(
        'Status Updated',
        'Invoice marked as ${_selected[0].toUpperCase()}${_selected.substring(1)}',
        backgroundColor: invoiceStatusColor(_selected),
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
        duration: const Duration(seconds: 2),
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
      color: BillifyColors.surface,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top accent bar
            Container(height: 3, color: BillifyColors.primary),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SETTLEMENT STATUS',
                    style: GoogleFonts.poppins(
                      fontSize: 10, fontWeight: FontWeight.w900,
                      letterSpacing: 2.0, color: BillifyColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select a status below, then tap Apply',
                    style: GoogleFonts.nunito(
                        fontSize: 12, color: BillifyColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  ...widget.statuses.map((s) {
                    final isActive = _selected == s;
                    return GestureDetector(
                      onTap: () => setState(() => _selected = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isActive ? invoiceStatusBg(s) : BillifyColors.surfaceLow,
                          border: Border(
                            left: BorderSide(
                              color: isActive ? invoiceStatusColor(s) : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(children: [
                          Icon(invoiceStatusIcon(s), color: invoiceStatusColor(s), size: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.toUpperCase(),
                              style: GoogleFonts.poppins(
                                fontSize: 10, fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: isActive ? invoiceStatusColor(s) : BillifyColors.textPrimary,
                              ),
                            ),
                          ),
                          if (s == widget.current)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              color: BillifyColors.outlineVariant.withOpacity(0.3),
                              child: Text('CURRENT',
                                  style: GoogleFonts.poppins(
                                      fontSize: 7, fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8, color: BillifyColors.textSecondary)),
                            ),
                          if (isActive && s != widget.current)
                            Icon(Icons.check_rounded, color: invoiceStatusColor(s), size: 16),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  if (_saving)
                    const Center(child: CircularProgressIndicator(color: BillifyColors.primary))
                  else
                    ElevatedButton(
                      onPressed: _apply,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selected == widget.current
                            ? BillifyColors.textSecondary
                            : invoiceStatusColor(_selected),
                        minimumSize: const Size(double.infinity, 48),
                        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                        elevation: 0,
                      ),
                      child: Text(
                        'APPLY STATUS',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.5),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  INVOICE CARD
// ────────────────────────────────────────────────────────────

class _InvoiceCard extends StatelessWidget {
  final _RecentInvoice invoice;
  final NumberFormat fmt;
  const _InvoiceCard({required this.invoice, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Get.toNamed(
        AppRoutes.invoiceDetail,
        arguments: {'invoiceId': invoice.invoiceId},
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: BillifyColors.surface,
          border: Border(
            left: BorderSide(color: invoiceStatusColor(invoice.status), width: 3),
            bottom: BorderSide(color: BillifyColors.outlineVariant.withOpacity(0.2), width: 0.5),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            // Client info
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invoice.clientName.isEmpty ? 'Unknown Client' : invoice.clientName,
                    style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w700,
                      color: BillifyColors.textPrimary,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${invoice.invoiceNumber}  ·  ${AppSettings.formatDate(invoice.date)}',
                    style: GoogleFonts.poppins(
                      fontSize: 8, color: BillifyColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            // Amount
            Expanded(
              flex: 2,
              child: Text(
                AppSettings.showAmountOnList ? fmt.format(invoice.totalAmount) : '—',
                style: GoogleFonts.poppins(
                  fontSize: 12, fontWeight: FontWeight.w800,
                  color: BillifyColors.textPrimary,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            // Status
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: () => showStatusPicker(context, invoice.invoiceId, invoice.status),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    color: invoiceStatusBg(invoice.status),
                    child: Text(
                      invoice.status.toUpperCase(),
                      style: GoogleFonts.poppins(
                        fontSize: 7, fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: invoiceStatusColor(invoice.status),
                      ),
                    ),
                  ),
                ),
              ),
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
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 3, height: 32,
              color: BillifyColors.outlineVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'NO LEDGER ENTRIES',
              style: GoogleFonts.poppins(
                fontSize: 9, fontWeight: FontWeight.w800,
                letterSpacing: 2.0, color: BillifyColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Create your first invoice to get started',
              style: GoogleFonts.nunito(
                fontSize: 12, color: BillifyColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyInvoiceState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: BillifyColors.surface,
        border: Border.all(color: BillifyColors.outlineVariant.withOpacity(0.3), width: 0.5),
      ),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 40,
            color: BillifyColors.outlineVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 10),
          Text(
            'NO INVOICES YET',
            style: GoogleFonts.poppins(
              fontSize: 10, fontWeight: FontWeight.w800,
              letterSpacing: 1.5, color: BillifyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap "New Invoice" to begin your ledger',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 12, color: BillifyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () => Get.toNamed(AppRoutes.invoiceCreate),
              style: ElevatedButton.styleFrom(
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                elevation: 0,
              ),
              child: Text(
                'CREATE INVOICE',
                style: GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  EMPTY QUERY SNAPSHOT
// ────────────────────────────────────────────────────────────

class _EmptyQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  const _EmptyQuerySnapshot();

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs => [];

  @override
  List<DocumentChange<Map<String, dynamic>>> get docChanges => [];

  @override
  SnapshotMetadata get metadata => _EmptyMetadata();

  @override
  int get size => 0;

  @override
  bool operator ==(Object other) => other is _EmptyQuerySnapshot;

  @override
  int get hashCode => 0;
}

class _EmptyMetadata implements SnapshotMetadata {
  @override
  bool get hasPendingWrites => false;

  @override
  bool get isFromCache => true;
}