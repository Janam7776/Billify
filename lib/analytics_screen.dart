// ════════════════════════════════════════════════════════════
//  analytics_screen.dart — Billify Analytics Module
//
//  Comprehensive analytics dashboard covering:
//    • Revenue Overview (line chart — monthly trend)
//    • Payment Status Distribution (pie chart)
//    • Income vs Expense (bar chart — monthly)
//    • Top Clients by Revenue (horizontal bar)
//    • Category Breakdown (donut chart)
//    • Shoot Category Distribution (pie chart)
//    • Reel Category Breakdown (pie chart)
//    • Payment Type Distribution (pie chart)
//    • Client Growth (area/line chart — monthly)
//    • Expense Category Breakdown (donut chart)
//    • Net Profit Trend (line chart)
//    • KPI Summary Cards
// ════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

import 'main.dart'
    show BillifyColors, AppRoutes, BillifyDrawer, BillifyC, AppThemeContext;
import 'web_layout.dart' show WebScaffold, WebLayoutService;
import 'theme_controller.dart' show ThemeController;
import 'client_screens.dart' show ClientModel, ReelEntry;

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

class _AnalyticsData {
  // KPIs
  final double totalRevenue;
  final double totalExpenses;
  final double netProfit;
  final int totalClients;
  final int totalInvoices;
  final double collectionRate;
  final double avgDealSize;

  // Period-over-period trends (% change, null = no prior data)
  final double? revenueTrend;
  final double? expenseTrend;
  final double? profitTrend;

  // Best month label + value
  final String bestMonthLabel;
  final double bestMonthRevenue;

  // Status distribution
  final Map<String, double> statusDistribution;
  final Map<String, int> statusCount;

  // Monthly revenue & expenses (last 12 months)
  final List<_MonthStat> monthlyStats;

  // Category breakdowns
  final Map<String, double> clientCategoryRevenue;
  final Map<String, double> shootCategoryRevenue;
  final Map<String, double> reelCategoryRevenue;
  final Map<String, double> paymentTypeDistribution;
  final Map<String, double> expenseCategoryBreakdown;

  // Top clients
  final List<_ClientStat> topClients;

  // Monthly client growth
  final List<_MonthCount> clientGrowth;

  const _AnalyticsData({
    required this.totalRevenue,
    required this.totalExpenses,
    required this.netProfit,
    required this.totalClients,
    required this.totalInvoices,
    required this.collectionRate,
    required this.avgDealSize,
    this.revenueTrend,
    this.expenseTrend,
    this.profitTrend,
    this.bestMonthLabel = '',
    this.bestMonthRevenue = 0,
    required this.statusDistribution,
    required this.statusCount,
    required this.monthlyStats,
    required this.clientCategoryRevenue,
    required this.shootCategoryRevenue,
    required this.reelCategoryRevenue,
    required this.paymentTypeDistribution,
    required this.expenseCategoryBreakdown,
    required this.topClients,
    required this.clientGrowth,
  });

  static _AnalyticsData empty() => _AnalyticsData(
    totalRevenue: 0,
    totalExpenses: 0,
    netProfit: 0,
    totalClients: 0,
    totalInvoices: 0,
    collectionRate: 0,
    avgDealSize: 0,
    statusDistribution: {},
    statusCount: {},
    monthlyStats: [],
    clientCategoryRevenue: {},
    shootCategoryRevenue: {},
    reelCategoryRevenue: {},
    paymentTypeDistribution: {},
    expenseCategoryBreakdown: {},
    topClients: [],
    clientGrowth: [],
  );
}

class _MonthStat {
  final String label;
  final double revenue;
  final double expense;
  final double netProfit;
  const _MonthStat(this.label, this.revenue, this.expense, this.netProfit);
}

class _ClientStat {
  final String name;
  final double revenue;
  final int reelCount;
  const _ClientStat(this.name, this.revenue, this.reelCount);
}

class _MonthCount {
  final String label;
  final int count;
  const _MonthCount(this.label, this.count);
}

