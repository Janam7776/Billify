// ════════════════════════════════════════════════════════════
//  THEME CONTROLLER  —  Light-only, full color customization
//  Save this as:  lib/theme_controller.dart
// ════════════════════════════════════════════════════════════

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Pref keys ─────────────────────────────────────────────────
class ThemePrefKeys {
  static const primaryColor           = 'theme_primaryColor';
  static const primaryOpacity         = 'theme_primaryOpacity';
  static const gradientEnabled        = 'theme_gradientEnabled';
  static const gradientColor2         = 'theme_gradientColor2';
  static const gradientColor2Opacity  = 'theme_gradientColor2Opacity';
  static const gradientAngle          = 'theme_gradientAngle';
}

// ════════════════════════════════════════════════════════════
//  THEME CONTROLLER
// ════════════════════════════════════════════════════════════
class ThemeController extends GetxController {
  static ThemeController get to => Get.find();

  // ── Reactive state ────────────────────────────────────────
  final primaryColorValue       = const Color(0xFF3C5D9C).obs;
  final primaryOpacity          = 1.0.obs;
  final gradientEnabled         = false.obs;
  final gradientColor2Value     = const Color(0xFF5A7BB8).obs;
  final gradientColor2Opacity   = 1.0.obs;
  final gradientAngle           = 135.0.obs;

  // ── Debounce timer for save (avoids hammering SharedPrefs on slider drag) ─
  Timer? _saveDebounce;
  // ── Debounce timer for theme rebuild (avoids rebuilding every frame) ──────
  Timer? _applyDebounce;

  // ── Derived getters ───────────────────────────────────────
  Color get primary =>
      primaryColorValue.value.withOpacity(primaryOpacity.value);

  Color get primaryLight =>
      _lighten(primaryColorValue.value, 0.15).withOpacity(primaryOpacity.value);

  Color get primaryDark =>
      _darken(primaryColorValue.value, 0.10).withOpacity(primaryOpacity.value);

  Color get grad2 =>
      gradientColor2Value.value.withOpacity(gradientColor2Opacity.value);

  LinearGradient get headerGradient {
    if (!gradientEnabled.value) {
      return LinearGradient(
        colors: [primary, primaryLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    final rad = gradientAngle.value * 3.14159265358979 / 180.0;
    return LinearGradient(
      colors: [primary, grad2],
      // Use dart:math-free approximation — accurate enough for gradients
      begin: Alignment(-_cos(rad), -_sin(rad)),
      end:   Alignment( _cos(rad),  _sin(rad)),
    );
  }

  Color get splashBg => primary;

  // Always light — dark/system removed per requirement
  ThemeMode get themeMode => ThemeMode.light;

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    _load();
  }

  @override
  void onClose() {
    _saveDebounce?.cancel();
    _applyDebounce?.cancel();
    super.onClose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();

    final pc = p.getInt(ThemePrefKeys.primaryColor);
    if (pc != null) primaryColorValue.value = Color(pc);
    primaryOpacity.value =
        p.getDouble(ThemePrefKeys.primaryOpacity) ?? 1.0;

    gradientEnabled.value =
        p.getBool(ThemePrefKeys.gradientEnabled) ?? false;

    final gc2 = p.getInt(ThemePrefKeys.gradientColor2);
    if (gc2 != null) gradientColor2Value.value = Color(gc2);
    gradientColor2Opacity.value =
        p.getDouble(ThemePrefKeys.gradientColor2Opacity) ?? 1.0;

    gradientAngle.value =
        p.getDouble(ThemePrefKeys.gradientAngle) ?? 135.0;

    _applyTheme();
  }

  // ── Setters — update reactive state immediately,
  //    debounce the expensive operations ─────────────────────

  void setPrimaryColor(Color c) {
    primaryColorValue.value = c;
    _scheduleApply();
    _scheduleSave();
  }

  void setPrimaryOpacity(double v) {
    primaryOpacity.value = v.clamp(0.0, 1.0);
    _scheduleApply();
    _scheduleSave();
  }

  void setGradientEnabled(bool v) {
    gradientEnabled.value = v;
    _applyTheme();   // instant for toggle
    _scheduleSave();
  }

  void setGradientColor2(Color c) {
    gradientColor2Value.value = c;
    _scheduleApply();
    _scheduleSave();
  }

  void setGradientColor2Opacity(double v) {
    gradientColor2Opacity.value = v.clamp(0.0, 1.0);
    _scheduleApply();
    _scheduleSave();
  }

  void setGradientAngle(double v) {
    gradientAngle.value = v % 360;
    _scheduleApply();
    _scheduleSave();
  }

  Future<void> resetToDefault() async {
    primaryColorValue.value     = const Color(0xFF3C5D9C);
    primaryOpacity.value        = 1.0;
    gradientEnabled.value       = false;
    gradientColor2Value.value   = const Color(0xFF5A7BB8);
    gradientColor2Opacity.value = 1.0;
    gradientAngle.value         = 135.0;
    _applyTheme();
    await _save();
  }

  // Apply a full preset atomically
  Future<void> applyPreset(ThemePreset p) async {
    primaryColorValue.value     = p.primary;
    primaryOpacity.value        = 1.0;
    gradientEnabled.value       = p.gradient;
    gradientColor2Value.value   = p.gradientEnd;
    gradientColor2Opacity.value = 1.0;
    gradientAngle.value         = p.angle;
    _applyTheme();
    await _save();
  }

  // ── Debounce helpers ──────────────────────────────────────

  /// Debounce heavy Get.changeTheme calls — only fires 80ms after last change.
  /// This prevents jank when dragging a slider quickly.
  void _scheduleApply() {
    _applyDebounce?.cancel();
    _applyDebounce = Timer(const Duration(milliseconds: 80), _applyTheme);
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), _save);
  }

