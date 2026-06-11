import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import 'main.dart' show BillifyColors, AppRoutes, BillifyC;
import 'theme_controller.dart' show ThemeController;
import 'web_layout.dart' show WebScaffold;
import 'client_screens.dart' show ClientModel, ReelEntry;

// ─── Model ────────────────────────────────────────────────────────────────────

class ScheduleShoot {
  final String clientId;
  final String clientName;
  final ReelEntry reel;
  final DateTime date;

  const ScheduleShoot({
    required this.clientId,
    required this.clientName,
    required this.reel,
    required this.date,
  });
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with TickerProviderStateMixin {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;
  PageController? _pageController;
  String _viewMode = 'Month';
  bool _panelOpen = false;

  late final Stream<QuerySnapshot> _stream;
  late final AnimationController _headerCtrl;
  late final Animation<double> _headerAnim;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _stream = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('clients')
        .snapshots();
    _headerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _headerAnim = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOutCubic);
    _headerCtrl.forward();
  }

  @override
  void dispose() {
    _headerCtrl.dispose();
    super.dispose();
  }

  // ── Data helpers ─────────────────────────────────────────────────────────────

  List<ScheduleShoot> _extractShoots(List<DocumentSnapshot> docs) {
    final result = <ScheduleShoot>[];
    for (final doc in docs) {
      final client = ClientModel.fromDoc(doc);
      for (final reel in client.reels) {
        result.add(ScheduleShoot(
          clientId: client.id,
          clientName: client.name,
          reel: reel,
          date: reel.projectStartDate ?? client.createdAt,
        ));
      }
    }
    return result;
  }

  Map<DateTime, List<ScheduleShoot>> _group(List<ScheduleShoot> shoots) {
    final map = <DateTime, List<ScheduleShoot>>{};
    for (final s in shoots) {
      final key = DateTime(s.date.year, s.date.month, s.date.day);
      (map[key] ??= []).add(s);
    }
    return map;
  }

  List<ScheduleShoot> _eventsFor(
      Map<DateTime, List<ScheduleShoot>> map, DateTime day) {
    return map[DateTime(day.year, day.month, day.day)] ?? [];
  }

  // ── Interaction ───────────────────────────────────────────────────────────────

  void _onDaySelected(
      DateTime day, Map<DateTime, List<ScheduleShoot>> eventsMap) {
    final events = _eventsFor(eventsMap, day);
    final sameDay = isSameDay(_selectedDay, day);

    setState(() {
      _selectedDay = day;
      _focusedDay = day;
    });

    if (events.isEmpty) {
      if (_panelOpen) {
        setState(() => _panelOpen = false);
      }
      return;
    }

    if (!_panelOpen) {
      setState(() => _panelOpen = true);
    } else if (sameDay) {
      setState(() => _panelOpen = false);
    }
  }

  void _closePanel() {
    setState(() => _panelOpen = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return WebScaffold(
      activeRoute: AppRoutes.schedule,
      appBar: _buildAppBar(),
      body: StreamBuilder<QuerySnapshot>(
        stream: _stream,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(
                color: ThemeController.to.primary,
                strokeWidth: 2,
              ),
            );
          }
          if (snap.hasError) {
            return _ErrorState('Failed to load schedule');
          }

          final shoots = _extractShoots(snap.data?.docs ?? []);
          final eventsMap = _group(shoots);
          final allShoots = [...shoots]
            ..sort((a, b) => a.date.compareTo(b.date));
          final selectedEvents = _selectedDay != null
              ? _eventsFor(eventsMap, _selectedDay!)
              : <ScheduleShoot>[];

          return Column(
            children: [
              // ── Nav header ────────────────────────────────────────────────
              _buildHeader(),
              // ── Body ──────────────────────────────────────────────────────
              if (_viewMode == 'List')
                Expanded(child: _buildList(allShoots, isFullList: true))
              else
                Expanded(
                  child: Stack(
                    children: [
                      // Calendar fills full area
                      Positioned.fill(
                        child: _buildCalendar(eventsMap),
                      ),
                      // Scrim
                      if (_panelOpen)
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: _closePanel,
                            child: AnimatedOpacity(
                              opacity: _panelOpen ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 220),
                              child: Container(
                                color: Colors.black.withOpacity(0.18),
                              ),
                            ),
                          ),
                        ),
                      // Right-side detail panel
                      Positioned(
                        top: 0,
                        bottom: 0,
                        right: 0,
                        width: 300,
                        child: AnimatedSlide(
                          offset: _panelOpen
                              ? Offset.zero
                              : const Offset(1.0, 0.0),
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          child: AnimatedOpacity(
                            opacity: _panelOpen ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 220),
                            child: _buildSidePanel(selectedEvents),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: BillifyColors.background,
      elevation: 0,
      title: Text(
        'CALENDAR',
        style: GoogleFonts.poppins(
          color: ThemeController.to.primary,
          fontSize: 13,
          fontWeight: FontWeight.w900,
          letterSpacing: 2.5,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(
          height: 1,
          thickness: 1,
          color: BillifyColors.outlineVariant.withOpacity(0.35),
        ),
      ),
    );
  }

  // ── Header row (nav + title + toggle) ─────────────────────────────────────────

  Widget _buildHeader() {
    final c = BillifyC.of(context);
    final slideAnim = Tween<Offset>(
      begin: const Offset(0, -0.4),
      end: Offset.zero,
    ).animate(_headerAnim);
    return FadeTransition(
      opacity: _headerAnim,
      child: SlideTransition(
        position: slideAnim,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              // Today button
              _PillButton(
                label: 'Today',
                onTap: () {
                  final now = DateTime.now();
                  setState(() {
                    _focusedDay = now;
                    _selectedDay = now;
                  });
                  _pageController?.jumpToPage(0);
                },
              ),
              const SizedBox(width: 6),
              // Prev
              _PillButton(
                icon: Icons.chevron_left_rounded,
                onTap: () => _pageController?.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                ),
              ),
              const SizedBox(width: 4),
              // Next
              _PillButton(
                icon: Icons.chevron_right_rounded,
                onTap: () => _pageController?.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                ),
              ),
              const SizedBox(width: 12),
              // Month / Year label — cross-fades on navigation
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.15, 0),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    DateFormat('MMMM yyyy').format(_focusedDay),
                    key: ValueKey(_focusedDay.month * 10000 + _focusedDay.year),
                    style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),
              ),
              // View toggle
              _SegmentedToggle(
                options: const ['Month', 'Week', 'List'],
                selected: _viewMode,
                onSelect: (v) {
                  setState(() {
                    _viewMode = v;
                    _calendarFormat = v == 'Week'
                        ? CalendarFormat.week
                        : CalendarFormat.month;
                    if (v == 'List' && _panelOpen) _closePanel();
                  });
                },
              ),
            ],
          ),
        ), // Padding
      ), // SlideTransition
    ); // FadeTransition
  }

  // ── Calendar ──────────────────────────────────────────────────────────────────

  Widget _buildCalendar(Map<DateTime, List<ScheduleShoot>> eventsMap) {
    return LayoutBuilder(builder: (context, constraints) {
      final rowCount = _calendarFormat == CalendarFormat.week ? 1 : 6;
      const dowH = 36.0;
      // Subtract 1px safety margin so table_calendar never overflows by a rounding pixel
      final availH = constraints.maxHeight - dowH - 1;
      final rowH = (availH / rowCount).floorToDouble().clamp(56.0, 120.0);

      final calendarH = dowH + rowCount * rowH;

      return Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: BillifyColors.outlineVariant.withOpacity(0.2),
              width: 1,
            ),
          ),
        ),
        child: SizedBox(
          height: calendarH,
          child: TableCalendar<ScheduleShoot>(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
            calendarFormat: _calendarFormat,
            eventLoader: (d) => _eventsFor(eventsMap, d),
            startingDayOfWeek: StartingDayOfWeek.sunday,
            onDaySelected: (sel, foc) {
              setState(() => _focusedDay = foc);
              _onDaySelected(sel, eventsMap);
            },
            onPageChanged: (foc) => setState(() => _focusedDay = foc),
            onCalendarCreated: (ctrl) => _pageController = ctrl,
            headerVisible: false,
            daysOfWeekHeight: dowH,
            rowHeight: rowH,
            calendarStyle: const CalendarStyle(
              markersMaxCount: 0,
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              dowTextFormatter: (d, locale) => DateFormat.E(locale).format(d),
              weekdayStyle: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: BillifyColors.textSecondary.withOpacity(0.7),
                letterSpacing: 0.2,
              ),
              weekendStyle: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: BillifyColors.textSecondary.withOpacity(0.45),
                letterSpacing: 0.2,
              ),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (ctx, d, f) => _cell(d, f, eventsMap),
              todayBuilder: (ctx, d, f) =>
                  _cell(d, f, eventsMap, isToday: true),
              selectedBuilder: (ctx, d, f) =>
                  _cell(d, f, eventsMap, isSelected: true),
              outsideBuilder: (ctx, d, f) =>
                  _cell(d, f, eventsMap, isOutside: true),
            ),
          ), // TableCalendar
        ), // SizedBox
      ); // Container
    });
  }

  // ── Calendar cell ─────────────────────────────────────────────────────────────

  Widget _cell(
      DateTime day,
      DateTime focusedDay,
      Map<DateTime, List<ScheduleShoot>> eventsMap, {
        bool isSelected = false,
        bool isOutside = false,
        bool isToday = false,
      }) {
    final events = _eventsFor(eventsMap, day);
    final c = BillifyC.of(context);
    final primary = ThemeController.to.primary;
    final faded = isOutside || day.month != focusedDay.month;

    final int reelCount = events.length;
    final int clientCount = events.map((e) => e.clientId).toSet().length;

    // Colors
    final Color bg = isSelected ? primary : Colors.white;

    final Color border = isSelected
        ? primary
        : isToday
        ? primary.withOpacity(0.5)
        : BillifyColors.outlineVariant.withOpacity(faded ? 0.10 : 0.30);

    final Color numColor = faded
        ? c.textPrimary.withOpacity(0.20)
        : isSelected
        ? Colors.white
        : isToday
        ? primary
        : c.textPrimary;

    final Color labelColor = isSelected
        ? Colors.white.withOpacity(0.85)
        : faded
        ? c.textSecondary.withOpacity(0.25)
        : c.textSecondary;

    final Color barBg = isSelected
        ? Colors.white.withOpacity(0.25)
        : primary.withOpacity(faded ? 0.06 : 0.12);

    final Color barFill = isSelected
        ? Colors.white.withOpacity(0.90)
        : faded
        ? primary.withOpacity(0.18)
        : primary;

    // Progress value: fraction of clients that have all reels paid
    final double progress = reelCount == 0
        ? 0.0
        : (events.where((e) => e.reel.paymentStatus == 'Completed').length /
        reelCount)
        .clamp(0.0, 1.0);

    return SizedBox.expand(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(
            color: border,
            width: isSelected || isToday ? 1.8 : 1.0,
          ),
          borderRadius: BorderRadius.circular(9),
          boxShadow: isSelected
              ? [
            BoxShadow(
              color: primary.withOpacity(0.22),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top: date number top-right ──────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 7, 0),
                child: Align(
                  alignment: Alignment.topRight,
                  child: Text(
                    '${day.day}',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: numColor,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // ── Middle: stats labels ────────────────────────────────────
              if (!faded && reelCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 4, 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StatLabel(
                        label: 'Reels= $reelCount',
                        color: labelColor,
                        isSelected: isSelected,
                      ),
                      const SizedBox(height: 1),
                      _StatLabel(
                        label: 'Clients= $clientCount',
                        color: labelColor,
                        isSelected: isSelected,
                      ),
                    ],
                  ),
                ),
              // ── Bottom: progress bar ────────────────────────────────────
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                child: _TileProgressBar(
                  progress: progress,
                  hasEvents: reelCount > 0 && !faded,
                  barBg: barBg,
                  barFill: barFill,
                  dotColor: barFill,
                  dotCount: clientCount.clamp(0, 4),
                ),
              ),
            ],
          ),
        ), // ClipRRect
      ),
    );
  }

  // ── Side panel (slides in from right) ────────────────────────────────────────

  Widget _buildSidePanel(List<ScheduleShoot> events) {
    final c = BillifyC.of(context);
    final primary = ThemeController.to.primary;
    final dateLabel = _selectedDay != null
        ? DateFormat('EEEE, d MMMM').format(_selectedDay!)
        : '';
    final monthLabel = _selectedDay != null
        ? DateFormat('MMM yyyy').format(_selectedDay!).toUpperCase()
        : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          bottomLeft: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.13),
            blurRadius: 24,
            offset: const Offset(-6, 0),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Panel header ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 14, 14),
            decoration: BoxDecoration(
              color: primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        monthLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.65),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateLabel,
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${events.length} shoot${events.length == 1 ? '' : 's'}',
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Close button
                GestureDetector(
                  onTap: _closePanel,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // ── Shoots list ───────────────────────────────────────────────────
          Expanded(child: _buildList(events)),
        ],
      ),
    );
  }

  // ── List (shared by panel + List view) ────────────────────────────────────────

  Widget _buildList(List<ScheduleShoot> events, {bool isFullList = false}) {
    if (events.isEmpty) {
      return _EmptyState(isFullList: isFullList);
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(14, isFullList ? 14 : 8, 14, 14),
      itemCount: events.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _AnimatedListItem(
        index: i,
        child: _ShootCard(
          shoot: events[i],
          compact: !isFullList,
        ),
      ),
    );
  }
}

