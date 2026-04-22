// ════════════════════════════════════════════════════════════
//  web_layout.dart — Billify
//
//  Key design decisions:
//  1. WebLayoutService  — GetxService singleton, loaded once at startup.
//     Holds 'mobile'|'desktop' choice. Never re-prompts once chosen.
//
//  2. WebLayoutGate     — Wraps GetMaterialApp's builder. Shows the
//     device-picker dialog exactly once (first web session). On every
//     subsequent launch it reads the saved pref and passes straight through.
//     Lives ABOVE the navigator so it is never destroyed on route changes.
//
//  3. WebScaffold       — StateLESS drop-in Scaffold replacement.
//     • Android/iOS/Mobile-web → full Scaffold with slide-out drawer.
//     • Desktop-web            → just body+appBar in a Column. The outer
//       Scaffold + permanent rail are provided by DesktopShell (see below).
//     No initState, no _checkedMode → zero rebuild-on-navigation.
//
//  4. DesktopShell      — A single persistent widget that wraps only the
//     main-app routes on desktop web. It renders the permanent 260 px rail
//     on the left and a content area on the right. Because it lives in
//     GetMaterialApp's builder (same level as WebLayoutGate), it is never
//     destroyed when routes change inside the app.
//
//  5. DesktopNavCallback — InheritedWidget injected by DesktopShell around
//     BillifyDrawer. _NavItem and profile-tap handlers detect it and call
//     desktopNavigateTo() instead of Navigator.pop() + Get.offAllNamed().
// ════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'main.dart' show BillifyColors, AppRoutes, BillifyDrawer;


// Routes that should NOT show the desktop shell (auth / onboarding screens)
const _kShelllessRoutes = {
  AppRoutes.splash,
  AppRoutes.login,
  AppRoutes.register,
  AppRoutes.forgotPassword,
  AppRoutes.termsConditions,
  AppRoutes.lock,
};

// ─────────────────────────────────────────────────────────────────────────────
//  CONSTANTS
// ─────────────────────────────────────────────────────────────────────────────

const String _kPrefKey   = 'web_layout_mode';
const double _kRailWidth = 260.0;

// ─────────────────────────────────────────────────────────────────────────────
//  SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class WebLayoutService extends GetxService {
  final RxString _mode        = ''.obs;
  // Start on splash so WebLayoutGate never shows the shell before login.
  final RxString activeRoute  = AppRoutes.splash.obs;

  String get mode      => _mode.value;
  bool get isDesktop   => kIsWeb && _mode.value == 'desktop';
  bool get isMobileWeb => kIsWeb && _mode.value == 'mobile';
  bool get hasChosen   => _mode.value.isNotEmpty;

  Future<WebLayoutService> init() async {
    if (!kIsWeb) { _mode.value = 'mobile'; return this; }
    final prefs = await SharedPreferences.getInstance();
    _mode.value = prefs.getString(_kPrefKey) ?? '';
    return this;
  }

  Future<void> setMode(String m) async {
    _mode.value = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, m);
  }

  Future<void> resetChoice() async {
    _mode.value = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefKey);
  }

  /// Call after every navigation so the rail highlight and gate
  /// react to the current screen correctly.
  void syncRoute(String route) {
    if (route.startsWith('/invoice'))   { activeRoute.value = AppRoutes.invoices;   return; }
    if (route.startsWith('/expense'))   { activeRoute.value = AppRoutes.expenses;   return; }
    if (route.startsWith('/client'))    { activeRoute.value = AppRoutes.clients;    return; }
    if (route.startsWith('/analytics')) { activeRoute.value = AppRoutes.analytics;  return; }
    if (route.startsWith('/settlement')){ activeRoute.value = AppRoutes.settlement; return; }
    activeRoute.value = route;
  }

  static WebLayoutService get to => Get.find<WebLayoutService>();
}

// ─────────────────────────────────────────────────────────────────────────────
//  DesktopNavCallback — InheritedWidget so any widget in the tree can detect
//  "I am inside the permanent desktop rail" and navigate correctly.
// ─────────────────────────────────────────────────────────────────────────────

