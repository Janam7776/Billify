// ════════════════════════════════════════════════════════════
//  dashboard_screen.dart — Billify Phase 2 (Client-Centric)
//
//  All financial summaries are derived from the CLIENT
//  collection, NOT from invoices.  Each ClientModel carries:
//    • paymentAmount   → real project value
//    • paymentStatus   → Pending | Advance | Completed | Overdue
//    • createdAt       → used for the monthly bar chart
//
//  Summary cards:
//    • Completed       → count + sum of Completed clients
//    • Advance         → count + sum of Advance clients
//    • Pending         → count + sum of Pending clients
//    • Overdue         → count + sum of Overdue clients  ← NEW (wired)
//    • Total Expenses  → expense collection
//    • Net Balance     → (Completed + Advance) − Expenses
//    • Active Clients  → total client count
//
//  NEW SECTIONS (fully wired, same boxy aesthetic):
//    • _OverviewKpiRow         → 3 KPI tiles: collection rate, avg deal, overdue %
//    • _StatusDonutSection     → mini donut + legend (status distribution)
//    • _CategoryBreakdown      → per-category income bar list
//    • _ExpenseBreakdown       → top expense categories
//    • _QuickActionsSection    → shortcut tiles to common actions
//
//  Bar chart income = Completed + Advance client payments.
// ════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

import 'main.dart'
    show
    BillifyColors,
    AppRoutes,
    BillifyDrawer,
    AppSettings,
    BillifyC,
    BillifyDialog;
import 'expense_screens.dart' show ExpenseListScreen, AddExpenseScreen;
import 'client_screens.dart' show DashboardRecentClients, showClientActionSheet;
import 'web_layout.dart' show WebScaffold, WebLayoutService;
import 'theme_controller.dart' show ThemeController;

// ── Desktop-safe navigation ────────────────────────────────
void _navTo(String route, {Object? arguments}) {
  if (Get.isRegistered<WebLayoutService>()) {
    WebLayoutService.to.syncRoute(route);
  }
  Get.toNamed(route, arguments: arguments);
}

// ────────────────────────────────────────────────────────────
//  DATA MODELS
// ────────────────────────────────────────────────────────────

class _DashboardData {
  // ── Client-derived financials ──
  final double completedValue;
  final int completedCount;
  final double advanceValue;
  final int advanceCount;
  final double pendingValue;
  final int pendingCount;
  final double overdueValue;      // NEW: wired overdue
  final int overdueCount;         // NEW: wired overdue
  final int totalClients;

  // ── Expense-collection-derived ──
  final double totalExpense;

  // ── Derived ──
  final double netBalance;
  final double collectionRate;    // (completed + advance) / totalValue * 100
  final double avgDealSize;       // totalValue / totalClients

  // ── Chart ──
  final List<_MonthBar> monthBars;

  // ── Category breakdown ──
  final Map<String, double> categoryIncome;     // clientCategory → sum of (completed+advance)
  final Map<String, double> expenseByCategory;  // expense category → sum

  // ── Recent client activity ──
  final List<_RecentClient> recentClients;

  const _DashboardData({
    required this.completedValue,
    required this.completedCount,
    required this.advanceValue,
    required this.advanceCount,
    required this.pendingValue,
    required this.pendingCount,
    required this.overdueValue,
    required this.overdueCount,
    required this.totalClients,
    required this.totalExpense,
    required this.netBalance,
    required this.collectionRate,
    required this.avgDealSize,
    required this.monthBars,
    required this.categoryIncome,
    required this.expenseByCategory,
    required this.recentClients,
  });
}

class _MonthBar {
  final String label;
  final double income;
  final double expense;
  const _MonthBar(this.label, this.income, this.expense);
}

class _RecentClient {
  final String id;
  final String name;
  final String mobile;
  final double paymentAmount;
  final String paymentStatus;
  final String clientCategory;
  final DateTime createdAt;

  const _RecentClient({
    required this.id,
    required this.name,
    required this.mobile,
    required this.paymentAmount,
    required this.paymentStatus,
    required this.clientCategory,
    required this.createdAt,
  });
}

// ────────────────────────────────────────────────────────────
//  COMPUTE FUNCTION
// ────────────────────────────────────────────────────────────