// ─── Animated list item (staggered entrance) ─────────────────────────────────

class _AnimatedListItem extends StatefulWidget {
  final int index;
  final Widget child;
  const _AnimatedListItem({required this.index, required this.child});

  @override
  State<_AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<_AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0.12, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    // Stagger by index
    Future.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ─── Shoot Card ───────────────────────────────────────────────────────────────

class _ShootCard extends StatefulWidget {
  final ScheduleShoot shoot;
  final bool compact;

  const _ShootCard({required this.shoot, this.compact = false});

  @override
  State<_ShootCard> createState() => _ShootCardState();
}

class _ShootCardState extends State<_ShootCard>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.025).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = BillifyC.of(context);
    final primary = ThemeController.to.primary;
    final isPaid = widget.shoot.reel.paymentStatus == 'Completed';
    final statusColor = isPaid ? BillifyColors.paid : BillifyColors.unpaid;

    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        _scaleCtrl.forward();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        _scaleCtrl.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: _hovered
                ? [
              BoxShadow(
                color: primary.withOpacity(0.12),
                blurRadius: 14,
                offset: const Offset(0, 4),
              )
            ]
                : [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () =>
                  Get.toNamed(AppRoutes.clientDetail, arguments: widget.shoot.clientId),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: widget.compact ? 10 : 14,
                ),
                decoration: BoxDecoration(
                  color: _hovered ? const Color(0xFFF8FAFF) : c.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _hovered
                        ? primary.withOpacity(0.35)
                        : BillifyColors.outlineVariant.withOpacity(0.32),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Status stripe
                    Container(
                      width: 3,
                      height: widget.compact ? 40 : 54,
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Date block — full list only
                    if (!widget.compact) ...[
                      SizedBox(
                        width: 36,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('dd').format(widget.shoot.date),
                              style: GoogleFonts.poppins(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: primary,
                                height: 1,
                              ),
                            ),
                            Text(
                              DateFormat('MMM').format(widget.shoot.date).toUpperCase(),
                              style: GoogleFonts.poppins(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: primary.withOpacity(0.65),
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 36,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        color: BillifyColors.outlineVariant.withOpacity(0.3),
                      ),
                    ],
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Name + amount
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.shoot.clientName,
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.w700,
                                    fontSize: widget.compact ? 13 : 14,
                                    color: c.textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '₹${NumberFormat('#,##,###').format(widget.shoot.reel.paymentAmount)}',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w800,
                                  fontSize: widget.compact ? 12 : 14,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Meta row
                          Row(
                            children: [
                              _Chip(widget.shoot.reel.displayShootCategory.toUpperCase()),
                              const SizedBox(width: 6),
                              Icon(Icons.access_time_rounded,
                                  size: 11,
                                  color: c.textSecondary.withOpacity(0.55)),
                              const SizedBox(width: 3),
                              Text(
                                widget.compact
                                    ? DateFormat('hh:mm a').format(widget.shoot.date)
                                    : DateFormat('hh:mm a · d MMM').format(widget.shoot.date),
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: c.textSecondary,
                                ),
                              ),
                              const Spacer(),
                              _StatusBadge(
                                label: widget.shoot.reel.displayPaymentType,
                                color: statusColor,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedRotation(
                      turns: _hovered ? 0.02 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Icon(Icons.chevron_right_rounded,
                          size: 16,
                          color: _hovered
                              ? primary.withOpacity(0.7)
                              : c.textSecondary.withOpacity(0.35)),
                    ),
                  ],
                ),
              ),
            ),
          ), // AnimatedContainer wrapper
        ), // Material
      ), // ScaleTransition
    ); // MouseRegion
  }
}