class DesktopNavCallback extends InheritedWidget {
  /// Called when a nav item should navigate to [route].
  final void Function(String route) navigate;

  const DesktopNavCallback({
    super.key,
    required this.navigate,
    required super.child,
  });

  /// Returns the callback if we are inside DesktopShell, null otherwise.
  static DesktopNavCallback? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopNavCallback>();

  @override
  bool updateShouldNotify(DesktopNavCallback old) => navigate != old.navigate;
}

// ─────────────────────────────────────────────────────────────────────────────
//  WebLayoutGate — injected via GetMaterialApp.builder, above the navigator.
//
//  ROOT CAUSE OF ALL CRASHES (both TypeErrorImpl and _elements.contains):
//  ───────────────────────────────────────────────────────────────────────
//  GetMaterialApp's builder: callback is called DURING the Navigator's very
//  first mount / restoreState pass.  At that exact moment, GetX's
//  initialRoutesGenerate tries to resolve every route's .page getter.
//  If the builder returns anything other than a bare passthrough on that
//  first synchronous call (e.g. a Scaffold, a Row, an Obx, or ANY widget
//  that rebuilds asynchronously), the Navigator element gets deactivated
//  and re-inflated in a different tree position, which corrupts
//  BuildOwner's element set → crash.
//
//  THE ONLY SAFE PATTERN:
//  ──────────────────────
//  1. On the very first build, return `child` with ZERO wrapping.
//  2. After the first frame is fully committed (addPostFrameCallback),
//     flip a flag and rebuild — now it is safe to add the shell around
//     the already-mounted Navigator.
//  3. The shell (Scaffold + Row) must be a StatefulWidget so it owns
//     a stable element slot; the Navigator (child) must always occupy
//     the SAME slot inside that Row — it must NEVER be moved, removed,
//     or re-parented by any reactive rebuild.
// ─────────────────────────────────────────────────────────────────────────────

class WebLayoutGate extends StatefulWidget {
  final Widget child;
  const WebLayoutGate({super.key, required this.child});

  @override
  State<WebLayoutGate> createState() => _WebLayoutGateState();
}

class _WebLayoutGateState extends State<WebLayoutGate> {
  // False on the very first synchronous build so we return child bare.
  // Flipped to true after the first frame — safe to add the shell.
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // Wait until the Navigator has fully mounted before wrapping it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // First synchronous build: return child with ZERO wrapping.
    // GetX resolves all route .page getters during this call —
    // any extra widget here corrupts the element tree.
    if (!_ready || !kIsWeb) return widget.child;