// ════════════════════════════════════════════════════════════
//  ANALYTICS SCREEN
// ════════════════════════════════════════════════════════════

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  _AnalyticsData _data = _AnalyticsData.empty();
  bool _loading = true;
  String _selectedPeriod = '12M';

  // Custom date range (used when _selectedPeriod == 'CUSTOM')
  DateTime? _customFrom;
  DateTime? _customTo;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final from = await showDatePicker(
      context: context,
      initialDate: _customFrom ?? DateTime(now.year, now.month - 2),
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'SELECT START MONTH',
    );
    if (from == null || !mounted) return;
    final to = await showDatePicker(
      context: context,
      initialDate: _customTo ?? now,
      firstDate: from,
      lastDate: now,
      helpText: 'SELECT END MONTH',
    );
    if (to == null || !mounted) return;
    setState(() {
      _customFrom = DateTime(from.year, from.month, 1);
      _customTo = DateTime(to.year, to.month, 1);
      _selectedPeriod = 'CUSTOM';
    });
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      late DateTime rangeStart;
      late DateTime rangeEnd;

      if (_selectedPeriod == 'CUSTOM' && _customFrom != null && _customTo != null) {
        rangeStart = DateTime(_customFrom!.year, _customFrom!.month, 1);
        rangeEnd = DateTime(_customTo!.year, _customTo!.month + 1, 0);
      } else {
        final months = _selectedPeriod == '3M' ? 3 : _selectedPeriod == '6M' ? 6 : 12;
        rangeStart = DateTime(now.year, now.month - months + 1, 1);
        rangeEnd = now;
      }

      // Number of months in range (for building stats arrays)
      final monthDiff = (rangeEnd.year - rangeStart.year) * 12 + rangeEnd.month - rangeStart.month + 1;
      final months = monthDiff.clamp(1, 60);
      final cutoff = rangeStart;

      // ── Clients ──
      final clientSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('clients')
          .get();

      // ── Expenses ──
      final expenseSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('expenses')
          .get();

      // ── Invoices ──
      final invoiceSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('invoices')
          .get();

      // ── Process clients ──
      final clients = clientSnap.docs
          .map((d) => ClientModel.fromDoc(d))
          .toList();

      double totalRev = 0;
      double completedRev = 0;
      Map<String, double> statusDist = {};
      Map<String, int> statusCnt = {};
      Map<String, double> catRev = {};
      Map<String, double> shootCatRev = {};
      Map<String, double> reelCatRev = {};
      Map<String, double> payTypeDist = {};
      Map<String, Map<int, double>> monthRevMap = {}; // "yyyy-M" -> {index -> rev}
      Map<String, int> monthClientCount = {};
      List<_ClientStat> clientStats = [];

      for (final client in clients) {
        double clientTotal = 0;
        for (final reel in client.reels) {
          final amt = reel.paymentAmount;
          totalRev += amt;
          clientTotal += amt;

          // Status
          final status = reel.paymentStatus;
          statusDist[status] = (statusDist[status] ?? 0) + amt;
          statusCnt[status] = (statusCnt[status] ?? 0) + 1;
          if (status == 'Completed' || status == 'Advance') {
            completedRev += amt;
          }

          // Shoot category
          final sc = reel.displayShootCategory;
          shootCatRev[sc] = (shootCatRev[sc] ?? 0) + amt;

          // Reel category
          final rc = reel.displayReelCategory;
          reelCatRev[rc] = (reelCatRev[rc] ?? 0) + amt;

          // Payment type
          final pt = reel.displayPaymentType;
          payTypeDist[pt] = (payTypeDist[pt] ?? 0) + amt;
        }

        // Client category
        final cc = client.displayCategory;
        catRev[cc] = (catRev[cc] ?? 0) + clientTotal;

        // Monthly revenue (by client creation date)
        final key =
            '${client.createdAt.year}-${client.createdAt.month.toString().padLeft(2, '0')}';
        monthRevMap[key] = (monthRevMap[key] ?? {});
        monthRevMap[key]![client.reels.length] =
            (monthRevMap[key]![client.reels.length] ?? 0) + clientTotal;

        // Monthly client growth
        if (client.createdAt.isAfter(cutoff)) {
          final ck =
              '${client.createdAt.year}-${client.createdAt.month.toString().padLeft(2, '0')}';
          monthClientCount[ck] = (monthClientCount[ck] ?? 0) + 1;
        }

        clientStats.add(_ClientStat(client.name, clientTotal, client.reelCount));
      }

      // ── Process expenses ──
      double totalExp = 0;
      Map<String, double> expCat = {};
      Map<String, double> monthExpMap = {};

      for (final doc in expenseSnap.docs) {
        final d = doc.data();
        final amt = ((d['amount'] ?? 0) as num).toDouble();
        totalExp += amt;
        final cat = d['category'] as String? ?? 'Other';
        expCat[cat] = (expCat[cat] ?? 0) + amt;

        final date = (d['date'] as Timestamp?)?.toDate() ?? DateTime.now();
        final key =
            '${date.year}-${date.month.toString().padLeft(2, '0')}';
        monthExpMap[key] = (monthExpMap[key] ?? 0) + amt;
      }

      // ── Build monthly stats (range) — oldest → newest ──
      final List<_MonthStat> monthStats = [];
      for (int i = 0; i < months; i++) {
        final dt = DateTime(rangeStart.year, rangeStart.month + i, 1);
        final key =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        final revMap = monthRevMap[key] ?? {};
        final rev = revMap.values.fold(0.0, (a, b) => a + b);
        final exp = monthExpMap[key] ?? 0;
        final label = DateFormat('MMM').format(dt);
        monthStats.add(_MonthStat(label, rev, exp, rev - exp));
      }

      // ── Build client growth — oldest → newest ──
      final List<_MonthCount> growth = [];
      for (int i = 0; i < months; i++) {
        final dt = DateTime(rangeStart.year, rangeStart.month + i, 1);
        final key =
            '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        growth.add(_MonthCount(DateFormat('MMM').format(dt),
            monthClientCount[key] ?? 0));
      }

      // Top 5 clients by revenue
      clientStats.sort((a, b) => b.revenue.compareTo(a.revenue));
      final top5 = clientStats.take(5).toList();

      final collRate =
      totalRev > 0 ? (completedRev / totalRev * 100) : 0.0;
      final avgDeal = clients.isNotEmpty ? totalRev / clients.length : 0.0;

      // ── Period-over-period trends (compare first half vs second half) ──
      double? revTrend, expTrend, profTrend;
      String bestMonthLbl = '';
      double bestMonthRev = 0;
      if (monthStats.length >= 2) {
        final half = monthStats.length ~/ 2;
        final firstHalfRev = monthStats.sublist(0, half).fold(0.0, (a, b) => a + b.revenue);
        final secondHalfRev = monthStats.sublist(half).fold(0.0, (a, b) => a + b.revenue);
        final firstHalfExp = monthStats.sublist(0, half).fold(0.0, (a, b) => a + b.expense);
        final secondHalfExp = monthStats.sublist(half).fold(0.0, (a, b) => a + b.expense);
        final firstHalfProfit = firstHalfRev - firstHalfExp;
        final secondHalfProfit = secondHalfRev - secondHalfExp;
        if (firstHalfRev > 0) revTrend = ((secondHalfRev - firstHalfRev) / firstHalfRev * 100);
        if (firstHalfExp > 0) expTrend = ((secondHalfExp - firstHalfExp) / firstHalfExp * 100);
        if (firstHalfProfit.abs() > 0) profTrend = ((secondHalfProfit - firstHalfProfit) / firstHalfProfit.abs() * 100);
      }
      if (monthStats.isNotEmpty) {
        final best = monthStats.reduce((a, b) => a.revenue > b.revenue ? a : b);
        bestMonthLbl = best.label;
        bestMonthRev = best.revenue;
      }

      setState(() {
        _data = _AnalyticsData(
          totalRevenue: totalRev,
          totalExpenses: totalExp,
          netProfit: totalRev - totalExp,
          totalClients: clients.length,
          totalInvoices: invoiceSnap.docs.length,
          collectionRate: collRate,
          avgDealSize: avgDeal,
          revenueTrend: revTrend,
          expenseTrend: expTrend,
          profitTrend: profTrend,
          bestMonthLabel: bestMonthLbl,
          bestMonthRevenue: bestMonthRev,
          statusDistribution: statusDist,
          statusCount: statusCnt,
          monthlyStats: monthStats,
          clientCategoryRevenue: catRev,
          shootCategoryRevenue: shootCatRev,
          reelCategoryRevenue: reelCatRev,
          paymentTypeDistribution: payTypeDist,
          expenseCategoryBreakdown: expCat,
          topClients: top5,
          clientGrowth: growth,
        );
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return WebScaffold(
      activeRoute: AppRoutes.analytics,
      appBar: AppBar(
        title: const Text('ANALYTICS'),
        leading: Navigator.canPop(context)
            ? IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Get.back(),
        )
            : null,
        actions: [
          // Period selector
          _PeriodSelector(
            selected: _selectedPeriod,
            onChanged: (p) {
              if (p == 'CUSTOM') {
                _pickCustomRange();
              } else {
                setState(() => _selectedPeriod = p);
                _loadData();
              }
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_selectedPeriod == 'CUSTOM' && _customFrom != null ? 112 : 84),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'OVERVIEW'),
                  Tab(text: 'CLIENTS'),
                  Tab(text: 'EXPENSES'),
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
              if (_selectedPeriod == 'CUSTOM' && _customFrom != null && _customTo != null)
                _CustomRangeLabel(from: _customFrom!, to: _customTo!, onTap: _pickCustomRange),
              if (!_loading) _QuickKpiStrip(data: _data),
            ],
          ),
        ),
      ),
      body: _loading
          ? Center(
        child: CircularProgressIndicator(color: c.primary),
      )
          : TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(data: _data),
          _ClientsTab(data: _data),
          _ExpensesTab(data: _data),
        ],
      ),
    );
  }
}