  // ── Persist ───────────────────────────────────────────────
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setInt(ThemePrefKeys.primaryColor,
          primaryColorValue.value.value),
      p.setDouble(ThemePrefKeys.primaryOpacity,  primaryOpacity.value),
      p.setBool(ThemePrefKeys.gradientEnabled,   gradientEnabled.value),
      p.setInt(ThemePrefKeys.gradientColor2,
          gradientColor2Value.value.value),
      p.setDouble(ThemePrefKeys.gradientColor2Opacity,
          gradientColor2Opacity.value),
      p.setDouble(ThemePrefKeys.gradientAngle, gradientAngle.value),
    ]);
  }

  // ── Apply to GetX ─────────────────────────────────────────
  // Only call buildLightTheme() once — never call changeTheme twice
  // or call changeThemeMode when it's always ThemeMode.light.
  void _applyTheme() {
    Get.changeTheme(buildLightTheme());
    // ThemeMode is always light — no need to call changeThemeMode repeatedly
  }

  // ── Theme builder ─────────────────────────────────────────
  ThemeData buildLightTheme() {
    final c           = primary;
    const onSurface   = Color(0xFF29343A);
    const surfaceLow  = Color(0xFFF0F4F8);
    const outlineVar  = Color(0xFFA8B3BB);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor:  c,
        brightness: Brightness.light,
        primary:    c,
        secondary:  const Color(0xFF536073),
        surface:    const Color(0xFFFFFFFF),
      ),
      scaffoldBackgroundColor: const Color(0xFFF7F9FC),
    );

    return base.copyWith(
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).copyWith(
        displayLarge:  GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.5, color: onSurface),
        displayMedium: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -1.0, color: onSurface),
        headlineLarge: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w800, color: onSurface),
        headlineMedium:GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w700, color: onSurface),
        bodyLarge:     GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w500, color: onSurface),
        bodyMedium:    GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w500, color: onSurface),
        bodySmall:     GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w400),
        labelLarge:    GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2, color: onSurface),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor:  const Color(0xFFF7F9FC),
        foregroundColor:  onSurface,
        elevation:        0,
        centerTitle:      false,
        titleTextStyle:   GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w800, color: c, letterSpacing: 1.0),
        iconTheme:        IconThemeData(color: c),
        surfaceTintColor: Colors.transparent,
        shadowColor:      Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color:     Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: outlineVar, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c,
          foregroundColor: const Color(0xFFF7F7FF),
          elevation:       0,
          minimumSize:     const Size(double.infinity, 52),
          shape:           const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle:       GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c,
          side:            BorderSide(color: c, width: 1.5),
          minimumSize:     const Size(double.infinity, 52),
          shape:           const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle:       GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled:        true,
        fillColor:     surfaceLow,
        border:        OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: outlineVar)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: outlineVar.withOpacity(0.6))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: c, width: 2)),
        errorBorder:   const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: Color(0xFF9F403D), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle:    GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0),
        hintStyle:     GoogleFonts.nunito(fontSize: 13, color: outlineVar),
        prefixIconColor: c,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c,
        foregroundColor: const Color(0xFFF7F7FF),
        elevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor:     Colors.white,
        selectedItemColor:   c,
        unselectedItemColor: const Color(0xFF566168),
        elevation: 0,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Color(0xFFCEDCE5),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      dividerTheme: DividerThemeData(color: outlineVar, thickness: 0.5),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceLow,
        selectedColor:   c,
        labelStyle:      GoogleFonts.poppins(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8),
        side:            BorderSide(color: outlineVar),
        shape:           const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:  const Color(0xFF29343A),
        contentTextStyle: GoogleFonts.nunito(color: Colors.white),
        behavior:         SnackBarBehavior.floating,
        shape:            const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        titleTextStyle:   GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w800, color: onSurface, letterSpacing: -0.3),
        contentTextStyle: GoogleFonts.nunito(fontSize: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? c : Colors.grey.shade400),
        trackColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? c.withOpacity(0.4) : Colors.grey.shade300),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? c : Colors.transparent),
        side:  BorderSide(color: c, width: 2),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c),
      tabBarTheme: TabBarThemeData(
        labelColor:           Colors.white,
        unselectedLabelColor: const Color(0xFFE1E9F0),
        indicatorColor:       c,
        labelStyle:           GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 1.0),
        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 11, letterSpacing: 0.8),
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        textColor: onSurface,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        textStyle: GoogleFonts.nunito(color: onSurface, fontSize: 14),
      ),
    );
  }

  // ── Color math helpers ─────────────────────────────────────
  static Color _lighten(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  static Color _darken(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0)).toColor();
  }

  // Use dart:math-free Taylor series — accurate enough for gradients
  static double _cos(double r) =>
      1 - r * r / 2 + r * r * r * r / 24 - r * r * r * r * r * r / 720;
  static double _sin(double r) =>
      r - r * r * r / 6 + r * r * r * r * r / 120 - r * r * r * r * r * r * r / 5040;
}

// ════════════════════════════════════════════════════════════
//  PRESET THEMES
// ════════════════════════════════════════════════════════════
class ThemePreset {
  final String name;
  final Color  primary;
  final Color  gradientEnd;
  final bool   gradient;
  final double angle;

  const ThemePreset({
    required this.name,
    required this.primary,
    required this.gradientEnd,
    this.gradient = false,
    this.angle = 135,
  });
}

const List<ThemePreset> kThemePresets = [
  ThemePreset(name: 'Billify',  primary: Color(0xFF3C5D9C), gradientEnd: Color(0xFF5A7BB8)),
  ThemePreset(name: 'Ocean',    primary: Color(0xFF006994), gradientEnd: Color(0xFF00B4D8), gradient: true, angle: 120),
  ThemePreset(name: 'Forest',   primary: Color(0xFF1B4332), gradientEnd: Color(0xFF52B788), gradient: true, angle: 135),
  ThemePreset(name: 'Sunset',   primary: Color(0xFFE63946), gradientEnd: Color(0xFFFF6B6B), gradient: true, angle: 45),
  ThemePreset(name: 'Royal',    primary: Color(0xFF6A0572), gradientEnd: Color(0xFFC77DFF), gradient: true, angle: 150),
  ThemePreset(name: 'Copper',   primary: Color(0xFFB5451B), gradientEnd: Color(0xFFE07B54), gradient: true, angle: 135),
  ThemePreset(name: 'Slate',    primary: Color(0xFF37474F), gradientEnd: Color(0xFF607D8B)),
  ThemePreset(name: 'Teal',     primary: Color(0xFF00695C), gradientEnd: Color(0xFF4DB6AC), gradient: true, angle: 120),
  ThemePreset(name: 'Gold',     primary: Color(0xFFC7971A), gradientEnd: Color(0xFFFFD166), gradient: true, angle: 135),
  ThemePreset(name: 'Crimson',  primary: Color(0xFF8B0000), gradientEnd: Color(0xFFDC143C), gradient: true, angle: 160),
  ThemePreset(name: 'Navy',     primary: Color(0xFF001F5B), gradientEnd: Color(0xFF003087)),
  ThemePreset(name: 'Midnight', primary: Color(0xFF1A1A2E), gradientEnd: Color(0xFF16213E), gradient: true, angle: 160),
];