    // After first frame: safe to wrap with the persistent shell.
    // DesktopShell keeps widget.child at a FIXED tree position forever.
    return DesktopShell(child: widget.child);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  DesktopShell — rendered ONCE, after the Navigator is fully mounted.
//
//  Layout:  [ optional rail | optional divider | Expanded(child) ]
//
//  INVARIANT: widget.child (the Navigator) is ALWAYS the last child of the
//  Row, at a fixed index.  It is NEVER inside any Obx, GetBuilder, or
//  conditional that could move/remove/re-parent it.  Only the rail and
//  divider slots are reactive.
// ─────────────────────────────────────────────────────────────────────────────

class DesktopShell extends StatelessWidget {
  final Widget child;
  const DesktopShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Row(
        children: [
          // ── Rail slot — reactive, but child is NEVER inside this Obx ────
          Obx(() {
            final svc      = WebLayoutService.to;
            final showRail = svc.isDesktop &&
                !_kShelllessRoutes.contains(svc.activeRoute.value);

            if (!showRail) return const SizedBox.shrink();

            return SizedBox(
              width: _kRailWidth,
              child: Material(
                color: BillifyColors.surface,
                elevation: 0,
                child: Column(
                  children: [
                    SizedBox(height: MediaQuery.of(context).padding.top),
                    Expanded(
                      child: DesktopNavCallback(
                        navigate: _handleNav,
                        child: BillifyDrawer(
                          activeRoute: svc.activeRoute.value,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          // ── Divider slot — reactive ───────────────────────────────────
          Obx(() {
            final svc      = WebLayoutService.to;
            final showRail = svc.isDesktop &&
                !_kShelllessRoutes.contains(svc.activeRoute.value);
            if (!showRail) return const SizedBox.shrink();
            return Container(
              width: 1,
              color: BillifyColors.outlineVariant.withOpacity(0.3),
            );
          }),

          // ── Content pane ─────────────────────────────────────────────
          // child is ALWAYS here at a FIXED index.
          // No Obx, no conditional, no reactive widget wraps this slot.
          Expanded(child: child),
        ],
      ),
    );
  }

  void _handleNav(String route) {
    WebLayoutService.to.syncRoute(route);
    Get.offAllNamed(route);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  WebScaffold — stateless drop-in Scaffold replacement for every screen.
//
//  Desktop-web:  just a Column(AppBar, body). The outer DesktopShell Scaffold
//                is the real Scaffold. No nested Scaffold, no state, no rebuild.
//
//  Mobile/Android/iOS:  full Scaffold with slide-out BillifyDrawer.
// ─────────────────────────────────────────────────────────────────────────────

class WebScaffold extends StatelessWidget {
  final String activeRoute;
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? floatingActionButton;
  final Color? backgroundColor;

  const WebScaffold({
    super.key,
    required this.activeRoute,
    this.appBar,
    required this.body,
    this.floatingActionButton,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && WebLayoutService.to.isDesktop) {
      return _buildDesktopContent(context);
    }
    return _buildMobileScaffold(context);
  }

  // ── Desktop: no Scaffold, no drawer — just the content ───────────────────

  Widget _buildDesktopContent(BuildContext context) {
    final bg = backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;
    final content = Column(
      children: [
        if (appBar != null) _DesktopAppBar(appBar: appBar!),
        Expanded(child: body),
      ],
    );

    if (floatingActionButton == null) {
      return ColoredBox(color: bg, child: content);
    }
    return ColoredBox(
      color: bg,
      child: Stack(
        children: [
          content,
          Positioned(
            right: 16,
            bottom: 24,
            child: floatingActionButton!,
          ),
        ],
      ),
    );
  }

  // ── Mobile / Android / iOS: full normal Scaffold ─────────────────────────

  Widget _buildMobileScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
      drawer: BillifyDrawer(activeRoute: activeRoute),
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      body: body,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Desktop AppBar wrapper — removes top safe-area issue
// ─────────────────────────────────────────────────────────────────────────────

class _DesktopAppBar extends StatelessWidget {
  final PreferredSizeWidget appBar;
  const _DesktopAppBar({required this.appBar});

  @override
  Widget build(BuildContext context) {
    // On desktop the rail replaces the drawer/hamburger. Suppress the
    // auto-inserted back button that Flutter adds when the GetX stack
    // has more than one route (e.g. Dashboard → Invoices).
    return SizedBox(
      height: appBar.preferredSize.height,
      child: Theme(
        data: Theme.of(context).copyWith(
          appBarTheme: Theme.of(context).appBarTheme.copyWith(
            // Prevent Flutter from auto-inserting a back arrow.
            // Screens that genuinely need a back button supply an
            // explicit leading: widget — those are unaffected.
          ),
        ),
        child: MediaQuery(
          // Override the padding so the AppBar doesn't add extra top space.
          data: MediaQuery.of(context).copyWith(padding: EdgeInsets.zero),
          child: Builder(
            builder: (ctx) {
              // If the appBar is a standard AppBar and has no explicit
              // leading set, force automaticallyImplyLeading off.
              if (appBar is AppBar) {
                final bar = appBar as AppBar;
                if (bar.leading == null) {
                  return AppBar(
                    key: bar.key,
                    automaticallyImplyLeading: false,
                    backgroundColor: bar.backgroundColor,
                    elevation: bar.elevation ?? 0,
                    title: bar.title,
                    actions: bar.actions,
                    bottom: bar.bottom,
                    titleSpacing: bar.titleSpacing,
                    toolbarHeight: bar.toolbarHeight,
                    foregroundColor: bar.foregroundColor,
                    shadowColor: bar.shadowColor,
                    surfaceTintColor: bar.surfaceTintColor,
                    centerTitle: bar.centerTitle,
                    titleTextStyle: bar.titleTextStyle,
                    toolbarTextStyle: bar.toolbarTextStyle,
                    iconTheme: bar.iconTheme,
                    actionsIconTheme: bar.actionsIconTheme,
                    shape: bar.shape,
                    systemOverlayStyle: bar.systemOverlayStyle,
                    scrolledUnderElevation: bar.scrolledUnderElevation,
                    flexibleSpace: bar.flexibleSpace,
                  );
                }
              }
              return appBar;
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Device picker dialog (shown once)
// ─────────────────────────────────────────────────────────────────────────────

Future<String> showWebDevicePickerDialog(BuildContext context) async {
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _DevicePickerDialog(),
  );
  return result ?? 'mobile';
}

class _DevicePickerDialog extends StatefulWidget {
  const _DevicePickerDialog();
  @override
  State<_DevicePickerDialog> createState() => _DevicePickerDialogState();
}

class _DevicePickerDialogState extends State<_DevicePickerDialog> {
  String _selected = '';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      backgroundColor: BillifyColors.surface,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(width: 3, height: 22, color: BillifyColors.primary),
                const SizedBox(width: 10),
                Text('CHOOSE YOUR DEVICE',
                    style: GoogleFonts.poppins(
                        fontSize: 11, fontWeight: FontWeight.w900,
                        letterSpacing: 2.0, color: BillifyColors.primary)),
              ]),
              const SizedBox(height: 8),
              Text(
                'How are you accessing Billify right now? '
                    'This sets the best layout for your screen. '
                    'You can change it later in Settings.',
                style: GoogleFonts.nunito(
                    fontSize: 13, color: BillifyColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 24),
              _OptionCard(
                icon: Icons.smartphone_rounded, label: 'MOBILE',
                sublabel: 'Normal layout · slide-out drawer',
                selected: _selected == 'mobile',
                onTap: () => setState(() => _selected = 'mobile'),
              ),
              const SizedBox(height: 10),
              _OptionCard(
                icon: Icons.desktop_windows_rounded, label: 'DESKTOP',
                sublabel: 'Wide layout · permanent side drawer',
                selected: _selected == 'desktop',
                onTap: () => setState(() => _selected = 'desktop'),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_selected),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BillifyColors.primary,
                    foregroundColor: const Color(0xFFF7F7FF),
                    disabledBackgroundColor:
                    BillifyColors.outlineVariant.withOpacity(0.3),
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero),
                    elevation: 0,
                  ),
                  child: Text(_selected.isEmpty ? 'SELECT AN OPTION' : 'CONFIRM',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w800,
                          fontSize: 11, letterSpacing: 1.5)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String label, sublabel;
  final bool selected;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon, required this.label, required this.sublabel,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? BillifyColors.primary.withOpacity(0.07)
              : BillifyColors.surfaceLow,
          border: Border.all(
            color: selected
                ? BillifyColors.primary
                : BillifyColors.outlineVariant.withOpacity(0.4),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            color: selected
                ? BillifyColors.primary
                : BillifyColors.outlineVariant.withOpacity(0.15),
            child: Icon(icon,
                color: selected ? const Color(0xFFF7F7FF) : BillifyColors.textSecondary,
                size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2,
                      color: selected ? BillifyColors.primary : BillifyColors.textPrimary)),
              Text(sublabel,
                  style: GoogleFonts.nunito(
                      fontSize: 12, color: BillifyColors.textSecondary)),
            ]),
          ),
          if (selected)
            const Icon(Icons.check_circle_rounded,
                color: BillifyColors.primary, size: 20),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Public helper — re-show picker from Settings
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showChangeLayoutDialog(BuildContext context) async {
  final svc = WebLayoutService.to;
  await svc.resetChoice();
  if (!context.mounted) return;
  final choice = await showWebDevicePickerDialog(context);
  await svc.setMode(choice);
}