// ─── Quick KPI Strip (compact header bar) ─────────────────────
class _QuickKpiStrip extends StatelessWidget {
  final _AnalyticsData data;
  const _QuickKpiStrip({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Container(
      color: c.card,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _StripStat('REVENUE', '${fmt.format(data.totalRevenue)}',
              BillifyColors.primary, data.revenueTrend, c),
          Container(width: 0.5, height: 28, color: c.border),
          _StripStat('NET PROFIT', '${fmt.format(data.netProfit)}',
              data.netProfit >= 0 ? BillifyColors.paid : BillifyColors.overdue,
              data.profitTrend, c),
          Container(width: 0.5, height: 28, color: c.border),
          _StripStat('COLLECTION', '${data.collectionRate.toStringAsFixed(0)}%',
              BillifyColors.primaryLight, null, c),
        ],
      ),
    );
  }

  Widget _StripStat(String label, String value, Color color, double? trend, BillifyC c) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 7, fontWeight: FontWeight.w800,
                        letterSpacing: 1.0, color: c.textSecondary)),
                Text(value,
                    style: GoogleFonts.poppins(
                        fontSize: 11, fontWeight: FontWeight.w900, color: color)),
              ],
            ),
            if (trend != null)
              _TrendBadge(trend: trend),
          ],
        ),
      ),
    );
  }
}

// ─── Trend Badge (↑↓ % change) ───────────────────────────────
class _TrendBadge extends StatelessWidget {
  final double trend;
  const _TrendBadge({required this.trend});