// ════════════════════════════════════════════════════════════
//  THEME CUSTOMIZATION SCREEN
// ════════════════════════════════════════════════════════════
class ThemeCustomizationScreen extends StatefulWidget {
  const ThemeCustomizationScreen({super.key});

  @override
  State<ThemeCustomizationScreen> createState() =>
      _ThemeCustomizationScreenState();
}

class _ThemeCustomizationScreenState
    extends State<ThemeCustomizationScreen>
    with SingleTickerProviderStateMixin {
  late ThemeController _tc;
  late TabController   _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tc = ThemeController.to;
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final tc       = _tc;
      final primary  = tc.primary;
      final gradient = tc.gradientEnabled.value
          ? tc.headerGradient
          : LinearGradient(
        colors: [primary, tc.primaryLight],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('THEME STUDIO'),
          actions: [
            TextButton(
              onPressed: () async {
                await tc.resetToDefault();
                if (!context.mounted) return;
                Get.snackbar(
                  'Reset',
                  'Theme restored to Billify default.',
                  backgroundColor: tc.primary,
                  colorText: Colors.white,
                  snackPosition: SnackPosition.TOP,
                  duration: const Duration(seconds: 2),
                );
              },
              child: Text(
                'RESET',
                style: GoogleFonts.poppins(
                  fontSize: 9, fontWeight: FontWeight.w800,
                  letterSpacing: 1.2, color: primary,
                ),
              ),
            ),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: primary,
            labelColor: primary,
            unselectedLabelColor:
            Theme.of(context).colorScheme.onSurfaceVariant,
            tabs: const [
              Tab(text: 'PRESETS'),
              Tab(text: 'COLORS'),
              Tab(text: 'GRADIENT'),
            ],
          ),
        ),
        body: Column(
          children: [
            // ── Live Preview ──────────────────────────────
            _LivePreview(
              gradient:        gradient,
              primary:         primary,
              gradientEnabled: tc.gradientEnabled.value,
              grad2:           tc.grad2,
            ),

            // ── Tabs ──────────────────────────────────────
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _PresetsTab(
                    onSelect: (p) => tc.applyPreset(p),
                    currentPrimary: tc.primaryColorValue.value,
                  ),
                  _ColorsTab(
                    primary:          tc.primaryColorValue.value,
                    primaryOpacity:   tc.primaryOpacity.value,
                    onPrimaryChanged: tc.setPrimaryColor,
                    onOpacityChanged: tc.setPrimaryOpacity,
                  ),
                  _GradientTab(
                    enabled:   tc.gradientEnabled.value,
                    color2:    tc.gradientColor2Value.value,
                    opacity2:  tc.gradientColor2Opacity.value,
                    angle:     tc.gradientAngle.value,
                    onEnabled:  tc.setGradientEnabled,
                    onColor2:   tc.setGradientColor2,
                    onOpacity2: tc.setGradientColor2Opacity,
                    onAngle:    tc.setGradientAngle,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

// ════════════════════════════════════════════════════════════
//  LIVE PREVIEW WIDGET  — dark/system toggle removed
// ════════════════════════════════════════════════════════════
class _LivePreview extends StatelessWidget {
  final LinearGradient gradient;
  final Color          primary;
  final bool           gradientEnabled;
  final Color          grad2;

  const _LivePreview({
    required this.gradient,
    required this.primary,
    required this.gradientEnabled,
    required this.grad2,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: primary.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header preview
          Container(
            height: 80,
            decoration: BoxDecoration(gradient: gradient),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 40, height: 40,
                    color: Colors.white.withOpacity(0.2),
                    child: const Icon(
                      Icons.receipt_long_rounded,
                      color: Colors.white, size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BILLIFY',
                          style: GoogleFonts.poppins(
                              fontSize: 14, fontWeight: FontWeight.w900,
                              color: Colors.white, letterSpacing: 3)),
                      Text('Live Preview',
                          style: GoogleFonts.nunito(
                              fontSize: 10, color: Colors.white70)),
                    ],
                  ),
                  const Spacer(),
                  // Light-mode indicator (static — no toggle)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    color: Colors.white.withOpacity(0.2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.light_mode_rounded,
                            color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text('LIGHT',
                            style: GoogleFonts.poppins(
                                fontSize: 8, fontWeight: FontWeight.w800,
                                letterSpacing: 1.0, color: Colors.white)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Body preview
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFFF7F9FC),
            child: Row(
              children: [
                // Mini card
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          color: primary.withOpacity(0.15),
                          child: Text('INVOICE',
                              style: GoogleFonts.poppins(
                                  fontSize: 7, fontWeight: FontWeight.w800,
                                  color: primary, letterSpacing: 1.0)),
                        ),
                        const SizedBox(height: 6),
                        Text('₹ 24,000',
                            style: GoogleFonts.poppins(
                                fontSize: 13, fontWeight: FontWeight.w800,
                                color: primary)),
                        Text('Client Co.',
                            style: GoogleFonts.nunito(
                                fontSize: 10,
                                color: const Color(0xFF566168))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Mini button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(gradient: gradient),
                  child: Text('+ NEW',
                      style: GoogleFonts.poppins(
                          fontSize: 9, fontWeight: FontWeight.w800,
                          color: Colors.white, letterSpacing: 1.0)),
                ),
                const SizedBox(width: 8),
                // Gradient swatch
                if (gradientEnabled)
                  Column(children: [
                    Container(width: 20, height: 20,
                        color: primary.withOpacity(0.9)),
                    const SizedBox(height: 2),
                    Container(width: 20, height: 20,
                        color: grad2.withOpacity(0.9)),
                  ])
                else
                  Container(width: 20, height: 42, color: primary),
              ],
            ),
          ),

          // Label
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: primary.withOpacity(0.07),
            child: Center(
              child: Text(
                'LIVE PREVIEW  —  CHANGES APPLY INSTANTLY',
                style: GoogleFonts.poppins(
                    fontSize: 7, fontWeight: FontWeight.w700,
                    letterSpacing: 1.5, color: primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  PRESETS TAB
// ════════════════════════════════════════════════════════════
class _PresetsTab extends StatelessWidget {
  final ValueChanged<ThemePreset> onSelect;
  final Color currentPrimary;

  const _PresetsTab({required this.onSelect, required this.currentPrimary});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:   3,
        crossAxisSpacing: 10,
        mainAxisSpacing:  10,
        childAspectRatio: 1.1,
      ),
      itemCount: kThemePresets.length,
      itemBuilder: (ctx, i) {
        final p   = kThemePresets[i];
        final sel = p.primary.value == currentPrimary.value;
        return GestureDetector(
          onTap: () => onSelect(p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              gradient: p.gradient
                  ? LinearGradient(
                colors: [p.primary, p.gradientEnd],
                begin: Alignment.topLeft,
                end:   Alignment.bottomRight,
              )
                  : null,
              color: !p.gradient ? p.primary : null,
              border: Border.all(
                color: sel ? Colors.white : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: sel
                  ? [BoxShadow(color: p.primary.withOpacity(0.5),
                  blurRadius: 10, offset: const Offset(0, 3))]
                  : [],
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sel)
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.white, size: 22),
                      const SizedBox(height: 4),
                      Text(p.name.toUpperCase(),
                          style: GoogleFonts.poppins(
                              fontSize: 9, fontWeight: FontWeight.w800,
                              color: Colors.white, letterSpacing: 0.8)),
                    ],
                  ),
                ),
                if (p.gradient)
                  Positioned(
                    top: 6, right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      color: Colors.white.withOpacity(0.25),
                      child: Text('GR',
                          style: GoogleFonts.poppins(
                              fontSize: 6, fontWeight: FontWeight.w800,
                              color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════
//  COLORS TAB  —  HSV color ring + opacity + hex input
// ════════════════════════════════════════════════════════════
class _ColorsTab extends StatefulWidget {
  final Color   primary;
  final double  primaryOpacity;
  final ValueChanged<Color>  onPrimaryChanged;
  final ValueChanged<double> onOpacityChanged;

  const _ColorsTab({
    required this.primary,
    required this.primaryOpacity,
    required this.onPrimaryChanged,
    required this.onOpacityChanged,
  });

  @override
  State<_ColorsTab> createState() => _ColorsTabState();
}

class _ColorsTabState extends State<_ColorsTab> {
  late HSVColor _hsv;
  late TextEditingController _hexCtrl;
  bool _hexFocused = false;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.primary);
    _hexCtrl = TextEditingController(text: _colorToHex(widget.primary));
  }

  @override
  void didUpdateWidget(_ColorsTab old) {
    super.didUpdateWidget(old);
    // Only sync from outside if not actively editing hex
    if (old.primary != widget.primary && !_hexFocused) {
      final newHsv = HSVColor.fromColor(widget.primary);
      // Avoid unnecessary setState if value hasn't meaningfully changed
      if ((newHsv.hue - _hsv.hue).abs() > 0.5 ||
          (newHsv.saturation - _hsv.saturation).abs() > 0.01 ||
          (newHsv.value - _hsv.value).abs() > 0.01) {
        setState(() {
          _hsv = newHsv;
          _hexCtrl.text = _colorToHex(widget.primary);
        });
      }
    }
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  String _colorToHex(Color c) =>
      '${c.red.toRadixString(16).padLeft(2, '0')}'
          '${c.green.toRadixString(16).padLeft(2, '0')}'
          '${c.blue.toRadixString(16).padLeft(2, '0')}'.toUpperCase();

  Color? _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    if (clean.length != 6) return null;
    final v = int.tryParse('FF$clean', radix: 16);
    return v != null ? Color(v) : null;
  }

  // Local state changes — notify controller (debounce is inside controller)
  void _onHueChanged(double h) {
    setState(() => _hsv = _hsv.withHue(h));
    final c = _hsv.toColor();
    if (!_hexFocused) _hexCtrl.text = _colorToHex(c);
    widget.onPrimaryChanged(c);
  }

  void _onSatChanged(double s) {
    setState(() => _hsv = _hsv.withSaturation(s));
    final c = _hsv.toColor();
    if (!_hexFocused) _hexCtrl.text = _colorToHex(c);
    widget.onPrimaryChanged(c);
  }

  void _onValChanged(double v) {
    setState(() => _hsv = _hsv.withValue(v));
    final c = _hsv.toColor();
    if (!_hexFocused) _hexCtrl.text = _colorToHex(c);
    widget.onPrimaryChanged(c);
  }

  void _onSvChanged(double s, double v) {
    setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
    final c = _hsv.toColor();
    if (!_hexFocused) _hexCtrl.text = _colorToHex(c);
    widget.onPrimaryChanged(c);
  }

  void _onHexCommit(String val) {
    final c = _hexToColor(val);
    if (c != null) {
      setState(() => _hsv = HSVColor.fromColor(c));
      widget.onPrimaryChanged(c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _hsv.toColor().withOpacity(widget.primaryOpacity);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Color Ring ────────────────────────────────────
          _SectionLabel(label: 'COLOR WHEEL'),
          const SizedBox(height: 8),
          Center(
            child: SizedBox(
              width: 240, height: 240,
              child: _HsvColorRing(
                hsv:          _hsv,
                onHueChanged: _onHueChanged,
                onSvChanged:  _onSvChanged,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // ── Hex Input ─────────────────────────────────────
          _SectionLabel(label: 'HEX CODE'),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 40, height: 40,
                color: currentColor,
                margin: const EdgeInsets.only(right: 10),
              ),
              Expanded(
                child: Focus(
                  onFocusChange: (f) => setState(() => _hexFocused = f),
                  child: TextField(
                    controller: _hexCtrl,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'HEX',
                      prefixText: '#',
                      counterText: '',
                    ),
                    maxLength: 6,
                    onSubmitted: _onHexCommit,
                    onChanged: (v) {
                      if (v.replaceAll('#', '').length == 6) {
                        _onHexCommit(v);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── Hue Slider ────────────────────────────────────
          _SectionLabel(label: 'HUE'),
          const SizedBox(height: 6),
          _GradientSlider(
            value: _hsv.hue / 360,
            gradient: const LinearGradient(colors: [
              Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
              Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ]),
            thumbColor: HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor(),
            onChanged: (v) => _onHueChanged(v * 360),
          ),

          const SizedBox(height: 16),

          // ── Saturation Slider ─────────────────────────────
          _SectionLabel(label: 'SATURATION'),
          const SizedBox(height: 6),
          _GradientSlider(
            value: _hsv.saturation,
            gradient: LinearGradient(colors: [
              HSVColor.fromAHSV(1, _hsv.hue, 0, _hsv.value).toColor(),
              HSVColor.fromAHSV(1, _hsv.hue, 1, _hsv.value).toColor(),
            ]),
            thumbColor: _hsv.toColor(),
            onChanged: _onSatChanged,
          ),

          const SizedBox(height: 16),

          // ── Brightness Slider ─────────────────────────────
          _SectionLabel(label: 'BRIGHTNESS'),
          const SizedBox(height: 6),
          _GradientSlider(
            value: _hsv.value,
            gradient: LinearGradient(colors: [
              Colors.black,
              HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor(),
            ]),
            thumbColor: _hsv.toColor(),
            onChanged: _onValChanged,
          ),

          const SizedBox(height: 16),

          // ── Opacity Slider ────────────────────────────────
          _SectionLabel(
              label: 'OPACITY  ${(widget.primaryOpacity * 100).round()}%'),
          const SizedBox(height: 6),
          _GradientSlider(
            value: widget.primaryOpacity,
            gradient: LinearGradient(colors: [
              _hsv.toColor().withOpacity(0),
              _hsv.toColor(),
            ]),
            thumbColor: _hsv.toColor().withOpacity(widget.primaryOpacity),
            onChanged: widget.onOpacityChanged,
            checkerboard: true,
          ),

          const SizedBox(height: 20),

          // ── Quick Palettes ────────────────────────────────
          _SectionLabel(label: 'QUICK PALETTE'),
          const SizedBox(height: 10),
          _QuickPalette(
            onSelect: (c) {
              setState(() {
                _hsv = HSVColor.fromColor(c);
                _hexCtrl.text = _colorToHex(c);
              });
              widget.onPrimaryChanged(c);
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  GRADIENT TAB
// ════════════════════════════════════════════════════════════
class _GradientTab extends StatefulWidget {
  final bool    enabled;
  final Color   color2;
  final double  opacity2;
  final double  angle;
  final ValueChanged<bool>   onEnabled;
  final ValueChanged<Color>  onColor2;
  final ValueChanged<double> onOpacity2;
  final ValueChanged<double> onAngle;

  const _GradientTab({
    required this.enabled,
    required this.color2,
    required this.opacity2,
    required this.angle,
    required this.onEnabled,
    required this.onColor2,
    required this.onOpacity2,
    required this.onAngle,
  });

  @override
  State<_GradientTab> createState() => _GradientTabState();
}

class _GradientTabState extends State<_GradientTab> {
  late HSVColor _hsv2;
  late TextEditingController _hex2Ctrl;

  @override
  void initState() {
    super.initState();
    _hsv2    = HSVColor.fromColor(widget.color2);
    _hex2Ctrl = TextEditingController(text: _colorToHex(widget.color2));
  }

  @override
  void didUpdateWidget(_GradientTab old) {
    super.didUpdateWidget(old);
    if (old.color2 != widget.color2) {
      setState(() {
        _hsv2 = HSVColor.fromColor(widget.color2);
        _hex2Ctrl.text = _colorToHex(widget.color2);
      });
    }
  }

  @override
  void dispose() {
    _hex2Ctrl.dispose();
    super.dispose();
  }

  String _colorToHex(Color c) =>
      '${c.red.toRadixString(16).padLeft(2, '0')}'
          '${c.green.toRadixString(16).padLeft(2, '0')}'
          '${c.blue.toRadixString(16).padLeft(2, '0')}'.toUpperCase();

  Color? _hexToColor(String hex) {
    final clean = hex.replaceAll('#', '');
    if (clean.length != 6) return null;
    final v = int.tryParse('FF$clean', radix: 16);
    return v != null ? Color(v) : null;
  }

  @override
  Widget build(BuildContext context) {
    final tc = ThemeController.to;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Enable toggle ─────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border.all(color: tc.primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.gradient_rounded, color: tc.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Enable Gradient',
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Switch(
                  value:     widget.enabled,
                  onChanged: widget.onEnabled,
                  activeColor: tc.primary,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (widget.enabled) ...[
            // ── Preview bar ───────────────────────────────
            Obx(() => Container(
              height: 56,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                gradient: ThemeController.to.headerGradient,
                boxShadow: [
                  BoxShadow(
                    color: ThemeController.to.primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Text('GRADIENT PREVIEW',
                    style: GoogleFonts.poppins(
                        fontSize: 10, fontWeight: FontWeight.w800,
                        color: Colors.white, letterSpacing: 2.0)),
              ),
            )),

            // ── Color 2 Hex ────────────────────────────────
            _SectionLabel(label: 'GRADIENT END COLOR'),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 36, height: 36,
                  color: _hsv2.toColor().withOpacity(widget.opacity2),
                  margin: const EdgeInsets.only(right: 10),
                ),
                Expanded(
                  child: TextField(
                    controller: _hex2Ctrl,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'HEX',
                      prefixText: '#',
                      counterText: '',
                    ),
                    maxLength: 6,
                    onSubmitted: (v) {
                      final c = _hexToColor(v);
                      if (c != null) {
                        setState(() => _hsv2 = HSVColor.fromColor(c));
                        widget.onColor2(c);
                      }
                    },
                    onChanged: (v) {
                      if (v.replaceAll('#', '').length == 6) {
                        final c = _hexToColor(v);
                        if (c != null) {
                          setState(() => _hsv2 = HSVColor.fromColor(c));
                          widget.onColor2(c);
                        }
                      }
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            _SectionLabel(label: 'END COLOR HUE'),
            const SizedBox(height: 6),
            _GradientSlider(
              value: _hsv2.hue / 360,
              gradient: const LinearGradient(colors: [
                Color(0xFFFF0000), Color(0xFFFFFF00), Color(0xFF00FF00),
                Color(0xFF00FFFF), Color(0xFF0000FF), Color(0xFFFF00FF),
                Color(0xFFFF0000),
              ]),
              thumbColor: HSVColor.fromAHSV(1, _hsv2.hue, 1, 1).toColor(),
              onChanged: (v) {
                setState(() => _hsv2 = _hsv2.withHue(v * 360));
                _hex2Ctrl.text = _colorToHex(_hsv2.toColor());
                widget.onColor2(_hsv2.toColor());
              },
            ),

            const SizedBox(height: 16),

            _SectionLabel(label: 'END COLOR SATURATION'),
            const SizedBox(height: 6),
            _GradientSlider(
              value: _hsv2.saturation,
              gradient: LinearGradient(colors: [
                HSVColor.fromAHSV(1, _hsv2.hue, 0, _hsv2.value).toColor(),
                HSVColor.fromAHSV(1, _hsv2.hue, 1, _hsv2.value).toColor(),
              ]),
              thumbColor: _hsv2.toColor(),
              onChanged: (v) {
                setState(() => _hsv2 = _hsv2.withSaturation(v));
                widget.onColor2(_hsv2.toColor());
              },
            ),

            const SizedBox(height: 16),

            _SectionLabel(
                label: 'END COLOR OPACITY  ${(widget.opacity2 * 100).round()}%'),
            const SizedBox(height: 6),
            _GradientSlider(
              value: widget.opacity2,
              gradient: LinearGradient(colors: [
                _hsv2.toColor().withOpacity(0),
                _hsv2.toColor(),
              ]),
              thumbColor: _hsv2.toColor().withOpacity(widget.opacity2),
              onChanged: widget.onOpacity2,
              checkerboard: true,
            ),

            const SizedBox(height: 20),

            // ── Angle ─────────────────────────────────────
            _SectionLabel(label: 'GRADIENT ANGLE  ${widget.angle.round()}°'),
            const SizedBox(height: 6),
            _AngleWheel(
              angle:     widget.angle,
              onChanged: widget.onAngle,
              primary:   tc.primary,
            ),

            const SizedBox(height: 16),

            // Quick angles
            _SectionLabel(label: 'QUICK ANGLES'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [0, 45, 90, 135, 180, 225, 270, 315].map((a) {
                final sel = widget.angle.round() == a;
                return GestureDetector(
                  onTap: () => widget.onAngle(a.toDouble()),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? tc.primary : tc.primary.withOpacity(0.08),
                      border: Border.all(
                          color: sel ? tc.primary : tc.primary.withOpacity(0.3)),
                    ),
                    child: Text('$a°',
                        style: GoogleFonts.poppins(
                            fontSize: 11, fontWeight: FontWeight.w700,
                            color: sel ? Colors.white : tc.primary)),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // ── Quick Gradients ───────────────────────────
            _SectionLabel(label: 'QUICK GRADIENTS'),
            const SizedBox(height: 10),
            _QuickGradients(
              onSelect: (c1, c2, angle) {
                widget.onColor2(c2);
                widget.onAngle(angle);
                setState(() => _hsv2 = HSVColor.fromColor(c2));
              },
            ),
          ] else ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(Icons.gradient_rounded,
                        size: 60, color: tc.primary.withOpacity(0.3)),
                    const SizedBox(height: 12),
                    Text(
                      'Enable gradient above\nto access gradient controls',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  HSV COLOR RING WIDGET
//  Fix: use RenderBox to get actual widget size dynamically
// ════════════════════════════════════════════════════════════
class _HsvColorRing extends StatelessWidget {
  final HSVColor hsv;
  final ValueChanged<double>          onHueChanged;
  final void Function(double s, double v) onSvChanged;

  const _HsvColorRing({
    required this.hsv,
    required this.onHueChanged,
    required this.onSvChanged,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final size = constraints.maxWidth;
      return GestureDetector(
        onPanStart:  (d) => _handle(d.localPosition, size),
        onPanUpdate: (d) => _handle(d.localPosition, size),
        onTapDown:   (d) => _handle(d.localPosition, size),
        child: CustomPaint(
          size: Size(size, size),
          painter: _HsvRingPainter(hsv: hsv),
        ),
      );
    });
  }

  void _handle(Offset pos, double size) {
    final center    = Offset(size / 2, size / 2);
    final dx        = pos.dx - center.dx;
    final dy        = pos.dy - center.dy;
    final dist      = _sqrt(dx * dx + dy * dy);
    final ringOuter = size / 2;
    final ringInner = ringOuter - 22;

    if (dist >= ringInner && dist <= ringOuter) {
      // Hue ring — use dart:math-free atan2 approximation
      double angle = (_atan2(dy, dx) * 180 / 3.14159265358979) + 90;
      if (angle < 0) angle += 360;
      if (angle > 360) angle -= 360;
      onHueChanged(angle);
    } else if (dist < ringInner - 4) {
      // SV square
      final sqHalf = (ringInner - 6) / 1.414 * 0.7;
      final sqLeft = center.dx - sqHalf;
      final sqTop  = center.dy - sqHalf;
      final s = ((pos.dx - sqLeft) / (sqHalf * 2)).clamp(0.0, 1.0);
      final v = (1.0 - (pos.dy - sqTop) / (sqHalf * 2)).clamp(0.0, 1.0);
      onSvChanged(s, v);
    }
  }

  static double _sqrt(double x) {
    if (x <= 0) return 0;
    double g = x / 2;
    for (int i = 0; i < 16; i++) { g = (g + x / g) / 2; }
    return g;
  }

  static double _atan2(double y, double x) {
    if (x == 0 && y == 0) return 0;
    if (x == 0) return y > 0 ? 1.5707963 : -1.5707963;
    final r = y / x;
    double atan;
    if (r.abs() <= 1) {
      atan = r / (1 + 0.28125 * r * r);
    } else {
      atan = (r > 0 ? 1.5707963 : -1.5707963) - r / (r * r + 0.28125);
    }
    if (x < 0) return y >= 0 ? atan + 3.14159265 : atan - 3.14159265;
    return atan;
  }
}

class _HsvRingPainter extends CustomPainter {
  final HSVColor hsv;
  const _HsvRingPainter({required this.hsv});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer  = size.width / 2;
    final inner  = outer - 22;
    final midR   = (inner + outer) / 2;

    // ── Hue ring ───────────────────────────────────────────
    const steps = 360;
    final arcRect = Rect.fromCircle(center: center, radius: midR);
    for (int i = 0; i < steps; i++) {
      final startAngle = (i / steps) * 3.14159265358979 * 2 - 3.14159265358979 / 2;
      final sweep      = (1 / steps) * 3.14159265358979 * 2 + 0.02;
      canvas.drawArc(
        arcRect,
        startAngle,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 22
          ..color = HSVColor.fromAHSV(1, i.toDouble(), 1, 1).toColor(),
      );
    }

    // ── Hue indicator ─────────────────────────────────────
    final hueRad = (hsv.hue - 90) * 3.14159265358979 / 180;
    final ix = center.dx + midR * _cos(hueRad);
    final iy = center.dy + midR * _sin(hueRad);
    canvas
      ..drawCircle(Offset(ix, iy), 11,
          Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3)
      ..drawCircle(Offset(ix, iy), 9,
          Paint()..color = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor());

    // ── SV square ─────────────────────────────────────────
    final sqHalf = (inner - 6) / 1.414 * 0.7;
    final sqLeft = center.dx - sqHalf;
    final sqTop  = center.dy - sqHalf;
    final sqRect = Rect.fromLTWH(sqLeft, sqTop, sqHalf * 2, sqHalf * 2);

    canvas
      ..drawRect(sqRect,
          Paint()..shader = LinearGradient(
            colors: [Colors.white, HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()],
          ).createShader(sqRect))
      ..drawRect(sqRect,
          Paint()..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black],
          ).createShader(sqRect));

    // ── SV indicator ──────────────────────────────────────
    final svX = sqLeft + hsv.saturation * sqHalf * 2;
    final svY = sqTop  + (1 - hsv.value) * sqHalf * 2;
    canvas
      ..drawCircle(Offset(svX, svY), 9,
          Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5)
      ..drawCircle(Offset(svX, svY), 7,
          Paint()..color = hsv.toColor());
  }

  double _cos(double r) => 1 - r*r/2 + r*r*r*r/24 - r*r*r*r*r*r/720;
  double _sin(double r) => r - r*r*r/6 + r*r*r*r*r/120 - r*r*r*r*r*r*r/5040;

  @override
  bool shouldRepaint(_HsvRingPainter old) => old.hsv != hsv;
}

// ════════════════════════════════════════════════════════════
//  GRADIENT SLIDER WIDGET
// ════════════════════════════════════════════════════════════
class _GradientSlider extends StatelessWidget {
  final double          value;
  final LinearGradient  gradient;
  final Color           thumbColor;
  final ValueChanged<double> onChanged;
  final bool            checkerboard;

  const _GradientSlider({
    required this.value,
    required this.gradient,
    required this.thumbColor,
    required this.onChanged,
    this.checkerboard = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          final v = (d.localPosition.dx / w).clamp(0.0, 1.0);
          onChanged(v);
        },
        onTapDown: (d) {
          final v = (d.localPosition.dx / w).clamp(0.0, 1.0);
          onChanged(v);
        },
        child: SizedBox(
          height: 36,
          width: double.infinity,
          child: CustomPaint(
            painter: _GradSliderPainter(
              value:        value,
              gradient:     gradient,
              thumbColor:   thumbColor,
              checkerboard: checkerboard,
            ),
          ),
        ),
      );
    });
  }
}

class _GradSliderPainter extends CustomPainter {
  final double         value;
  final LinearGradient gradient;
  final Color          thumbColor;
  final bool           checkerboard;

  const _GradSliderPainter({
    required this.value,
    required this.gradient,
    required this.thumbColor,
    required this.checkerboard,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 12, size.width, 12),
      const Radius.circular(6),
    );

    if (checkerboard) {
      canvas.save();
      canvas.clipRRect(trackRect);
      final cPaint = Paint();
      const sq = 8.0;
      for (double x = 0; x < size.width; x += sq) {
        for (double row = 0; row < 12; row += sq) {
          cPaint.color = ((x ~/ sq + row ~/ sq) % 2 == 0)
              ? Colors.grey.shade300 : Colors.white;
          canvas.drawRect(Rect.fromLTWH(x, 12 + row, sq, sq), cPaint);
        }
      }
      canvas.restore();
    }

    canvas.drawRRect(
      trackRect,
      Paint()..shader = gradient.createShader(
          Rect.fromLTWH(0, 12, size.width, 12)),
    );
    canvas.drawRRect(
      trackRect,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color       = Colors.black12,
    );

    // Clamp thumb so it doesn't overflow edges
    final thumbX = (value * size.width).clamp(12.0, size.width - 12.0);
    canvas
      ..drawCircle(Offset(thumbX, 18), 12,
          Paint()..color = Colors.white)
      ..drawCircle(Offset(thumbX, 18), 10,
          Paint()..color = thumbColor)
      ..drawCircle(Offset(thumbX, 18), 12,
          Paint()..color = Colors.black12..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_GradSliderPainter old) =>
      old.value != value || old.thumbColor != thumbColor;
}

// ════════════════════════════════════════════════════════════
//  ANGLE WHEEL WIDGET
// ════════════════════════════════════════════════════════════
class _AngleWheel extends StatelessWidget {
  final double angle;
  final ValueChanged<double> onChanged;
  final Color primary;

  const _AngleWheel({
    required this.angle,
    required this.onChanged,
    required this.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight:         4,
              activeTrackColor:    primary,
              inactiveTrackColor:  primary.withOpacity(0.2),
              thumbColor:          primary,
              overlayColor:        primary.withOpacity(0.15),
            ),
            child: Slider(
              value: angle,
              min:   0,
              max:   360,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onPanUpdate: (d) {
            final box = context.findRenderObject() as RenderBox?;
            if (box == null) return;
            final local  = box.globalToLocal(d.globalPosition);
            // The wheel is always the rightmost 48px
            final center = Offset(box.size.width - 24, 24.0);
            final dx = local.dx - center.dx;
            final dy = local.dy - center.dy;
            double a = (_atan2(dy, dx) * 180 / 3.14159265358979) + 90;
            if (a < 0) a += 360;
            onChanged(a % 360);
          },
          child: SizedBox(
            width: 48, height: 48,
            child: CustomPaint(
              painter: _AngleWheelPainter(angle: angle, primary: primary),
            ),
          ),
        ),
      ],
    );
  }

  static double _atan2(double y, double x) {
    if (x == 0 && y == 0) return 0;
    if (x == 0) return y > 0 ? 1.5707963 : -1.5707963;
    final r = y / x;
    double atan;
    if (r.abs() <= 1) {
      atan = r / (1 + 0.28125 * r * r);
    } else {
      atan = (r > 0 ? 1.5707963 : -1.5707963) - r / (r * r + 0.28125);
    }
    if (x < 0) return y >= 0 ? atan + 3.14159265 : atan - 3.14159265;
    return atan;
  }
}

class _AngleWheelPainter extends CustomPainter {
  final double angle;
  final Color  primary;
  const _AngleWheelPainter({required this.angle, required this.primary});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;

    canvas
      ..drawCircle(c, r,
          Paint()..color = primary.withOpacity(0.15)..style = PaintingStyle.fill)
      ..drawCircle(c, r,
          Paint()..color = primary.withOpacity(0.4)..style = PaintingStyle.stroke..strokeWidth = 1.5);

    final rad = (angle - 90) * 3.14159265358979 / 180;
    final ex  = c.dx + r * _cos(rad);
    final ey  = c.dy + r * _sin(rad);
    canvas
      ..drawLine(c, Offset(ex, ey),
          Paint()..color = primary..strokeWidth = 2.5..strokeCap = StrokeCap.round)
      ..drawCircle(Offset(ex, ey), 4, Paint()..color = primary)
      ..drawCircle(c, 3, Paint()..color = primary.withOpacity(0.5));
  }

  double _cos(double r) => 1 - r*r/2 + r*r*r*r/24 - r*r*r*r*r*r/720;
  double _sin(double r) => r - r*r*r/6 + r*r*r*r*r/120 - r*r*r*r*r*r*r/5040;

  @override
  bool shouldRepaint(_AngleWheelPainter old) =>
      old.angle != angle || old.primary != primary;
}

// ════════════════════════════════════════════════════════════
//  QUICK PALETTE WIDGET
// ════════════════════════════════════════════════════════════
const _kQuickColors = [
  Color(0xFF3C5D9C), Color(0xFF1A237E), Color(0xFF006994),
  Color(0xFF1B4332), Color(0xFFE63946), Color(0xFF6A0572),
  Color(0xFFB5451B), Color(0xFF37474F), Color(0xFF00695C),
  Color(0xFFC7971A), Color(0xFF8B0000), Color(0xFF263238),
  Color(0xFF880E4F), Color(0xFF4A148C), Color(0xFF01579B),
  Color(0xFF1B5E20), Color(0xFFFF6F00), Color(0xFF3E2723),
  Color(0xFF212121), Color(0xFF004D40), Color(0xFFBF360C),
  Color(0xFF0D47A1), Color(0xFF33691E), Color(0xFF827717),
];

class _QuickPalette extends StatelessWidget {
  final ValueChanged<Color> onSelect;
  const _QuickPalette({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: _kQuickColors.map((c) => GestureDetector(
        onTap: () => onSelect(c),
        child: Container(width: 32, height: 32, color: c),
      )).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  QUICK GRADIENTS WIDGET
// ════════════════════════════════════════════════════════════
const _kQuickGradients = [
  [Color(0xFF3C5D9C), Color(0xFF5A7BB8), 135.0],
  [Color(0xFFE63946), Color(0xFFFF6B6B), 45.0],
  [Color(0xFF1B4332), Color(0xFF52B788), 135.0],
  [Color(0xFF6A0572), Color(0xFFC77DFF), 150.0],
  [Color(0xFF006994), Color(0xFF00B4D8), 120.0],
  [Color(0xFFC7971A), Color(0xFFFFD166), 135.0],
  [Color(0xFF880E4F), Color(0xFFFF80AB), 135.0],
  [Color(0xFF004D40), Color(0xFF64FFDA), 120.0],
];

class _QuickGradients extends StatelessWidget {
  final void Function(Color c1, Color c2, double angle) onSelect;
  const _QuickGradients({required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10, runSpacing: 10,
      children: _kQuickGradients.map((g) {
        final c1    = g[0] as Color;
        final c2    = g[1] as Color;
        final angle = g[2] as double;
        return GestureDetector(
          onTap: () => onSelect(c1, c2, angle),
          child: Container(
            width: 56, height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [c1, c2],
                begin: Alignment.centerLeft,
                end:   Alignment.centerRight,
              ),
              border: Border.all(color: Colors.white24),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Section label ──────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    // Use Obx so the accent bar updates when primary color changes
    return Obx(() => Row(
      children: [
        Container(
          width: 3, height: 14,
          color: ThemeController.to.primary,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 9, fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: ThemeController.to.primary,
          ),
        ),
      ],
    ));
  }
}