// ─── Tile stat label ──────────────────────────────────────────────────────────

class _StatLabel extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;

  const _StatLabel({
    required this.label,
    required this.color,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.poppins(
        fontSize: 8,
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.3,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ─── Tile progress bar with client dots ──────────────────────────────────────

class _TileProgressBar extends StatelessWidget {
  final double progress; // 0.0 – 1.0 paid fraction
  final bool hasEvents;
  final Color barBg;
  final Color barFill;
  final Color dotColor;
  final int dotCount; // number of client dots (capped at 4)

  const _TileProgressBar({
    required this.progress,
    required this.hasEvents,
    required this.barBg,
    required this.barFill,
    required this.dotColor,
    required this.dotCount,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasEvents) {
      return Container(height: 2, color: barBg);
    }

    return Container(
      height: 12,
      color: barBg,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Stack(
        children: [
          // Track
          Container(
            decoration: BoxDecoration(
              color: barBg,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          // Fill
          FractionallySizedBox(
            widthFactor: progress == 0 ? 0.0 : progress.clamp(0.08, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: barFill,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          // Blue client dots — right-aligned
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < dotCount.clamp(0, 4); i++) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: barBg, width: 0.8),
                    ),
                  ),
                  if (i < dotCount.clamp(0, 4) - 1) const SizedBox(width: 1.5),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable small widgets ───────────────────────────────────────────────────

/// Single pill button — handles both text-only and icon-only variants
class _PillButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  const _PillButton({this.label, this.icon, required this.onTap})
      : assert(label != null || icon != null);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: label != null
            ? const EdgeInsets.symmetric(horizontal: 14, vertical: 7)
            : const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: BillifyColors.outlineVariant.withOpacity(0.45),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: label != null
            ? Text(
          label!,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: BillifyColors.textPrimary,
          ),
        )
            : Icon(icon, size: 17, color: BillifyColors.textPrimary),
      ),
    );
  }
}

class _SegmentedToggle extends StatelessWidget {
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelect;

  const _SegmentedToggle({
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final primary = ThemeController.to.primary;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: BillifyColors.surfaceLow,
        border: Border.all(
          color: BillifyColors.outlineVariant.withOpacity(0.4),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final active = opt == selected;
          return GestureDetector(
            onTap: () => onSelect(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? primary : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                boxShadow: active
                    ? [
                  BoxShadow(
                    color: primary.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  )
                ]
                    : null,
              ),
              child: Text(
                opt,
                style: GoogleFonts.poppins(
                  fontSize: 11,
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

class _Chip extends StatelessWidget {
  final String label;
  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: BillifyColors.surfaceLow,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: BillifyColors.outlineVariant.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: BillifyColors.textSecondary,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isFullList;
  const _EmptyState({this.isFullList = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFullList
                  ? Icons.video_camera_front_outlined
                  : Icons.event_available_outlined,
              size: 36,
              color: BillifyColors.textSecondary.withOpacity(0.25),
            ),
            const SizedBox(height: 10),
            Text(
              isFullList ? 'No shoots scheduled' : 'Nothing on this day',
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: BillifyColors.textSecondary.withOpacity(0.7),
              ),
            ),
            if (isFullList) ...[
              const SizedBox(height: 4),
              Text(
                'Shoot dates will appear here once added',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  color: BillifyColors.textSecondary.withOpacity(0.45),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  const _ErrorState(this.message);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 32, color: BillifyColors.unpaid.withOpacity(0.5)),
          const SizedBox(height: 10),
          Text(
            message,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: BillifyColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}