_DashboardData _compute(
    QuerySnapshot clientSnap,
    QuerySnapshot expenseSnap,
    ) {
  final now = DateTime.now();

  // 4-month rolling window
  final Map<String, double> incomeByMonth = {};
  final Map<String, double> expenseByMonth = {};
  for (int i = 3; i >= 0; i--) {
    final m = DateTime(now.year, now.month - i, 1);
    final key = DateFormat('MMM').format(m);
    incomeByMonth[key] = 0;
    expenseByMonth[key] = 0;
  }

  double completedValue = 0;
  int completedCount = 0;
  double advanceValue = 0;
  int advanceCount = 0;
  double pendingValue = 0;
  int pendingCount = 0;
  double overdueValue = 0;
  int overdueCount = 0;
  final Map<String, double> categoryIncome = {};
  final List<_RecentClient> allClients = [];

  for (final doc in clientSnap.docs) {
    final d = doc.data() as Map<String, dynamic>;
    final ts = (d['createdAt'] ?? d['updatedAt']) as Timestamp?;
    final date = ts?.toDate() ?? now;
    final mKey = DateFormat('MMM').format(date);
    final category = (d['clientCategory'] as String? ?? 'Other');

    // Count how many reels this client has (mirrors ReelEntry.countReels)
    int reelCount = 0;
    if (d.containsKey('reelCategory')) reelCount = 1;
    int ri = 2;
    while (d.containsKey('reelCategory$ri')) {
      reelCount = ri;
      ri++;
    }
    if (reelCount == 0) reelCount = 1; // legacy fallback

    // Accumulate each reel's amount according to its own payment status
    double clientTotalAmount = 0;
    String primaryStatus = 'Pending';

    for (int i = 1; i <= reelCount; i++) {
      final suffix = i == 1 ? '' : '$i';
      final reelStatus =
      (d['paymentStatus$suffix'] as String? ?? 'Pending');
      final reelAmount =
      ((d['paymentAmount$suffix'] ?? 0) as num).toDouble();

      if (i == 1) primaryStatus = reelStatus;
      clientTotalAmount += reelAmount;

      switch (reelStatus.toLowerCase()) {
        case 'completed':
          completedValue += reelAmount;
          if (i == 1) completedCount++;
          if (incomeByMonth.containsKey(mKey)) {
            incomeByMonth[mKey] = incomeByMonth[mKey]! + reelAmount;
          }
          categoryIncome[category] =
              (categoryIncome[category] ?? 0) + reelAmount;
          break;
        case 'advance':
          advanceValue += reelAmount;
          if (i == 1) advanceCount++;
          if (incomeByMonth.containsKey(mKey)) {
            incomeByMonth[mKey] = incomeByMonth[mKey]! + reelAmount;
          }
          categoryIncome[category] =
              (categoryIncome[category] ?? 0) + reelAmount;
          break;
        case 'pending':
          pendingValue += reelAmount;
          if (i == 1) pendingCount++;
          break;
        case 'overdue':
          overdueValue += reelAmount;
          if (i == 1) overdueCount++;
          break;
      }
    }

    allClients.add(_RecentClient(
      id: doc.id,
      name: (d['name'] as String? ?? ''),
      mobile: (d['mobile'] as String? ?? ''),
      paymentAmount: clientTotalAmount,
      paymentStatus: primaryStatus,
      clientCategory: category,
      createdAt: date,
    ));
  }

  // Aggregate expenses
  double totalExpense = 0;
  final Map<String, double> expenseByCategory = {};
  for (final doc in expenseSnap.docs) {
    final d = doc.data() as Map<String, dynamic>;
    final type = (d['type'] ?? 'expense') as String;
    final amt = ((d['netAmount'] ?? d['amount'] ?? 0) as num).toDouble();
    final ts = (d['date'] ?? d['createdAt']) as Timestamp?;
    final date = ts?.toDate() ?? now;
    final mKey = DateFormat('MMM').format(date);
    final cat = (d['category'] as String? ?? 'Other');

    if (type == 'expense') {
      totalExpense += amt;
      if (expenseByMonth.containsKey(mKey)) {
        expenseByMonth[mKey] = expenseByMonth[mKey]! + amt;
      }
      expenseByCategory[cat] = (expenseByCategory[cat] ?? 0) + amt;
    }
  }

  allClients.sort((a, b) => b.createdAt.compareTo(a.createdAt));

  final earnedIncome = completedValue + advanceValue;
  final totalValue = earnedIncome + pendingValue + overdueValue;
  final collectionRate = totalValue > 0 ? (earnedIncome / totalValue * 100) : 0.0;
  final avgDealSize = allClients.isNotEmpty ? totalValue / allClients.length : 0.0;

  final monthBars = incomeByMonth.keys
      .map((k) => _MonthBar(k, incomeByMonth[k]!, expenseByMonth[k]!))
      .toList();

  // Sort categoryIncome descending
  final sortedCategoryIncome = Map.fromEntries(
    categoryIncome.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );
  final sortedExpenseByCategory = Map.fromEntries(
    expenseByCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
  );

  return _DashboardData(
    completedValue: completedValue,
    completedCount: completedCount,
    advanceValue: advanceValue,
    advanceCount: advanceCount,
    pendingValue: pendingValue,
    pendingCount: pendingCount,
    overdueValue: overdueValue,
    overdueCount: overdueCount,
    totalClients: allClients.length,
    totalExpense: totalExpense,
    netBalance: earnedIncome - totalExpense,
    collectionRate: collectionRate,
    avgDealSize: avgDealSize,
    monthBars: monthBars,
    categoryIncome: sortedCategoryIncome,
    expenseByCategory: sortedExpenseByCategory,
    recentClients: allClients.take(5).toList(),
  );
}