  @override
  Widget build(BuildContext context) {
    final isUp = trend >= 0;
    final color = isUp ? BillifyColors.paid : BillifyColors.overdue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      color: color.withOpacity(0.1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              size: 8, color: color),
          const SizedBox(width: 2),
          Text(
            '${trend.abs().toStringAsFixed(0)}%',
            style: GoogleFonts.poppins(
                fontSize: 8, fontWeight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }
}

// ─── Period Selector ──────────────────────────────────────────
class _PeriodSelector extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _PeriodSelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: ['3M', '6M', '12M', 'CUSTOM'].map((p) {
        final active = p == selected;
        final isCustom = p == 'CUSTOM';
        return GestureDetector(
          onTap: () => onChanged(p),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: active
                  ? c.primary
                  : c.primary.withOpacity(0.08),
              borderRadius: BorderRadius.zero,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isCustom) ...[
                  Icon(
                    Icons.date_range_rounded,
                    size: 10,
                    color: active ? Colors.white : c.primary,
                  ),
                  const SizedBox(width: 3),
                ],
                Text(
                  p,
                  style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: active ? Colors.white : c.primary,
                    letterSpacing: 0.8,
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

// ─── Custom Range Label ───────────────────────────────────────
class _CustomRangeLabel extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final VoidCallback onTap;
  const _CustomRangeLabel({required this.from, required this.to, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final fmt = DateFormat('MMM yyyy');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: c.primary.withOpacity(0.06),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.date_range_rounded, size: 12, color: c.primary),
            const SizedBox(width: 6),
            Text(
              '${fmt.format(from)}  →  ${fmt.format(to)}',
              style: GoogleFonts.poppins(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: c.primary,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.edit_rounded, size: 11, color: c.primary.withOpacity(0.6)),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  OVERVIEW TAB
// ════════════════════════════════════════════════════════════

class _OverviewTab extends StatelessWidget {
  final _AnalyticsData data;
  const _OverviewTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final fullFmt =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // KPI Cards row
        _SectionTitle('KEY METRICS'),
        const SizedBox(height: 8),
        _KpiGrid(data: data),
        const SizedBox(height: 12),

        // Best month callout
        if (data.bestMonthLabel.isNotEmpty)
          _BestMonthBanner(label: data.bestMonthLabel, revenue: data.bestMonthRevenue),
        const SizedBox(height: 20),

        // Revenue vs Expense Bar Chart
        _SectionTitle('INCOME VS EXPENSE'),
        const SizedBox(height: 4),
        _ChartLegend(items: const [
          _LegendDot(color: BillifyColors.primary, label: 'Income'),
          _LegendDot(color: BillifyColors.unpaid, label: 'Expense'),
        ]),
        const SizedBox(height: 6),
        _ChartCard(
          height: 300,
          child: _IncomeExpenseBarChart(stats: data.monthlyStats),
        ),
        const SizedBox(height: 20),

        // Net Profit Line Chart
        _SectionTitle('NET PROFIT TREND'),
        const SizedBox(height: 4),
        _ChartLegend(items: const [
          _LegendDot(color: BillifyColors.paid, label: 'Net Profit'),
        ]),
        const SizedBox(height: 6),
        _ChartCard(
          height: 280,
          child: _NetProfitLineChart(stats: data.monthlyStats),
        ),
        const SizedBox(height: 20),

        // Payment Status Pie Chart
        _SectionTitle('PAYMENT STATUS DISTRIBUTION'),
        const SizedBox(height: 8),
        _ChartCard(
          height: 320,
          child: _StatusPieChart(
            distribution: data.statusDistribution,
            counts: data.statusCount,
          ),
        ),
        const SizedBox(height: 20),

        // Payment Type Pie Chart
        _SectionTitle('PAYMENT METHOD BREAKDOWN'),
        const SizedBox(height: 8),
        _ChartCard(
          height: 300,
          child: _PaymentTypePieChart(
              distribution: data.paymentTypeDistribution),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
//  CLIENTS TAB
// ════════════════════════════════════════════════════════════

class _ClientsTab extends StatelessWidget {
  final _AnalyticsData data;
  const _ClientsTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final topClient = data.topClients.isNotEmpty ? data.topClients.first : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top client callout
        if (topClient != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF7B61FF).withOpacity(0.07),
              border: Border(left: BorderSide(color: const Color(0xFF7B61FF), width: 3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.star_rounded, size: 16, color: Color(0xFF7B61FF)),
                const SizedBox(width: 8),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.poppins(fontSize: 10, color: c.textPrimary),
                      children: [
                        TextSpan(
                          text: 'TOP CLIENT  ',
                          style: GoogleFonts.poppins(
                              fontSize: 8, fontWeight: FontWeight.w800,
                              letterSpacing: 1.0, color: c.textSecondary),
                        ),
                        TextSpan(
                          text: topClient.name,
                          style: GoogleFonts.poppins(
                              fontSize: 11, fontWeight: FontWeight.w900,
                              color: const Color(0xFF7B61FF)),
                        ),
                        TextSpan(
                          text: '  ·  ${fmt.format(topClient.revenue)}',
                          style: GoogleFonts.poppins(
                              fontSize: 10, fontWeight: FontWeight.w700,
                              color: c.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Client Growth Line Chart
        _SectionTitle('CLIENT GROWTH (NEW CLIENTS/MONTH)'),
        const SizedBox(height: 4),
        _ChartLegend(items: const [
          _LegendDot(color: Color(0xFF3C5D9C), label: 'New Clients'),
        ]),
        const SizedBox(height: 6),
        _ChartCard(
          height: 280,
          child: _ClientGrowthBarChart(growth: data.clientGrowth),
        ),
        const SizedBox(height: 20),

        // Top Clients Horizontal Bar
        _SectionTitle('TOP CLIENTS BY REVENUE'),
        const SizedBox(height: 8),
        _ChartCard(
          height: 60.0 * (data.topClients.isEmpty ? 1 : data.topClients.length) + 48,
          child: _TopClientsChart(clients: data.topClients),
        ),
        const SizedBox(height: 20),

        // Client Category Donut
        _SectionTitle('CLIENT CATEGORY REVENUE'),
        const SizedBox(height: 8),
        _ChartCard(
          height: 320,
          child: _DonutChart(
            data: data.clientCategoryRevenue,
            centerLabel: 'Category',
          ),
        ),
        const SizedBox(height: 20),

        // Shoot Category Pie
        _SectionTitle('SHOOT CATEGORY BREAKDOWN'),
        const SizedBox(height: 8),
        _ChartCard(
          height: 300,
          child: _GenericPieChart(data: data.shootCategoryRevenue),
        ),
        const SizedBox(height: 20),

        // Reel Category Pie
        _SectionTitle('REEL CATEGORY BREAKDOWN'),
        const SizedBox(height: 8),
        _ChartCard(
          height: 300,
          child: _GenericPieChart(data: data.reelCategoryRevenue),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
//  EXPENSES TAB
// ════════════════════════════════════════════════════════════

class _ExpensesTab extends StatelessWidget {
  final _AnalyticsData data;
  const _ExpensesTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final ratio = data.totalRevenue > 0
        ? (data.totalExpenses / data.totalRevenue * 100)
        : 0.0;
    final isHealthy = ratio < 60;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Expense health insight
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: (isHealthy ? BillifyColors.paid : BillifyColors.overdue)
                .withOpacity(0.07),
            border: Border(
                left: BorderSide(
                    color: isHealthy ? BillifyColors.paid : BillifyColors.overdue,
                    width: 3)),
          ),
          child: Row(
            children: [
              Icon(
                isHealthy
                    ? Icons.thumb_up_rounded
                    : Icons.warning_amber_rounded,
                size: 16,
                color: isHealthy ? BillifyColors.paid : BillifyColors.overdue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isHealthy
                      ? 'Expense ratio is healthy at ${ratio.toStringAsFixed(1)}% of revenue.'
                      : 'High expense ratio: ${ratio.toStringAsFixed(1)}% of revenue spent. Review costs.',
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Expense summary
        _SectionTitle('EXPENSE SUMMARY'),
        const SizedBox(height: 8),
        _ExpenseSummaryCard(data: data),
        const SizedBox(height: 20),

        // Expense category donut
        _SectionTitle('EXPENSE CATEGORY BREAKDOWN'),
        const SizedBox(height: 8),
        _ChartCard(
          height: 340,
          child: _DonutChart(
            data: data.expenseCategoryBreakdown,
            centerLabel: 'Expenses',
          ),
        ),
        const SizedBox(height: 20),

        // Monthly Expense Bar
        _SectionTitle('MONTHLY EXPENSE TREND'),
        const SizedBox(height: 4),
        _ChartLegend(items: const [
          _LegendDot(color: BillifyColors.unpaid, label: 'Monthly Expense'),
        ]),
        const SizedBox(height: 6),
        _ChartCard(
          height: 280,
          child: _MonthlyExpenseBarChart(stats: data.monthlyStats),
        ),
        const SizedBox(height: 20),

        // Expense vs Revenue Ratio
        _SectionTitle('EXPENSE RATIO BY MONTH'),
        const SizedBox(height: 8),
        _ChartCard(
          height: 280,
          child: _ExpenseRatioLineChart(stats: data.monthlyStats),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
//  REUSABLE WIDGETS
// ════════════════════════════════════════════════════════════

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Row(
      children: [
        Container(width: 3, height: 14, color: c.primary),
        const SizedBox(width: 8),
        Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Best Month Banner ─────────────────────────────────────────
class _BestMonthBanner extends StatelessWidget {
  final String label;
  final double revenue;
  const _BestMonthBanner({required this.label, required this.revenue});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: BillifyColors.paid.withOpacity(0.07),
        border: Border(left: BorderSide(color: BillifyColors.paid, width: 3)),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events_rounded, size: 16, color: BillifyColors.paid),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.poppins(fontSize: 10, color: c.textPrimary),
                children: [
                  TextSpan(
                    text: 'BEST MONTH  ',
                    style: GoogleFonts.poppins(
                        fontSize: 8, fontWeight: FontWeight.w800,
                        letterSpacing: 1.0, color: c.textSecondary),
                  ),
                  TextSpan(
                    text: label,
                    style: GoogleFonts.poppins(
                        fontSize: 11, fontWeight: FontWeight.w900,
                        color: BillifyColors.paid),
                  ),
                  TextSpan(
                    text: '  ·  ${fmt.format(revenue)}',
                    style: GoogleFonts.poppins(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: c.textPrimary),
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

// ── Chart Legend Row ──────────────────────────────────────────
class _LegendDot {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
}

class _ChartLegend extends StatelessWidget {
  final List<_LegendDot> items;
  const _ChartLegend({required this.items});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Row(
      children: items.map((d) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: d.color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Text(d.label,
                style: GoogleFonts.poppins(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: c.textSecondary)),
          ],
        ),
      )).toList(),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final Widget child;
  final double height;
  const _ChartCard({required this.child, required this.height});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border, width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

// ── KPI Grid ──────────────────────────────────────────────────
class _KpiGrid extends StatelessWidget {
  final _AnalyticsData data;
  const _KpiGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final fmt =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final c = BillifyC.of(context);

    final kpis = [
      _Kpi('Total Revenue', fmt.format(data.totalRevenue), Icons.trending_up_rounded, BillifyColors.primary, data.revenueTrend),
      _Kpi('Total Expenses', fmt.format(data.totalExpenses), Icons.trending_down_rounded, BillifyColors.unpaid, data.expenseTrend),
      _Kpi('Net Profit', fmt.format(data.netProfit), Icons.account_balance_rounded,
          data.netProfit >= 0 ? BillifyColors.paid : BillifyColors.overdue, data.profitTrend),
      _Kpi('Total Clients', '${data.totalClients}', Icons.people_rounded, const Color(0xFF7B61FF), null),
      _Kpi('Collection Rate', '${data.collectionRate.toStringAsFixed(1)}%', Icons.pie_chart_rounded, BillifyColors.primaryLight, null),
      _Kpi('Avg Deal Size', fmt.format(data.avgDealSize), Icons.handshake_rounded, const Color(0xFF00ACC1), null),
    ];

    // 2-col grid: 3 rows x 2 cards — readable and balanced
    final rows = [
      kpis.sublist(0, 2),
      kpis.sublist(2, 4),
      kpis.sublist(4, 6),
    ];

    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Expanded(child: _KpiCard(kpi: row[0])),
              const SizedBox(width: 8),
              Expanded(child: _KpiCard(kpi: row[1])),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _Kpi {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double? trend;
  const _Kpi(this.label, this.value, this.icon, this.color, this.trend);
}

class _KpiCard extends StatelessWidget {
  final _Kpi kpi;
  const _KpiCard({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(
          left: BorderSide(color: kpi.color, width: 3),
          top: BorderSide(color: c.border, width: 0.5),
          right: BorderSide(color: c.border, width: 0.5),
          bottom: BorderSide(color: c.border, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label + icon row
          Row(
            children: [
              Icon(kpi.icon, color: kpi.color, size: 12),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  kpi.label.toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: c.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (kpi.trend != null) _TrendBadge(trend: kpi.trend!),
            ],
          ),
          const SizedBox(height: 6),
          // Value
          Text(
            kpi.value,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: kpi.color,
              letterSpacing: -0.3,
              height: 1.1,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Expense Summary Card ─────────────────────────────────────
class _ExpenseSummaryCard extends StatelessWidget {
  final _AnalyticsData data;
  const _ExpenseSummaryCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final fmt =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final ratio =
    data.totalRevenue > 0 ? (data.totalExpenses / data.totalRevenue * 100) : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.border, width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              _SummaryItem('Total Expenses', fmt.format(data.totalExpenses),
                  BillifyColors.unpaid, c),
              const SizedBox(width: 16),
              _SummaryItem('Expense Ratio',
                  '${ratio.toStringAsFixed(1)}%', BillifyColors.overdue, c),
              const SizedBox(width: 16),
              _SummaryItem('Net Profit', fmt.format(data.netProfit),
                  data.netProfit >= 0 ? BillifyColors.paid : BillifyColors.overdue, c),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.zero,
            child: LinearProgressIndicator(
              value: data.totalRevenue > 0
                  ? (data.totalExpenses / data.totalRevenue).clamp(0, 1)
                  : 0,
              backgroundColor: BillifyColors.paid.withOpacity(0.2),
              valueColor:
              const AlwaysStoppedAnimation<Color>(BillifyColors.unpaid),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Revenue', style: GoogleFonts.poppins(fontSize: 9, color: c.textSecondary)),
              Text('${ratio.toStringAsFixed(1)}% spent',
                  style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: BillifyColors.unpaid)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _SummaryItem(String label, String value, Color color, BillifyC c) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: c.textSecondary,
                  letterSpacing: 0.5)),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: color)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  CHART WIDGETS
// ════════════════════════════════════════════════════════════

// Chart color palette
const _kChartColors = [
  Color(0xFF3C5D9C),
  Color(0xFF536073),
  Color(0xFF9F403D),
  Color(0xFF7B61FF),
  Color(0xFF00ACC1),
  Color(0xFFFF7043),
  Color(0xFF66BB6A),
  Color(0xFFFFCA28),
  Color(0xFFAB47BC),
  Color(0xFF26A69A),
];

Color _chartColor(int i) => _kChartColors[i % _kChartColors.length];

// ── Income vs Expense Bar Chart ───────────────────────────────
class _IncomeExpenseBarChart extends StatelessWidget {
  final List<_MonthStat> stats;
  const _IncomeExpenseBarChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return _EmptyChart();
    final c = BillifyC.of(context);
    final maxY = stats
        .map((s) => math.max(s.revenue, s.expense))
        .fold(0.0, math.max) *
        1.2;

    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 100 : maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, gi, rod, ri) {
              final s = stats[group.x];
              final label = ri == 0 ? 'Income' : 'Expense';
              final val = ri == 0 ? s.revenue : s.expense;
              return BarTooltipItem(
                '$label\n${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(val)}',
                GoogleFonts.poppins(fontSize: 11, color: Colors.white),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (v, _) => Text(
                NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v),
                style:
                GoogleFonts.poppins(fontSize: 10, color: c.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= stats.length) return const SizedBox();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    stats[i].label,
                    style: GoogleFonts.poppins(
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: c.textSecondary),
                  ),
                );
              },
            ),
          ),
          rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
              color: c.border, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        barGroups: stats.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.revenue,
                color: BillifyColors.primary,
                width: 12,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  topRight: Radius.circular(3),
                ),
              ),
              BarChartRodData(
                toY: e.value.expense,
                color: BillifyColors.unpaid.withOpacity(0.85),
                width: 12,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  topRight: Radius.circular(3),
                ),
              ),
            ],
            barsSpace: 4,
          );
        }).toList(),
      ),
    );
  }
}

// ── Net Profit Line Chart ─────────────────────────────────────
class _NetProfitLineChart extends StatelessWidget {
  final List<_MonthStat> stats;
  const _NetProfitLineChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return _EmptyChart();
    final c = BillifyC.of(context);
    final maxY = stats.map((s) => s.netProfit.abs()).fold(0.0, math.max) * 1.3;

    return LineChart(
      LineChartData(
        minY: -maxY * 0.3,
        maxY: maxY == 0 ? 100 : maxY,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final stat = stats[s.x.toInt()];
              return LineTooltipItem(
                '${stat.label}\n${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(s.y)}',
                GoogleFonts.poppins(fontSize: 11, color: Colors.white),
              );
            }).toList(),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (v, _) => Text(
                NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v),
                style: GoogleFonts.poppins(fontSize: 10, color: c.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= stats.length) return const SizedBox();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(stats[i].label,
                      style: GoogleFonts.poppins(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: c.textSecondary)),
                );
              },
            ),
          ),
          rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: c.border, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(y: 0, color: c.border, strokeWidth: 1),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: stats.asMap().entries.map((e) {
              return FlSpot(e.key.toDouble(), e.value.netProfit);
            }).toList(),
            isCurved: true,
            curveSmoothness: 0.3,
            color: BillifyColors.paid,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                radius: 4,
                color: BillifyColors.paid,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: BillifyColors.paid.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status Pie Chart ──────────────────────────────────────────
class _StatusPieChart extends StatefulWidget {
  final Map<String, double> distribution;
  final Map<String, int> counts;
  const _StatusPieChart(
      {required this.distribution, required this.counts});

  @override
  State<_StatusPieChart> createState() => _StatusPieChartState();
}

class _StatusPieChartState extends State<_StatusPieChart> {
  int _touched = -1;

  Color _statusColor(String status) {
    switch (status) {
      case 'Completed':
        return BillifyColors.paid;
      case 'Advance':
        return BillifyColors.primary;
      case 'Pending':
        return const Color(0xFFFFCA28);
      case 'Overdue':
        return BillifyColors.overdue;
      default:
        return BillifyColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final entries = widget.distribution.entries.toList();
    if (entries.isEmpty) return _EmptyChart();

    final total = entries.fold(0.0, (s, e) => s + e.value);
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  setState(() {
                    _touched = response?.touchedSection?.touchedSectionIndex ?? -1;
                  });
                },
              ),
              sectionsSpace: 3,
              centerSpaceRadius: 0,
              sections: entries.asMap().entries.map((e) {
                final isTouched = e.key == _touched;
                final pct = total > 0 ? e.value.value / total * 100 : 0;
                return PieChartSectionData(
                  color: _statusColor(e.value.key),
                  value: e.value.value,
                  title: '${pct.toStringAsFixed(0)}%',
                  radius: isTouched ? 110 : 92,
                  titleStyle: GoogleFonts.poppins(
                    fontSize: isTouched ? 13 : 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  titlePositionPercentageOffset: 0.62,
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries.map((e) {
              final count = widget.counts[e.key] ?? 0;
              return _LegendItem(
                color: _statusColor(e.key),
                label: e.key,
                value: '${fmt.format(e.value)}',
                subtitle: '$count client${count == 1 ? '' : 's'}',
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Payment Type Pie Chart ────────────────────────────────────
class _PaymentTypePieChart extends StatefulWidget {
  final Map<String, double> distribution;
  const _PaymentTypePieChart({required this.distribution});

  @override
  State<_PaymentTypePieChart> createState() => _PaymentTypePieChartState();
}

class _PaymentTypePieChartState extends State<_PaymentTypePieChart> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final entries = widget.distribution.entries.toList();
    if (entries.isEmpty) return _EmptyChart();

    final total = entries.fold(0.0, (s, e) => s + e.value);
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  setState(() {
                    _touched = response?.touchedSection?.touchedSectionIndex ?? -1;
                  });
                },
              ),
              sectionsSpace: 3,
              centerSpaceRadius: 36,
              sections: entries.asMap().entries.map((e) {
                final isTouched = e.key == _touched;
                final pct = total > 0 ? e.value.value / total * 100 : 0;
                return PieChartSectionData(
                  color: _chartColor(e.key),
                  value: e.value.value,
                  title: '${pct.toStringAsFixed(0)}%',
                  radius: isTouched ? 96 : 80,
                  titleStyle: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  titlePositionPercentageOffset: 0.65,
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries.asMap().entries.map((e) {
              return _LegendItem(
                color: _chartColor(e.key),
                label: e.value.key,
                value: '${fmt.format(e.value.value)}',
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Generic Pie Chart ─────────────────────────────────────────
class _GenericPieChart extends StatefulWidget {
  final Map<String, double> data;
  const _GenericPieChart({required this.data});

  @override
  State<_GenericPieChart> createState() => _GenericPieChartState();
}

class _GenericPieChartState extends State<_GenericPieChart> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final entries = widget.data.entries.toList();
    if (entries.isEmpty) return _EmptyChart();

    final total = entries.fold(0.0, (s, e) => s + e.value);
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final c = BillifyC.of(context);

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  setState(() {
                    _touched = response?.touchedSection?.touchedSectionIndex ?? -1;
                  });
                },
              ),
              sectionsSpace: 3,
              centerSpaceRadius: 0,
              sections: entries.asMap().entries.map((e) {
                final isTouched = e.key == _touched;
                final pct = total > 0 ? e.value.value / total * 100 : 0;
                return PieChartSectionData(
                  color: _chartColor(e.key),
                  value: e.value.value,
                  title: '${pct.toStringAsFixed(0)}%',
                  radius: isTouched ? 108 : 90,
                  titleStyle: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                  titlePositionPercentageOffset: 0.62,
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries.asMap().entries.map((e) {
              return _LegendItem(
                color: _chartColor(e.key),
                label: e.value.key,
                value: '${fmt.format(e.value.value)}',
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Donut Chart ───────────────────────────────────────────────
class _DonutChart extends StatefulWidget {
  final Map<String, double> data;
  final String centerLabel;
  const _DonutChart({required this.data, required this.centerLabel});

  @override
  State<_DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<_DonutChart> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final entries = widget.data.entries.toList();
    if (entries.isEmpty) return _EmptyChart();

    final total = entries.fold(0.0, (s, e) => s + e.value);
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    final c = BillifyC.of(context);

    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      setState(() {
                        _touched = response?.touchedSection?.touchedSectionIndex ?? -1;
                      });
                    },
                  ),
                  sectionsSpace: 3,
                  centerSpaceRadius: 60,
                  sections: entries.asMap().entries.map((e) {
                    final isTouched = e.key == _touched;
                    final pct = total > 0 ? e.value.value / total * 100 : 0;
                    return PieChartSectionData(
                      color: _chartColor(e.key),
                      value: e.value.value,
                      title: isTouched
                          ? '${pct.toStringAsFixed(1)}%'
                          : '',
                      radius: isTouched ? 90 : 76,
                      titleStyle: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    );
                  }).toList(),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${fmt.format(total)}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: c.textPrimary,
                    ),
                  ),
                  Text(
                    widget.centerLabel,
                    style: GoogleFonts.poppins(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: entries.asMap().entries.map((e) {
                final pct = total > 0 ? e.value.value / total * 100 : 0;
                return _LegendItem(
                  color: _chartColor(e.key),
                  label: e.value.key,
                  value: '${pct.toStringAsFixed(1)}%',
                  subtitle: '${fmt.format(e.value.value)}',
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Client Growth Bar Chart ───────────────────────────────────
class _ClientGrowthBarChart extends StatelessWidget {
  final List<_MonthCount> growth;
  const _ClientGrowthBarChart({required this.growth});

  @override
  Widget build(BuildContext context) {
    if (growth.isEmpty) return _EmptyChart();
    final c = BillifyC.of(context);
    final maxY =
        growth.map((g) => g.count.toDouble()).fold(0.0, math.max) * 1.3;

    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 10 : maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, gi, rod, ri) {
              final g = growth[group.x];
              return BarTooltipItem(
                '${g.label}: ${g.count} clients',
                GoogleFonts.poppins(fontSize: 11, color: Colors.white),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              interval: (maxY / 4).ceilToDouble().clamp(1, 999999),
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: GoogleFonts.poppins(fontSize: 10, color: c.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= growth.length) return const SizedBox();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(growth[i].label,
                      style: GoogleFonts.poppins(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: c.textSecondary)),
                );
              },
            ),
          ),
          rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: c.border, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        barGroups: growth.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.count.toDouble(),
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    BillifyColors.primary.withOpacity(0.6),
                    BillifyColors.primary,
                  ],
                ),
                width: 24,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  topRight: Radius.circular(3),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── Top Clients Chart (Horizontal Bar) ───────────────────────
class _TopClientsChart extends StatelessWidget {
  final List<_ClientStat> clients;
  const _TopClientsChart({required this.clients});

  @override
  Widget build(BuildContext context) {
    if (clients.isEmpty) return _EmptyChart();
    final c = BillifyC.of(context);
    final maxVal = clients.map((c) => c.revenue).fold(0.0, math.max);
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

    return Column(
      children: clients.asMap().entries.map((e) {
        final pct = maxVal > 0 ? e.value.revenue / maxVal : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  e.value.name,
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: _chartColor(e.key).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: pct,
                      child: Container(
                        height: 28,
                        decoration: BoxDecoration(
                          color: _chartColor(e.key),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${fmt.format(e.value.revenue)}',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Monthly Expense Bar Chart ─────────────────────────────────
class _MonthlyExpenseBarChart extends StatelessWidget {
  final List<_MonthStat> stats;
  const _MonthlyExpenseBarChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return _EmptyChart();
    final c = BillifyC.of(context);
    final maxY =
        stats.map((s) => s.expense).fold(0.0, math.max) * 1.3;

    return BarChart(
      BarChartData(
        maxY: maxY == 0 ? 100 : maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, gi, rod, ri) {
              final s = stats[group.x];
              return BarTooltipItem(
                '${s.label}: ₹${NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(s.expense)}',
                GoogleFonts.poppins(fontSize: 11, color: Colors.white),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (v, _) => Text(
                NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0).format(v),
                style: GoogleFonts.poppins(fontSize: 10, color: c.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= stats.length) return const SizedBox();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(stats[i].label,
                      style: GoogleFonts.poppins(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: c.textSecondary)),
                );
              },
            ),
          ),
          rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: c.border, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        barGroups: stats.asMap().entries.map((e) {
          return BarChartGroupData(
            x: e.key,
            barRods: [
              BarChartRodData(
                toY: e.value.expense,
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    BillifyColors.unpaid.withOpacity(0.6),
                    BillifyColors.unpaid,
                  ],
                ),
                width: 24,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(3),
                  topRight: Radius.circular(3),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── Expense Ratio Line Chart ──────────────────────────────────
class _ExpenseRatioLineChart extends StatelessWidget {
  final List<_MonthStat> stats;
  const _ExpenseRatioLineChart({required this.stats});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return _EmptyChart();
    final c = BillifyC.of(context);

    final ratios = stats.map((s) {
      return s.revenue > 0 ? (s.expense / s.revenue * 100) : 0.0;
    }).toList();

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 120,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              return LineTooltipItem(
                '${stats[s.x.toInt()].label}: ${s.y.toStringAsFixed(1)}%',
                GoogleFonts.poppins(fontSize: 11, color: Colors.white),
              );
            }).toList(),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, _) => Text(
                '${v.toInt()}%',
                style: GoogleFonts.poppins(fontSize: 10, color: c.textSecondary),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= stats.length) return const SizedBox();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(stats[i].label,
                      style: GoogleFonts.poppins(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: c.textSecondary)),
                );
              },
            ),
          ),
          rightTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
          const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: c.border, strokeWidth: 0.5),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: 100,
              color: BillifyColors.overdue.withOpacity(0.4),
              strokeWidth: 1,
              dashArray: [5, 4],
              label: HorizontalLineLabel(
                show: true,
                labelResolver: (_) => '100%',
                style: GoogleFonts.poppins(
                    fontSize: 8, color: BillifyColors.overdue),
              ),
            ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: ratios.asMap().entries.map((e) {
              return FlSpot(e.key.toDouble(), e.value);
            }).toList(),
            isCurved: true,
            curveSmoothness: 0.25,
            color: BillifyColors.overdue,
            barWidth: 3,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, pct, bar, idx) => FlDotCirclePainter(
                radius: 4,
                color: BillifyColors.overdue,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: BillifyColors.overdue.withOpacity(0.12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Legend Item ───────────────────────────────────────────────
class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  final String? subtitle;
  const _LegendItem(
      {required this.color,
        required this.label,
        required this.value,
        this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              )),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle != null ? '$value  ·  $subtitle' : value,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    color: c.textSecondary,
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

// ── Empty Chart Placeholder ───────────────────────────────────
class _EmptyChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_rounded, size: 40, color: c.border),
          const SizedBox(height: 8),
          Text('No data yet',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: c.textSecondary)),
        ],
      ),
    );
  }
}