// ────────────────────────────────────────────────────────────
//  DASHBOARD SCREEN
// ────────────────────────────────────────────────────────────

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final fmt = AppSettings.currencyFmt();

    final clientStream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('clients')
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
            iconColor: ThemeController.to.primary,
            title: 'Exit Billify?',
            body: 'Are you sure you want to exit the app?',
            confirmLabel: 'Exit',
            confirmColor: BillifyColors.unpaid,
            onConfirm: () => Navigator.of(ctx).pop(true),
          ),
        );
        if (shouldExit == true) SystemNavigator.pop();
      },
      child: WebScaffold(
        activeRoute: AppRoutes.dashboard,
        appBar: _buildAppBar(),
        floatingActionButton: _buildFABs(context),
        body: _buildBody(
          context: context,
          fmt: fmt,
          clientStream: clientStream,
          expenseStream: expenseStream,
          userStream: userStream,
        ),
      ),
    );
  }

  // ── AppBar ──────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: BillifyColors.background,
      elevation: 0,
      title: Text(
        'DASHBOARD',
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
            height: 1,
            color: BillifyColors.outlineVariant.withOpacity(0.4)),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined,
              color: BillifyColors.textSecondary, size: 20),
          onPressed: () {},
        ),
      ],
    );
  }

  // ── FABs ────────────────────────────────────────────────

  Widget _buildFABs(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.extended(
          heroTag: 'fab_expense',
          onPressed: () => _navTo(AppRoutes.expenseAdd),
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            'ADD EXPENSE',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.2),
          ),
          backgroundColor: BillifyColors.surfaceHigh,
          foregroundColor: BillifyColors.textPrimary,
          elevation: 0,
          shape:
          const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
          heroTag: 'fab_client',
          onPressed: () => showClientActionSheet(context),
          icon: const Icon(Icons.person_add_rounded, size: 18),
          label: Text(
            'CLIENT',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 1.2),
          ),
          backgroundColor: ThemeController.to.primary,
          foregroundColor: const Color(0xFFF7F7FF),
          elevation: 0,
          shape:
          const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        ),
      ],
    );
  }

  // ── Body ────────────────────────────────────────────────

  Widget _buildBody({
    required BuildContext context,
    required NumberFormat fmt,
    required Stream<QuerySnapshot> clientStream,
    required Stream<QuerySnapshot> expenseStream,
    required Stream<DocumentSnapshot> userStream,
  }) {
    return StreamBuilder<QuerySnapshot>(
      stream: clientStream,
      builder: (context, clientSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: expenseStream,
          builder: (context, expenseSnap) {
            final _DashboardData? d =
            (clientSnap.hasData && expenseSnap.hasData)
                ? _compute(clientSnap.data!, expenseSnap.data!)
                : clientSnap.hasData
                ? _compute(
                clientSnap.data!, _EmptyQuerySnapshot())
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

                if (clientSnap.connectionState == ConnectionState.waiting &&
                    !clientSnap.hasData) {
                  return Center(
                    child: CircularProgressIndicator(
                        color: ThemeController.to.primary),
                  );
                }

                return RefreshIndicator(
                  color: ThemeController.to.primary,
                  onRefresh: () async =>
                      Future.delayed(const Duration(milliseconds: 400)),
                  child: CustomScrollView(
                    slivers: [
                      // ── Header Banner ──────────────────
                      SliverToBoxAdapter(
                        child: _HeaderBanner(userName: userName),
                      ),
                      // ── KPI Row (new) ──────────────────
                      if (d != null)
                        SliverToBoxAdapter(
                          child: _OverviewKpiRow(d: d, fmt: fmt),
                        ),
                      // ── Summary Cards ──────────────────
                      SliverToBoxAdapter(
                        child: _SummaryCardsSection(d: d, fmt: fmt),
                      ),
                      // ── Quick Actions (new) ────────────
                      SliverToBoxAdapter(
                        child: _QuickActionsSection(),
                      ),
                      // ── Bar Chart ──────────────────────
                      if (d != null && d.monthBars.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _BarChartCard(bars: d.monthBars),
                        ),
                      // ── Status Distribution (new) ──────
                      if (d != null && d.totalClients > 0)
                        SliverToBoxAdapter(
                          child: _StatusDistributionSection(d: d, fmt: fmt),
                        ),
                      // ── Recent Client Activity ─────────
                      SliverToBoxAdapter(
                        child: _RecentClientsSection(
                          clients: d?.recentClients ?? [],
                          fmt: fmt,
                        ),
                      ),
                      // ── Category Breakdown (new) ───────
                      if (d != null && d.categoryIncome.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _CategoryBreakdownSection(d: d, fmt: fmt),
                        ),
                      // ── Expense Breakdown (new) ────────
                      if (d != null && d.expenseByCategory.isNotEmpty)
                        SliverToBoxAdapter(
                          child: _ExpenseBreakdownSection(d: d, fmt: fmt),
                        ),
                      // ── Recent Clients (from client_screens) ─
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
//  SECTION HEADER HELPER
// ────────────────────────────────────────────────────────────

Widget _sectionHeader(String title, {String? action, VoidCallback? onAction}) {
  return Row(
    children: [
      Container(width: 3, height: 14, color: ThemeController.to.primary),
      const SizedBox(width: 8),
      Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.8,
          color: ThemeController.to.primary,
        ),
      ),
      if (action != null) ...[
        const Spacer(),
        GestureDetector(
          onTap: onAction,
          child: Text(
            action,
            style: GoogleFonts.poppins(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: ThemeController.to.primary,
            ),
          ),
        ),
      ],
    ],
  );
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
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _sectionHeader('CLIENT FINANCIALS'),
          ),
          Column(
            children: [
              // ── Row 1: Completed | Advance ────────────────────
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: 'Completed',
                        value: fmt.format(d!.completedValue),
                        subLabel: '${d!.completedCount} client${d!.completedCount == 1 ? '' : 's'}',
                        icon: Icons.check_circle_rounded,
                        color: BillifyColors.paid,
                        bgColor: const Color(0xFFE8F5E9),
                        onTap: () => _navTo(AppRoutes.clients,
                            arguments: {'filter': 'Completed'}),
                      ),
                    ),
                    const SizedBox(width: 1),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Advance',
                        value: fmt.format(d!.advanceValue),
                        subLabel: '${d!.advanceCount} client${d!.advanceCount == 1 ? '' : 's'}',
                        icon: Icons.timelapse_rounded,
                        color: const Color(0xFF1976D2),
                        bgColor: const Color(0xFFE3F2FD),
                        onTap: () => _navTo(AppRoutes.clients,
                            arguments: {'filter': 'Advance'}),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              // ── Row 2: Pending | Overdue ──────────────────────
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: 'Pending',
                        value: fmt.format(d!.pendingValue),
                        subLabel: '${d!.pendingCount} client${d!.pendingCount == 1 ? '' : 's'}',
                        icon: Icons.hourglass_bottom_rounded,
                        color: BillifyColors.unpaid,
                        bgColor: const Color(0xFFFFEBEE),
                        onTap: () => _navTo(AppRoutes.clients,
                            arguments: {'filter': 'Pending'}),
                      ),
                    ),
                    const SizedBox(width: 1),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Overdue',
                        value: fmt.format(d!.overdueValue),
                        subLabel: '${d!.overdueCount} client${d!.overdueCount == 1 ? '' : 's'}',
                        icon: Icons.warning_amber_rounded,
                        color: BillifyColors.overdue,
                        bgColor: const Color(0xFFFFF3E0),
                        onTap: () => _navTo(AppRoutes.clients,
                            arguments: {'filter': 'Overdue'}),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              // ── Row 3: Expenses | Net Balance ─────────────────
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: 'Expenses',
                        value: fmt.format(d!.totalExpense),
                        icon: Icons.arrow_upward_rounded,
                        color: const Color(0xFFE53935),
                        bgColor: const Color(0xFFFFEBEE),
                        onTap: () => _navTo(AppRoutes.expenses),
                      ),
                    ),
                    const SizedBox(width: 1),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Net Balance',
                        value: fmt.format(d!.netBalance),
                        icon: Icons.account_balance_wallet_rounded,
                        color: d!.netBalance >= 0
                            ? BillifyColors.paid
                            : BillifyColors.unpaid,
                        bgColor: d!.netBalance >= 0
                            ? const Color(0xFFE8F5E9)
                            : const Color(0xFFFFEBEE),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 1),
              // ── Row 4: Active Clients (full width) ────────────
              _SummaryCard(
                label: 'Active Clients',
                value: '${d!.totalClients} client${d!.totalClients == 1 ? '' : 's'}',
                icon: Icons.people_rounded,
                color: ThemeController.to.primary,
                bgColor: const Color(0xFFE8EAF6),
                isWide: true,
                onTap: () => _navTo(AppRoutes.clients),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  OVERVIEW KPI ROW  ← NEW
// ────────────────────────────────────────────────────────────

class _OverviewKpiRow extends StatelessWidget {
  final _DashboardData d;
  final NumberFormat fmt;
  const _OverviewKpiRow({required this.d, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final overduePercent = d.totalClients > 0
        ? (d.overdueCount / d.totalClients * 100)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('PERFORMANCE OVERVIEW'),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _KpiTile(
                    label: 'COLLECTION\nRATE',
                    value: '${d.collectionRate.toStringAsFixed(1)}%',
                    icon: Icons.trending_up_rounded,
                    color: d.collectionRate >= 70
                        ? BillifyColors.paid
                        : d.collectionRate >= 40
                        ? const Color(0xFF1976D2)
                        : BillifyColors.unpaid,
                    footnote: 'of total pipeline',
                  ),
                ),
                const SizedBox(width: 1),
                Expanded(
                  child: _KpiTile(
                    label: 'AVG DEAL\nSIZE',
                    value: fmt.format(d.avgDealSize),
                    icon: Icons.bar_chart_rounded,
                    color: ThemeController.to.primary,
                    footnote: 'per client',
                  ),
                ),
                const SizedBox(width: 1),
                Expanded(
                  child: _KpiTile(
                    label: 'OVERDUE\nRATE',
                    value: '${overduePercent.toStringAsFixed(1)}%',
                    icon: Icons.warning_amber_rounded,
                    color: overduePercent > 20
                        ? BillifyColors.overdue
                        : overduePercent > 5
                        ? BillifyColors.unpaid
                        : BillifyColors.paid,
                    footnote: '${d.overdueCount} client${d.overdueCount == 1 ? '' : 's'}',
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

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final String footnote;
  final IconData icon;
  final Color color;

  const _KpiTile({
    required this.label,
    required this.value,
    required this.footnote,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BillifyColors.surface,
        border: Border(
          top: BorderSide(color: color, width: 2),
          left: BorderSide(
              color: BillifyColors.outlineVariant.withOpacity(0.3),
              width: 0.5),
          right: BorderSide(
              color: BillifyColors.outlineVariant.withOpacity(0.3),
              width: 0.5),
          bottom: BorderSide(
              color: BillifyColors.outlineVariant.withOpacity(0.3),
              width: 0.5),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: BillifyColors.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            footnote,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: color.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 7,
              fontWeight: FontWeight.w700,
              color: BillifyColors.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  QUICK ACTIONS SECTION  ← NEW
// ────────────────────────────────────────────────────────────

class _QuickActionsSection extends StatelessWidget {
  const _QuickActionsSection();

  @override
  Widget build(BuildContext context) {
    final row1 = [
      _QuickAction(
        label: 'NEW\nCLIENT',
        icon: Icons.person_add_rounded,
        onTap: () => _navTo(AppRoutes.clientAdd),
      ),
      _QuickAction(
        label: 'ADD\nEXPENSE',
        icon: Icons.receipt_long_rounded,
        onTap: () => _navTo(AppRoutes.expenseAdd),
      ),
      _QuickAction(
        label: 'ALL\nCLIENTS',
        icon: Icons.people_outline_rounded,
        onTap: () => _navTo(AppRoutes.clients),
      ),
      _QuickAction(
        label: 'EXPENSES\nLIST',
        icon: Icons.account_balance_wallet_outlined,
        onTap: () => _navTo(AppRoutes.expenses),
      ),
    ];
    final row2 = [
      _QuickAction(
        label: 'ANALYTICS',
        icon: Icons.bar_chart_rounded,
        onTap: () => _navTo(AppRoutes.analytics),
      ),
      _QuickAction(
        label: 'SETTLEMENT',
        icon: Icons.handshake_rounded,
        onTap: () => _navTo(AppRoutes.settlement),
      ),
    ];

    Row buildRow(List<_QuickAction> acts) => Row(
      children: acts.asMap().entries.map((e) {
        return Expanded(
          child: Row(
            children: [
              Expanded(child: _QuickActionTile(action: e.value)),
              if (e.key < acts.length - 1) const SizedBox(width: 1),
            ],
          ),
        );
      }).toList(),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('QUICK ACTIONS'),
          const SizedBox(height: 10),
          buildRow(row1),
          const SizedBox(height: 1),
          buildRow(row2),
        ],
      ),
    );
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _QuickAction({required this.label, required this.icon, required this.onTap});
}

class _QuickActionTile extends StatelessWidget {
  final _QuickAction action;
  const _QuickActionTile({required this.action});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: action.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: ThemeController.to.primary.withOpacity(0.05),
          border: Border.all(
            color: ThemeController.to.primary.withOpacity(0.2),
            width: 0.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, color: ThemeController.to.primary, size: 20),
            const SizedBox(height: 6),
            Text(
              action.label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 7,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: ThemeController.to.primary,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  STATUS DISTRIBUTION SECTION  ← NEW
// ────────────────────────────────────────────────────────────

class _StatusDistributionSection extends StatelessWidget {
  final _DashboardData d;
  final NumberFormat fmt;
  const _StatusDistributionSection({required this.d, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final total = d.completedCount + d.advanceCount + d.pendingCount + d.overdueCount;
    if (total == 0) return const SizedBox.shrink();

    final segments = [
      _DonutSegment('Completed', d.completedCount, BillifyColors.paid, const Color(0xFFE8F5E9)),
      _DonutSegment('Advance', d.advanceCount, const Color(0xFF1976D2), const Color(0xFFE3F2FD)),
      _DonutSegment('Pending', d.pendingCount, BillifyColors.unpaid, const Color(0xFFFFEBEE)),
      _DonutSegment('Overdue', d.overdueCount, BillifyColors.overdue, const Color(0xFFFFF3E0)),
    ].where((s) => s.count > 0).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: BillifyColors.surface,
          border: Border.all(
              color: BillifyColors.outlineVariant.withOpacity(0.3),
              width: 0.5),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader('CLIENT STATUS SPLIT'),
            const SizedBox(height: 14),
            Row(
              children: [
                // Mini donut
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CustomPaint(
                    painter: _DonutPainter(segments: segments, total: total),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$total',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: BillifyColors.textPrimary,
                            ),
                          ),
                          Text(
                            'TOTAL',
                            style: GoogleFonts.poppins(
                              fontSize: 6,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              color: BillifyColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                // Legend
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: segments.map((s) {
                      final pct = (s.count / total * 100).toStringAsFixed(1);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(width: 10, height: 10, color: s.color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.label.toUpperCase(),
                                style: GoogleFonts.poppins(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.6,
                                  color: BillifyColors.textSecondary,
                                ),
                              ),
                            ),
                            Text(
                              '${s.count}',
                              style: GoogleFonts.poppins(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: s.color,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$pct%',
                              style: GoogleFonts.poppins(
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                                color: BillifyColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
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

class _DonutSegment {
  final String label;
  final int count;
  final Color color;
  final Color bgColor;
  const _DonutSegment(this.label, this.count, this.color, this.bgColor);
}

class _DonutPainter extends CustomPainter {
  final List<_DonutSegment> segments;
  final int total;
  const _DonutPainter({required this.segments, required this.total});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = math.min(cx, cy) - 2;
    final innerR = outerR * 0.55;
    double startAngle = -math.pi / 2;
    const gapAngle = 0.04;

    for (final seg in segments) {
      final sweep = (seg.count / total) * (2 * math.pi) - gapAngle;
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.fill;

      final path = Path();
      path.moveTo(cx + outerR * math.cos(startAngle), cy + outerR * math.sin(startAngle));
      path.arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: outerR),
          startAngle, sweep, false);
      path.arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: innerR),
          startAngle + sweep, -sweep, false);
      path.close();
      canvas.drawPath(path, paint);

      startAngle += sweep + gapAngle;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => false;
}

// ────────────────────────────────────────────────────────────
//  CATEGORY BREAKDOWN SECTION  ← NEW
// ────────────────────────────────────────────────────────────

class _CategoryBreakdownSection extends StatelessWidget {
  final _DashboardData d;
  final NumberFormat fmt;
  const _CategoryBreakdownSection({required this.d, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final maxVal = d.categoryIncome.values.fold(0.0, (a, b) => a > b ? a : b);
    final top = d.categoryIncome.entries.take(5).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: BillifyColors.surface,
          border: Border.all(
              color: BillifyColors.outlineVariant.withOpacity(0.3),
              width: 0.5),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              'INCOME BY CATEGORY',
              action: 'VIEW CLIENTS →',
              onAction: () => _navTo(AppRoutes.clients),
            ),
            const SizedBox(height: 14),
            ...top.map((e) {
              final ratio = maxVal > 0 ? e.value / maxVal : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: BillifyColors.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          fmt.format(e.value),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: BillifyColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Stack(
                      children: [
                        Container(
                          height: 4,
                          width: double.infinity,
                          color: BillifyColors.surfaceContainer,
                        ),
                        FractionallySizedBox(
                          widthFactor: ratio,
                          child: Container(
                            height: 4,
                            color: ThemeController.to.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────
//  EXPENSE BREAKDOWN SECTION  ← NEW
// ────────────────────────────────────────────────────────────

class _ExpenseBreakdownSection extends StatelessWidget {
  final _DashboardData d;
  final NumberFormat fmt;
  const _ExpenseBreakdownSection({required this.d, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final maxVal = d.expenseByCategory.values.fold(0.0, (a, b) => a > b ? a : b);
    final top = d.expenseByCategory.entries.take(5).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: BillifyColors.surface,
          border: Border.all(
              color: BillifyColors.outlineVariant.withOpacity(0.3),
              width: 0.5),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              'TOP EXPENSE CATEGORIES',
              action: 'VIEW ALL →',
              onAction: () => _navTo(AppRoutes.expenses),
            ),
            const SizedBox(height: 14),
            ...top.map((e) {
              final ratio = maxVal > 0 ? e.value / maxVal : 0.0;
              final pct = d.totalExpense > 0
                  ? (e.value / d.totalExpense * 100).toStringAsFixed(1)
                  : '0.0';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            e.key.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: BillifyColors.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          '$pct%',
                          style: GoogleFonts.poppins(
                            fontSize: 8,
                            fontWeight: FontWeight.w600,
                            color: BillifyColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          fmt.format(e.value),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFE53935),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Stack(
                      children: [
                        Container(
                          height: 4,
                          width: double.infinity,
                          color: BillifyColors.surfaceContainer,
                        ),
                        FractionallySizedBox(
                          widthFactor: ratio,
                          child: Container(
                            height: 4,
                            color: const Color(0xFFE53935),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: const Color(0xFFFFEBEE),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TOTAL EXPENSES',
                    style: GoogleFonts.poppins(
                      fontSize: 8,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: const Color(0xFFE53935),
                    ),
                  ),
                  Text(
                    fmt.format(d.totalExpense),
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFE53935),
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
      color: ThemeController.to.primary,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _DashGridPainter())),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CLIENT OVERVIEW',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFF7F7FF).withOpacity(0.5),
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  userName.isEmpty
                      ? 'Client Summary.'
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
                  DateFormat('EEEE, d MMMM yyyy')
                      .format(DateTime.now())
                      .toUpperCase(),
                  style: GoogleFonts.poppins(
                    color: const Color(0xFFF7F7FF).withOpacity(0.55),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
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
  final String? subLabel;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback? onTap;
  final bool isWide;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
    this.subLabel,
    this.onTap,
    this.isWide = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isWide ? double.infinity : null,
        decoration: BoxDecoration(
          color: BillifyColors.surface,
          border: Border(
            top: BorderSide(color: color, width: 2),
            left: BorderSide(
                color: BillifyColors.outlineVariant.withOpacity(0.3),
                width: 0.5),
            right: BorderSide(
                color: BillifyColors.outlineVariant.withOpacity(0.3),
                width: 0.5),
            bottom: BorderSide(
                color: BillifyColors.outlineVariant.withOpacity(0.3),
                width: 0.5),
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: isWide
            ? Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              color: bgColor,
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: BillifyColors.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    label.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                      color: BillifyColors.textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.arrow_forward_rounded,
                  size: 14, color: BillifyColors.outlineVariant),
          ],
        )
            : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 18),
                if (onTap != null)
                  const Icon(Icons.arrow_forward_rounded,
                      size: 12,
                      color: BillifyColors.outlineVariant),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: BillifyColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            if (subLabel != null) ...[
              const SizedBox(height: 1),
              Text(
                subLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color.withOpacity(0.8),
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: GoogleFonts.poppins(
                fontSize: 8,
                fontWeight: FontWeight.w700,
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
        border: Border.all(
            color: BillifyColors.outlineVariant.withOpacity(0.3),
            width: 0.5),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartHeader(),
          const SizedBox(height: 14),
          _buildChart(context, chartMax),
        ],
      ),
    );
  }

  Widget _buildChartHeader() {
    return Row(
      children: [
        Container(width: 3, height: 14, color: ThemeController.to.primary),
        const SizedBox(width: 8),
        Text(
          'CLIENT INCOME VS EXPENSE',
          style: GoogleFonts.poppins(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.8,
            color: ThemeController.to.primary,
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
            leftTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
            fontSize: 8,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: BillifyColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ────────────────────────────────────────────────────────────
//  RECENT CLIENTS SECTION
// ────────────────────────────────────────────────────────────

class _RecentClientsSection extends StatelessWidget {
  final List<_RecentClient> clients;
  final NumberFormat fmt;
  const _RecentClientsSection(
      {required this.clients, required this.fmt});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            'RECENT CLIENT ACTIVITY',
            action: 'VIEW ALL →',
            onAction: () => _navTo(AppRoutes.clients),
          ),
          const SizedBox(height: 8),
          if (clients.isNotEmpty)
            Container(
              color: BillifyColors.surfaceContainer,
              padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Expanded(
                    flex: 3,
                    child: Text('CLIENT NAME', style: _hStyle())),
                Expanded(
                    flex: 2,
                    child: Text('AMOUNT',
                        style: _hStyle(), textAlign: TextAlign.right)),
                Expanded(
                    flex: 2,
                    child: Text('STATUS',
                        style: _hStyle(), textAlign: TextAlign.center)),
              ]),
            ),
          clients.isEmpty
              ? _EmptyClientActivityState()
              : Column(
            children: clients
                .map((c) => _ClientActivityRow(client: c, fmt: fmt))
                .toList(),
          ),
        ],
      ),
    );
  }

  TextStyle _hStyle() => GoogleFonts.poppins(
      fontSize: 8,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.2,
      color: BillifyColors.textSecondary);
}

// ────────────────────────────────────────────────────────────
//  CLIENT ACTIVITY ROW
// ────────────────────────────────────────────────────────────

Color _clientStatusColor(String s) {
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

Color _clientStatusBg(String s) {
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

class _ClientActivityRow extends StatelessWidget {
  final _RecentClient client;
  final NumberFormat fmt;
  const _ClientActivityRow({required this.client, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final statusColor = _clientStatusColor(client.paymentStatus);
    final statusBg = _clientStatusBg(client.paymentStatus);

    return GestureDetector(
      onTap: () => _navTo(
        AppRoutes.clientDetail,
        arguments: client.id,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: BillifyColors.surface,
          border: Border(
            left: BorderSide(color: statusColor, width: 3),
            bottom: BorderSide(
                color: BillifyColors.outlineVariant.withOpacity(0.2),
                width: 0.5),
          ),
        ),
        padding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    client.name.isEmpty ? 'Unknown Client' : client.name,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: BillifyColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${client.clientCategory}  ·  ${AppSettings.formatDate(client.createdAt)}',
                    style: GoogleFonts.poppins(
                      fontSize: 8,
                      color: BillifyColors.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                AppSettings.showAmountOnList
                    ? fmt.format(client.paymentAmount)
                    : '—',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: BillifyColors.textPrimary,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  color: statusBg,
                  child: Text(
                    client.paymentStatus.toUpperCase(),
                    style: GoogleFonts.poppins(
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: statusColor,
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
//  SHARED STATUS HELPERS
// ────────────────────────────────────────────────────────────

Color invoiceStatusColor(String s) {
  switch (s) {
    case 'paid':
      return BillifyColors.paid;
    case 'unpaid':
      return BillifyColors.unpaid;
    case 'advance':
      return const Color(0xFF6A5ACD);
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
    case 'advance':
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
    case 'advance':
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
  final statuses = ['draft', 'unpaid', 'paid', 'advance'];
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
            Container(height: 3, color: ThemeController.to.primary),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SETTLEMENT STATUS',
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                      color: ThemeController.to.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select a status below, then tap Apply',
                    style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: BillifyColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  ...widget.statuses.map((s) {
                    final isActive = _selected == s;
                    return GestureDetector(
                      onTap: () => setState(() => _selected = s),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isActive
                              ? invoiceStatusBg(s)
                              : BillifyColors.surfaceLow,
                          border: Border(
                            left: BorderSide(
                              color: isActive
                                  ? invoiceStatusColor(s)
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        child: Row(children: [
                          Icon(invoiceStatusIcon(s),
                              color: invoiceStatusColor(s), size: 16),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              s.toUpperCase(),
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: isActive
                                    ? invoiceStatusColor(s)
                                    : BillifyColors.textPrimary,
                              ),
                            ),
                          ),
                          if (s == widget.current)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              color: BillifyColors.outlineVariant
                                  .withOpacity(0.3),
                              child: Text('CURRENT',
                                  style: GoogleFonts.poppins(
                                      fontSize: 7,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                      color: BillifyColors.textSecondary)),
                            ),
                          if (isActive && s != widget.current)
                            Icon(Icons.check_rounded,
                                color: invoiceStatusColor(s), size: 16),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  if (_saving)
                    Center(
                        child: CircularProgressIndicator(
                            color: ThemeController.to.primary))
                  else
                    ElevatedButton(
                      onPressed: _apply,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _selected == widget.current
                            ? BillifyColors.textSecondary
                            : invoiceStatusColor(_selected),
                        minimumSize: const Size(double.infinity, 48),
                        shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero),
                        elevation: 0,
                      ),
                      child: Text(
                        'APPLY STATUS',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                            letterSpacing: 1.5),
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
              width: 3,
              height: 32,
              color: BillifyColors.outlineVariant.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'NO CLIENT DATA',
              style: GoogleFonts.poppins(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
                color: BillifyColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add your first client to get started',
              style: GoogleFonts.nunito(
                fontSize: 12,
                color: BillifyColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyClientActivityState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: BillifyColors.surface,
        border: Border.all(
            color: BillifyColors.outlineVariant.withOpacity(0.3),
            width: 0.5),
      ),
      child: Column(
        children: [
          Icon(
            Icons.people_outline_rounded,
            size: 40,
            color: BillifyColors.outlineVariant.withOpacity(0.5),
          ),
          const SizedBox(height: 10),
          Text(
            'NO CLIENTS YET',
            style: GoogleFonts.poppins(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: BillifyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add your first client to track activity',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 12,
              color: BillifyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () => _navTo(AppRoutes.clientAdd),
              style: ElevatedButton.styleFrom(
                shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.zero),
                elevation: 0,
              ),
              child: Text(
                'ADD CLIENT',
                style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5),
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