import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'firebase_options.dart';
import 'dashboard_screen.dart';
import 'invoice_screens.dart';
import 'expense_screens.dart';

// firebase_options.dart is imported above — real keys from FlutterFire CLI

// ════════════════════════════════════════════════════════════
//  MAIN ENTRY POINT
// ════════════════════════════════════════════════════════════
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Init settings (loads persisted theme before first frame)
  Get.put(SettingsController());

  runApp(const BillifyApp());
}

// ════════════════════════════════════════════════════════════
//  BRAND CONSTANTS
// ════════════════════════════════════════════════════════════
class BillifyColors {
  // Primary — Deep Indigo
  static const Color primary        = Color(0xFF1A237E);
  static const Color primaryLight   = Color(0xFF534BAE);
  static const Color primaryDark    = Color(0xFF000051);

  // Accent — Amber / Gold
  static const Color accent         = Color(0xFFFFC107);
  static const Color accentDark     = Color(0xFFC79100);

  // Status colors
  static const Color paid           = Color(0xFF2E7D32); // green
  static const Color unpaid         = Color(0xFFC62828); // red
  static const Color draft          = Color(0xFF757575); // grey
  static const Color overdue        = Color(0xFFE65100); // orange

  // Neutral
  static const Color background     = Color(0xFFF5F6FA);
  static const Color surface        = Color(0xFFFFFFFF);
  static const Color textPrimary    = Color(0xFF1A1A2E);
  static const Color textSecondary  = Color(0xFF6B7280);
  static const Color divider        = Color(0xFFE5E7EB);

  // Dark theme
  static const Color darkBackground = Color(0xFF0D0D1A);
  static const Color darkSurface    = Color(0xFF1C1C2E);
  static const Color darkCard       = Color(0xFF252538);
}

// ════════════════════════════════════════════════════════════
//  APP THEMES
// ════════════════════════════════════════════════════════════
class BillifyTheme {
  // ── Light Theme ──
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BillifyColors.primary,
        brightness: Brightness.light,
        primary:   BillifyColors.primary,
        secondary: BillifyColors.accent,
        surface:   BillifyColors.surface,
        background: BillifyColors.background,
      ),
      scaffoldBackgroundColor: BillifyColors.background,
    );

    return base.copyWith(
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).copyWith(
        // Display / Heading — Poppins
        displayLarge:  GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w700, color: BillifyColors.textPrimary),
        displayMedium: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: BillifyColors.textPrimary),
        displaySmall:  GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w600, color: BillifyColors.textPrimary),
        headlineLarge: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: BillifyColors.textPrimary),
        headlineMedium:GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: BillifyColors.textPrimary),
        headlineSmall: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: BillifyColors.textPrimary),
        // Body — Nunito
        bodyLarge:     GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w400, color: BillifyColors.textPrimary),
        bodyMedium:    GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w400, color: BillifyColors.textPrimary),
        bodySmall:     GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w400, color: BillifyColors.textSecondary),
        labelLarge:    GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: BillifyColors.textPrimary),
        labelMedium:   GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w500, color: BillifyColors.textSecondary),
        labelSmall:    GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w400, color: BillifyColors.textSecondary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor:  BillifyColors.primary,
        foregroundColor:  Colors.white,
        elevation:        0,
        centerTitle:      true,
        titleTextStyle:   GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        iconTheme:        const IconThemeData(color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color:      BillifyColors.surface,
        elevation:  2,
        shadowColor: BillifyColors.primary.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor:  BillifyColors.primary,
          foregroundColor:  Colors.white,
          elevation:        2,
          minimumSize:      const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BillifyColors.primary,
          side: const BorderSide(color: BillifyColors.primary, width: 1.5),
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled:      true,
        fillColor:   BillifyColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BillifyColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BillifyColors.divider, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BillifyColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BillifyColors.unpaid, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: GoogleFonts.nunito(color: BillifyColors.textSecondary),
        hintStyle:  GoogleFonts.nunito(color: BillifyColors.textSecondary.withOpacity(0.7)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: BillifyColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: BillifyColors.surface,
        selectedItemColor: BillifyColors.primary,
        unselectedItemColor: BillifyColors.textSecondary,
        elevation: 8,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: BillifyColors.surface,
        elevation: 4,
      ),
      dividerTheme: const DividerThemeData(
        color: BillifyColors.divider,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor:    BillifyColors.background,
        selectedColor:      BillifyColors.primary.withOpacity(0.15),
        labelStyle:         GoogleFonts.nunito(fontSize: 12, fontWeight: FontWeight.w500),
        side: const BorderSide(color: BillifyColors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BillifyColors.darkSurface,
        contentTextStyle: GoogleFonts.nunito(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: BillifyColors.textPrimary),
        contentTextStyle: GoogleFonts.nunito(fontSize: 14, color: BillifyColors.textSecondary),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) return BillifyColors.primary;
          return Colors.transparent;
        }),
        side: const BorderSide(color: BillifyColors.primary, width: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: BillifyColors.primary,
      ),
    );
  }

  // ── Dark Theme ──
  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BillifyColors.primary,
        brightness: Brightness.dark,
        primary:    BillifyColors.primaryLight,
        secondary:  BillifyColors.accent,
        surface:    BillifyColors.darkSurface,
        background: BillifyColors.darkBackground,
      ),
      scaffoldBackgroundColor: BillifyColors.darkBackground,
    );

    return base.copyWith(
      textTheme: GoogleFonts.poppinsTextTheme(base.textTheme).copyWith(
        displayLarge:  GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
        displayMedium: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
        headlineLarge: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
        bodyLarge:     GoogleFonts.nunito(fontSize: 16, color: Colors.white70),
        bodyMedium:    GoogleFonts.nunito(fontSize: 14, color: Colors.white70),
        bodySmall:     GoogleFonts.nunito(fontSize: 12, color: Colors.white54),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor:    BillifyColors.darkSurface,
        foregroundColor:    Colors.white,
        elevation:          0,
        centerTitle:        true,
        titleTextStyle:     GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: CardThemeData(
        color:     BillifyColors.darkCard,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BillifyColors.primaryLight,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled:    true,
        fillColor: BillifyColors.darkCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: BillifyColors.primaryLight, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: GoogleFonts.nunito(color: Colors.white54),
        hintStyle:  GoogleFonts.nunito(color: Colors.white38),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: BillifyColors.primaryLight,
        foregroundColor: Colors.white,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: BillifyColors.darkSurface,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  ROUTE NAMES
// ════════════════════════════════════════════════════════════
class AppRoutes {
  static const splash           = '/splash';
  static const login            = '/login';
  static const register         = '/register';
  static const forgotPassword   = '/forgot-password';
  static const termsConditions  = '/terms-conditions';
  static const dashboard        = '/dashboard';
  static const invoices         = '/invoices';
  static const invoiceCreate    = '/invoice-create';
  static const invoiceEdit      = '/invoice-edit';
  static const invoiceDetail    = '/invoice-detail';
  static const expenses         = '/expenses';
  static const expenseAdd       = '/expense-add';
  static const profile          = '/profile';
  static const settings         = '/settings';
  static const lock             = '/lock';
}

// ════════════════════════════════════════════════════════════
//  AUTH MIDDLEWARE — protects dashboard & inner routes
// ════════════════════════════════════════════════════════════
class AuthMiddleware extends GetMiddleware {
  @override
  int? get priority => 1;

  @override
  RouteSettings? redirect(String? route) {
    final user = FirebaseAuth.instance.currentUser;

    // Not logged in → go to login
    if (user == null) {
      return const RouteSettings(name: AppRoutes.login);
    }
    return null; // allow
  }
}

// ────────────────────────────────────────────────────────────
//  TERMS MIDDLEWARE — checks if terms have been accepted
// ────────────────────────────────────────────────────────────
class TermsMiddleware extends GetMiddleware {
  @override
  int? get priority => 2;

  @override
  RouteSettings? redirect(String? route) {
    // SharedPreferences sync check (fast path)
    // Full async check happens in SplashScreen
    return null;
  }
}

// ════════════════════════════════════════════════════════════
//  ROOT APP WIDGET
// ════════════════════════════════════════════════════════════
class BillifyApp extends StatefulWidget {
  const BillifyApp({super.key});
  @override
  State<BillifyApp> createState() => _BillifyAppState();
}

class _BillifyAppState extends State<BillifyApp>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Get.isRegistered<SettingsController>()) return;
    final ctrl = SettingsController.to;
    // Only mark background on paused — inactive fires too often (dialogs, etc.)
    if (state == AppLifecycleState.paused) {
      ctrl.onBackground();
    } else if (state == AppLifecycleState.resumed) {
      ctrl.onForeground();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      // ── Identity ──
      title:           'Billify',
      debugShowCheckedModeBanner: false,

      // ── Themes — driven by SettingsController ──
      theme:     BillifyTheme.light,
      darkTheme: BillifyTheme.dark,
      themeMode: ThemeMode.system,

      // ── Default route ──
      initialRoute: AppRoutes.splash,

      // ── All named routes ──
      getPages: [
        // Splash
        GetPage(
          name:       AppRoutes.splash,
          page:       () => const SplashScreen(),
          transition: Transition.fadeIn,
        ),

        // Auth
        GetPage(
          name:       AppRoutes.login,
          page:       () => const LoginScreen(),
          transition: Transition.fadeIn,
        ),
        GetPage(
          name:       AppRoutes.register,
          page:       () => const RegisterScreen(),
          transition: Transition.rightToLeft,
        ),
        GetPage(
          name:       AppRoutes.forgotPassword,
          page:       () => const ForgotPasswordScreen(),
          transition: Transition.rightToLeft,
        ),

        // Onboarding
        GetPage(
          name:       AppRoutes.termsConditions,
          page:       () => const TermsConditionsScreen(),
          transition: Transition.upToDown,
          middlewares: [AuthMiddleware()],
        ),

        // Main App — protected by AuthMiddleware
        GetPage(
          name:       AppRoutes.dashboard,
          page:       () => const DashboardScreen(),
          transition: Transition.fadeIn,
          middlewares: [AuthMiddleware()],
        ),
        GetPage(
          name:       AppRoutes.invoices,
          page:       () => const InvoiceListScreen(),
          transition: Transition.rightToLeft,
          middlewares: [AuthMiddleware()],
        ),
        GetPage(
          name:       AppRoutes.invoiceCreate,
          page:       () => const InvoiceCreateScreen(),
          transition: Transition.rightToLeft,
          middlewares: [AuthMiddleware()],
        ),
        GetPage(
          name:       AppRoutes.invoiceEdit,
          page:       () => const InvoiceEditScreen(),
          transition: Transition.rightToLeft,
          middlewares: [AuthMiddleware()],
        ),
        GetPage(
          name:       AppRoutes.invoiceDetail,
          page:       () => const InvoiceDetailScreen(),
          transition: Transition.rightToLeft,
          middlewares: [AuthMiddleware()],
        ),
        GetPage(
          name:       AppRoutes.expenses,
          page:       () => const ExpenseListScreen(),
          transition: Transition.rightToLeft,
          middlewares: [AuthMiddleware()],
        ),
        GetPage(
          name:       AppRoutes.expenseAdd,
          page:       () => const AddExpenseScreen(),
          transition: Transition.rightToLeft,
          middlewares: [AuthMiddleware()],
        ),
        GetPage(
          name:       AppRoutes.profile,
          page:       () => const ProfileScreen(),
          transition: Transition.rightToLeft,
          middlewares: [AuthMiddleware()],
        ),
        GetPage(
          name:       AppRoutes.settings,
          page:       () => const SettingsScreen(),
          transition: Transition.rightToLeft,
          middlewares: [AuthMiddleware()],
        ),
        GetPage(
          name:       AppRoutes.lock,
          page:       () => const LockScreen(),
          transition: Transition.fadeIn,
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════
//  SPLASH SCREEN — routing logic
// ════════════════════════════════════════════════════════════
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double>   _fadeAnim;
  late Animation<double>   _scaleAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim  = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _scaleAnim = Tween<double>(begin: 0.7, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _controller.forward();
    _navigate();
  }

  /// Decides where to send the user after splash
  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2400));

    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // Not logged in → Login
      Get.offAllNamed(AppRoutes.login);
      return;
    }

    // Logged in — check if terms have been accepted
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final termsAccepted = doc.data()?['termsAccepted'] ?? false;

      if (termsAccepted) {
        Get.offAllNamed(AppRoutes.dashboard);
        // Trigger lock check on cold launch (after reaching dashboard)
        if (Get.isRegistered<SettingsController>()) {
          SettingsController.to.onForeground();
        }
      } else {
        Get.offAllNamed(AppRoutes.termsConditions);
      }
    } catch (_) {
      Get.offAllNamed(AppRoutes.login);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillifyColors.primary,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo container
                Container(
                  width:  100,
                  height: 100,
                  decoration: BoxDecoration(
                    color:        Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withOpacity(0.2),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.receipt_long_rounded,
                      color: BillifyColors.primary,
                      size: 56,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // App name
                Text(
                  'Billify',
                  style: GoogleFonts.poppins(
                    fontSize:   38,
                    fontWeight: FontWeight.w800,
                    color:      Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Smart Invoicing. Simple Finance.',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    color:    Colors.white70,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 40),
                // Loading indicator
                SizedBox(
                  width:  40,
                  height: 40,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      BillifyColors.accent,
                    ),
                    strokeWidth: 3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// ════════════════════════════════════════════════════════════
//  SHARED DIALOG / SHEET DESIGN SYSTEM
//  All popups in the app use these helpers for visual consistency.
// ════════════════════════════════════════════════════════════

/// Rounded dialog base — used for all AlertDialog-style popups.
class BillifyDialog extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   title;
  final String   body;
  final String   cancelLabel;
  final String   confirmLabel;
  final Color    confirmColor;
  final VoidCallback? onConfirm;

  const BillifyDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.cancelLabel  = 'Cancel',
    this.confirmLabel = 'Confirm',
    this.confirmColor = BillifyColors.primary,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon badge
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 30),
            ),
            const SizedBox(height: 18),
            // Title
            Text(title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 17, fontWeight: FontWeight.w700,
                    color: BillifyColors.textPrimary)),
            const SizedBox(height: 10),
            // Body
            Text(body,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                    fontSize: 14, height: 1.5,
                    color: BillifyColors.textSecondary)),
            const SizedBox(height: 24),
            // Buttons — stacked
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: onConfirm,
                child: Text(confirmLabel,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700, fontSize: 14,
                        color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  backgroundColor: BillifyColors.background,
                ),
                onPressed: () => Get.back(result: false),
                child: Text(cancelLabel,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600, fontSize: 14,
                        color: BillifyColors.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Input dialog — title + single TextField + Save/Cancel.
class BillifyInputDialog extends StatefulWidget {
  final String   title;
  final String   hint;
  final String   initialValue;
  final TextInputType keyboard;
  final IconData icon;

  const BillifyInputDialog({
    required this.title,
    required this.hint,
    required this.initialValue,
    this.keyboard = TextInputType.text,
    this.icon = Icons.edit_rounded,
  });

  @override
  State<BillifyInputDialog> createState() => BillifyInputDialogState();
}

class BillifyInputDialogState extends State<BillifyInputDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: BillifyColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon,
                    color: BillifyColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Text(widget.title,
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: BillifyColors.textPrimary)),
            ]),
            const SizedBox(height: 18),
            // Field
            TextField(
              controller: _ctrl,
              keyboardType: widget.keyboard,
              autofocus: true,
              decoration: InputDecoration(
                hintText: widget.hint,
                prefixIcon: Icon(widget.icon,
                    color: BillifyColors.primary, size: 18),
              ),
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600, fontSize: 15),
            ),
            const SizedBox(height: 20),
            // Actions
            Row(children: [
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    backgroundColor: BillifyColors.background,
                    minimumSize: const Size(0, 46),
                  ),
                  onPressed: () => Get.back(),
                  child: Text('Cancel',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          color: BillifyColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    minimumSize: const Size(0, 46),
                    elevation: 0,
                  ),
                  onPressed: () => Get.back(result: _ctrl.text.trim()),
                  child: Text('Save',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Image source picker — bottom-sheet style two-option sheet.
class BillifyImageSourceSheet extends StatelessWidget {
  final String title;
  const BillifyImageSourceSheet({this.title = 'Choose Source'});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: BillifyColors.divider,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 18),
          Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: BillifyColors.textPrimary)),
          const SizedBox(height: 18),
          BillifySourceOption(
            icon: Icons.photo_library_rounded,
            label: 'Choose from Gallery',
            subtitle: 'Pick an existing photo',
            color: BillifyColors.primary,
            onTap: () => Get.back(result: ImageSource.gallery),
          ),
          const SizedBox(height: 10),
          BillifySourceOption(
            icon: Icons.camera_alt_rounded,
            label: 'Take a Photo',
            subtitle: 'Use camera to capture',
            color: const Color(0xFF00897B),
            onTap: () => Get.back(result: ImageSource.camera),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: BillifyColors.background,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                minimumSize: const Size(0, 44),
              ),
              onPressed: () => Get.back(),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(
                      fontWeight: FontWeight.w600,
                      color: BillifyColors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}

class BillifySourceOption extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   subtitle;
  final Color    color;
  final VoidCallback onTap;
  const BillifySourceOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: BillifyColors.textPrimary)),
            Text(subtitle,
                style: GoogleFonts.nunito(
                    fontSize: 12, color: BillifyColors.textSecondary)),
          ],
        ),
      ]),
    ),
  );
}

// ─── Generic Options Sheet ────────────────────────────────────────────────────
class BillifyOptionsSheet<T> extends StatelessWidget {
  final String            title;
  final List<T>           options;
  final T                 current;
  final String Function(T) label;
  final ValueChanged<T>   onSelect;

  const BillifyOptionsSheet({
    required this.title,
    required this.options,
    required this.current,
    required this.label,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: BillifyColors.divider,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: BillifyColors.primary.withOpacity(0.09),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.tune_rounded,
                  color: BillifyColors.primary, size: 16),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: BillifyColors.textPrimary)),
          ]),
          const SizedBox(height: 16),
          ...options.map((opt) {
            final isSelected = opt == current;
            return GestureDetector(
              onTap: () { Get.back(); onSelect(opt); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? BillifyColors.primary.withOpacity(0.07)
                      : BillifyColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? BillifyColors.primary : BillifyColors.divider,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Row(children: [
                  // Selection dot
                  Container(
                    width: 18, height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? BillifyColors.primary : Colors.transparent,
                      border: Border.all(
                        color: isSelected ? BillifyColors.primary : BillifyColors.textSecondary.withOpacity(0.4),
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 11)
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(label(opt),
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? BillifyColors.primary
                              : BillifyColors.textPrimary,
                        )),
                  ),
                ]),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  SIDE DRAWER — Premium redesign with layered gradient header
// ════════════════════════════════════════════════════════════
class BillifyDrawer extends StatefulWidget {
  final String activeRoute;
  const BillifyDrawer({super.key, required this.activeRoute});

  @override
  State<BillifyDrawer> createState() => _BillifyDrawerState();
}

class _BillifyDrawerState extends State<BillifyDrawer>
    with SingleTickerProviderStateMixin {
  String? _logoBase64;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _loadLogo();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLogo() async {
    final prefs = await SharedPreferences.getInstance();
    final b64   = prefs.getString(_PrefKeys.logoBase64);
    if (mounted) setState(() => _logoBase64 = b64);
  }

  void _logout() {
    Get.dialog(
      BillifyDialog(
        icon:         Icons.logout_rounded,
        iconColor:    BillifyColors.unpaid,
        title:        'Sign Out',
        body:         'Are you sure you want to sign out of Billify?',
        confirmLabel: 'Sign Out',
        confirmColor: BillifyColors.unpaid,
        onConfirm: () async {
          await FirebaseAuth.instance.signOut();
          Get.offAllNamed(AppRoutes.login);
        },
      ),
    );
  }

  int _drawerMissingCount(Map<String, dynamic> data) {
    int c = 0;
    if ((data['fullName']      as String? ?? '').isEmpty) c++;
    if ((data['businessName']  as String? ?? '').isEmpty) c++;
    if ((data['phone']         as String? ?? '').isEmpty) c++;
    if ((data['address']       as String? ?? '').isEmpty) c++;
    if ((data['gstNumber']     as String? ?? '').isEmpty) c++;
    if ((data['panNumber']     as String? ?? '').isEmpty) c++;
    if ((data['bankName']      as String? ?? '').isEmpty) c++;
    if ((data['accountNumber'] as String? ?? '').isEmpty) c++;
    if ((data['ifscCode']      as String? ?? '').isEmpty) c++;
    if (_logoBase64 == null) c++;
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final authUser      = FirebaseAuth.instance.currentUser;
    final emailVerified = authUser?.emailVerified ?? false;

    return Drawer(
      width: 288,
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Container(
          decoration: BoxDecoration(
            color: BillifyColors.surface,
            borderRadius: const BorderRadius.only(
              topRight:    Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color:      BillifyColors.primary.withOpacity(0.18),
                blurRadius: 32,
                offset:     const Offset(8, 0),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topRight:    Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            child: Column(
              children: [
                // ── Rich Header ────────────────────────────
                StreamBuilder<DocumentSnapshot>(
                  stream: authUser == null
                      ? const Stream.empty()
                      : FirebaseFirestore.instance
                      .collection('users')
                      .doc(authUser.uid)
                      .snapshots(),
                  builder: (context, snap) {
                    final data = (snap.data?.data() as Map<String, dynamic>?) ?? {};
                    final displayName  = data['fullName']     as String?
                        ?? authUser?.displayName ?? 'Billify User';
                    final businessName = data['businessName'] as String? ?? '';
                    final email        = data['email']        as String?
                        ?? authUser?.email ?? '';
                    final missing      = _drawerMissingCount(data);
                    final initials     = displayName.isNotEmpty
                        ? displayName[0].toUpperCase() : 'B';

                    return _DrawerHeader(
                      displayName:   displayName,
                      businessName:  businessName,
                      email:         email,
                      emailVerified: emailVerified,
                      logoBase64:    _logoBase64,
                      initials:      initials,
                      missingCount:  missing,
                      onProfileTap: () {
                        Navigator.of(context).pop();
                        Get.offAllNamed(AppRoutes.dashboard);
                        Get.toNamed(AppRoutes.profile);
                      },
                    );
                  },
                ),

                // ── Profile incomplete banner ───────────────
                StreamBuilder<DocumentSnapshot>(
                  stream: authUser == null
                      ? const Stream.empty()
                      : FirebaseFirestore.instance
                      .collection('users')
                      .doc(authUser.uid)
                      .snapshots(),
                  builder: (context, snap) {
                    final data    = (snap.data?.data() as Map<String, dynamic>?) ?? {};
                    final missing = _drawerMissingCount(data);
                    if (missing == 0 && _logoBase64 != null) {
                      return const SizedBox.shrink();
                    }
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        Get.offAllNamed(AppRoutes.dashboard);
                        Get.toNamed(AppRoutes.profile);
                      },
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFE8F0FE),
                              BillifyColors.primary.withOpacity(0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: BillifyColors.primary.withOpacity(0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color:  BillifyColors.primary.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit_rounded,
                                  color: BillifyColors.primary, size: 12),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Complete profile · $missing pending',
                                style: GoogleFonts.nunito(
                                    fontSize: 12,
                                    color: BillifyColors.primary,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: BillifyColors.primary, size: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),

                // ── Section label: Main ─────────────────────
                _DrawerSectionLabel(label: 'MAIN'),

                // ── Nav Items ──────────────────────────────
                _NavItem(
                  icon:        Icons.dashboard_rounded,
                  label:       'Dashboard',
                  route:       AppRoutes.dashboard,
                  activeRoute: widget.activeRoute,
                ),
                _NavItem(
                  icon:        Icons.receipt_long_rounded,
                  label:       'Invoices',
                  route:       AppRoutes.invoices,
                  activeRoute: widget.activeRoute,
                ),
                _NavItem(
                  icon:        Icons.account_balance_wallet_rounded,
                  label:       'Expenses & Income',
                  route:       AppRoutes.expenses,
                  activeRoute: widget.activeRoute,
                ),
                _NavItem(
                  icon:        Icons.person_rounded,
                  label:       'My Profile',
                  route:       AppRoutes.profile,
                  activeRoute: widget.activeRoute,
                ),

                // ── Section label: More ─────────────────────
                _DrawerSectionLabel(label: 'MORE'),

                _NavItem(
                  icon:        Icons.description_rounded,
                  label:       'Terms & Conditions',
                  route:       AppRoutes.termsConditions,
                  activeRoute: widget.activeRoute,
                ),
                _NavItem(
                  icon:        Icons.settings_rounded,
                  label:       'Settings',
                  route:       AppRoutes.settings,
                  activeRoute: widget.activeRoute,
                ),

                const Spacer(),

                // ── Logout ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _logout,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 13),
                        decoration: BoxDecoration(
                          color: BillifyColors.unpaid.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: BillifyColors.unpaid.withOpacity(0.18)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color:  BillifyColors.unpaid.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.logout_rounded,
                                  color: BillifyColors.unpaid, size: 16),
                            ),
                            const SizedBox(width: 12),
                            Text('Sign Out',
                                style: GoogleFonts.poppins(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: BillifyColors.unpaid)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Version footer ─────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 20, top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 5, height: 5,
                        decoration: const BoxDecoration(
                            color: BillifyColors.primary,
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text('Billify  v1.0.0',
                          style: GoogleFonts.poppins(
                              fontSize: 10,
                              letterSpacing: 1.2,
                              color: BillifyColors.textSecondary
                                  .withOpacity(0.6),
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Drawer Header widget ──────────────────────────────────
class _DrawerHeader extends StatelessWidget {
  final String displayName;
  final String businessName;
  final String email;
  final bool   emailVerified;
  final String? logoBase64;
  final String initials;
  final int    missingCount;
  final VoidCallback onProfileTap;

  const _DrawerHeader({
    required this.displayName,
    required this.businessName,
    required this.email,
    required this.emailVerified,
    required this.logoBase64,
    required this.initials,
    required this.missingCount,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onProfileTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 52, 20, 22),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              BillifyColors.primaryDark,
              BillifyColors.primary,
              BillifyColors.primaryLight,
            ],
            begin: Alignment.topLeft,
            end:   Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Decorative circles
            Positioned(
              top: -24, right: -20,
              child: Container(
                width: 110, height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            Positioned(
              bottom: -10, right: 40,
              child: Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.04),
                ),
              ),
            ),

            // Content
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar row
                Row(
                  children: [
                    Stack(
                      children: [
                        Container(
                          width: 62, height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.6), width: 2),
                            boxShadow: [
                              BoxShadow(
                                color:      Colors.black.withOpacity(0.25),
                                blurRadius: 12,
                                offset:     const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: logoBase64 != null
                                ? Image.memory(
                              base64Decode(logoBase64!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _HeaderInitials(initials),
                            )
                                : Container(
                              color: Colors.white.withOpacity(0.15),
                              child: _HeaderInitials(initials),
                            ),
                          ),
                        ),
                        // Badge
                        if (missingCount > 0)
                          Positioned(
                            top: 0, right: 0,
                            child: Container(
                              width: 18, height: 18,
                              decoration: BoxDecoration(
                                color:  BillifyColors.overdue,
                                shape:  BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: Center(
                                child: Text('$missingCount',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800)),
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(width: 14),

                    // App brand pill
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color:        Colors.white.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border:       Border.all(
                                  color: Colors.white.withOpacity(0.25)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.receipt_long_rounded,
                                    color: Colors.white70, size: 11),
                                const SizedBox(width: 5),
                                Text('Billify',
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.5)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Display name
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.2),
                ),

                if (businessName.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    businessName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.nunito(
                        fontSize: 12.5, color: Colors.white70),
                  ),
                ],

                const SizedBox(height: 6),

                // Email row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                            fontSize: 11.5, color: Colors.white54),
                      ),
                    ),
                    if (emailVerified) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color:        Colors.greenAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.greenAccent.withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified_rounded,
                                size: 10, color: Colors.greenAccent),
                            const SizedBox(width: 3),
                            Text('Verified',
                                style: GoogleFonts.nunito(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.greenAccent)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderInitials extends StatelessWidget {
  final String initials;
  const _HeaderInitials(this.initials);
  @override
  Widget build(BuildContext context) => Center(
    child: Text(initials,
        style: GoogleFonts.poppins(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Colors.white)),
  );
}

// ── Section label ─────────────────────────────────────────
class _DrawerSectionLabel extends StatelessWidget {
  final String label;
  const _DrawerSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Text(
      label,
      style: GoogleFonts.poppins(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.8,
          color: BillifyColors.textSecondary.withOpacity(0.55)),
    ),
  );
}

// ── Nav Item ──────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   route;
  final String   activeRoute;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.activeRoute,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = activeRoute == route;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            Navigator.of(context).pop();
            if (isActive) return;
            if (route == AppRoutes.dashboard) {
              Get.offAllNamed(AppRoutes.dashboard);
            } else {
              Get.offAllNamed(AppRoutes.dashboard);
              Get.toNamed(route);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: isActive
                  ? LinearGradient(
                colors: [
                  BillifyColors.primary,
                  BillifyColors.primaryLight,
                ],
                begin: Alignment.centerLeft,
                end:   Alignment.centerRight,
              )
                  : null,
              color: isActive ? null : Colors.transparent,
            ),
            child: Row(
              children: [
                // Icon container
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.white.withOpacity(0.2)
                        : BillifyColors.primary.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    size: 17,
                    color: isActive
                        ? Colors.white
                        : BillifyColors.primary.withOpacity(0.7),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.poppins(
                      fontSize: 13.5,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive
                          ? Colors.white
                          : BillifyColors.textPrimary,
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  AUTH SCREENS
// ════════════════════════════════════════════════════════════

// ── Login Screen ──────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool  _obscure      = true;
  bool  _loading      = false;

  Future<void> _login() async {
    if (_emailCtrl.text.trim().isEmpty || _passwordCtrl.text.isEmpty) {
      Get.snackbar('Error', 'Please fill in all fields',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email:    _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      // Check terms
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final termsAccepted = doc.data()?['termsAccepted'] ?? false;
      Get.offAllNamed(termsAccepted ? AppRoutes.dashboard : AppRoutes.termsConditions);
    } on FirebaseAuthException catch (e) {
      Get.snackbar('Login Failed', e.message ?? 'An error occurred',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    if (_emailCtrl.text.trim().isEmpty) {
      Get.snackbar('Enter Email', 'Please enter your email to reset password',
          backgroundColor: BillifyColors.overdue, colorText: Colors.white);
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _emailCtrl.text.trim());
      Get.snackbar('Email Sent', 'Password reset link sent to ${_emailCtrl.text.trim()}',
          backgroundColor: BillifyColors.paid, colorText: Colors.white);
    } catch (e) {
      Get.snackbar('Error', 'Could not send reset email',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillifyColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Logo
              Center(
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: BillifyColors.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 40),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text('Billify',
                    style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.w800,
                        color: BillifyColors.primary)),
              ),
              Center(
                child: Text('Sign in to your account',
                    style: GoogleFonts.nunito(color: BillifyColors.textSecondary)),
              ),
              const SizedBox(height: 40),

              // Email
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: Icon(Icons.email_rounded, color: BillifyColors.primary),
                ),
              ),
              const SizedBox(height: 16),

              // Password
              TextField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_rounded, color: BillifyColors.primary),
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                        color: BillifyColors.textSecondary),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Forgot password
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _forgotPassword,
                  child: Text('Forgot Password?',
                      style: GoogleFonts.nunito(color: BillifyColors.primary, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 24),

              // Login button
              _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                onPressed: _login,
                child: const Text('Login'),
              ),
              const SizedBox(height: 16),

              // Register link
              Center(
                child: GestureDetector(
                  onTap: () => Get.toNamed(AppRoutes.register),
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",
                      style: GoogleFonts.nunito(color: BillifyColors.textSecondary),
                      children: [
                        TextSpan(
                          text: 'Register',
                          style: GoogleFonts.nunito(
                              color: BillifyColors.primary, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Register Screen ───────────────────────────────────────
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameCtrl         = TextEditingController();
  final _businessCtrl     = TextEditingController();
  final _emailCtrl        = TextEditingController();
  final _passwordCtrl     = TextEditingController();
  final _confirmPassCtrl  = TextEditingController();
  bool  _obscure          = true;
  bool  _loading          = false;

  Future<void> _register() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _businessCtrl.text.trim().isEmpty ||
        _emailCtrl.text.trim().isEmpty ||
        _passwordCtrl.text.isEmpty) {
      Get.snackbar('Error', 'Please fill in all fields',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
      return;
    }
    if (_passwordCtrl.text != _confirmPassCtrl.text) {
      Get.snackbar('Error', 'Passwords do not match',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
      return;
    }
    if (_passwordCtrl.text.length < 6) {
      Get.snackbar('Error', 'Password must be at least 6 characters',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
      return;
    }

    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email:    _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      // Update display name
      await cred.user!.updateDisplayName(_nameCtrl.text.trim());

      // Create Firestore user profile document
      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set({
        'uid':              cred.user!.uid,
        'fullName':         _nameCtrl.text.trim(),
        'businessName':     _businessCtrl.text.trim(),
        'email':            _emailCtrl.text.trim(),
        'phone':            '',
        'address':          '',
        'gstNumber':        '',
        'panNumber':        '',
        'logoUrl':          '',
        'photoUrl':         '',
        'termsAccepted':    false,
        'termsAcceptedAt':  null,
        'createdAt':        FieldValue.serverTimestamp(),
      });

      Get.offAllNamed(AppRoutes.termsConditions);
    } on FirebaseAuthException catch (e) {
      Get.snackbar('Registration Failed', e.message ?? 'An error occurred',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text('Join Billify',
                style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w700,
                    color: BillifyColors.primary)),
            Text('Create your free account',
                style: GoogleFonts.nunito(color: BillifyColors.textSecondary)),
            const SizedBox(height: 32),

            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Full Name',
                prefixIcon: Icon(Icons.person_rounded, color: BillifyColors.primary),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _businessCtrl,
              decoration: const InputDecoration(
                labelText: 'Business Name',
                prefixIcon: Icon(Icons.business_rounded, color: BillifyColors.primary),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                prefixIcon: Icon(Icons.email_rounded, color: BillifyColors.primary),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_rounded, color: BillifyColors.primary),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                      color: BillifyColors.textSecondary),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPassCtrl,
              obscureText: _obscure,
              decoration: const InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: Icon(Icons.lock_outline_rounded, color: BillifyColors.primary),
              ),
            ),
            const SizedBox(height: 32),

            _loading
                ? const CircularProgressIndicator()
                : ElevatedButton(
              onPressed: _register,
              child: const Text('Create Account'),
            ),
            const SizedBox(height: 16),

            GestureDetector(
              onTap: () => Get.back(),
              child: RichText(
                text: TextSpan(
                  text: 'Already have an account? ',
                  style: GoogleFonts.nunito(color: BillifyColors.textSecondary),
                  children: [
                    TextSpan(
                      text: 'Login',
                      style: GoogleFonts.nunito(
                          color: BillifyColors.primary, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Forgot Password Screen ────────────────────────────────
class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Forgot Password')),
    body: Center(
      child: Text('Forgot Password Screen — Phase 2',
          style: GoogleFonts.nunito(color: BillifyColors.textSecondary)),
    ),
  );
}

// ════════════════════════════════════════════════════════════
//  TERMS & CONDITIONS SCREEN
// ════════════════════════════════════════════════════════════
class TermsConditionsScreen extends StatefulWidget {
  const TermsConditionsScreen({super.key});
  @override
  State<TermsConditionsScreen> createState() => _TermsConditionsScreenState();
}

class _TermsConditionsScreenState extends State<TermsConditionsScreen> {
  bool _scrolledToBottom = false;
  bool _agreed           = false;
  bool _loading          = false;
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.offset >= _scrollCtrl.position.maxScrollExtent - 40) {
        if (!_scrolledToBottom) setState(() => _scrolledToBottom = true);
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (!_agreed) return;
    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'termsAccepted':   true,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
      });
      Get.offAllNamed(AppRoutes.dashboard);
    } catch (e) {
      Get.snackbar('Error', 'Could not save acceptance. Please try again.',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms & Conditions')),
      body: Column(
        children: [
          // Scroll hint
          if (!_scrolledToBottom)
            Container(
              color: BillifyColors.accent.withOpacity(0.15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: BillifyColors.overdue, size: 18),
                  const SizedBox(width: 8),
                  Text('Please scroll to read all terms before proceeding.',
                      style: GoogleFonts.nunito(color: BillifyColors.overdue, fontSize: 13)),
                ],
              ),
            ),

          // Terms content
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: BillifyColors.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.description_rounded,
                              color: BillifyColors.primary, size: 40),
                        ),
                        const SizedBox(height: 12),
                        Text('Terms & Conditions',
                            style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700,
                                color: BillifyColors.primary)),
                        Text('Last updated: January 2025',
                            style: GoogleFonts.nunito(color: BillifyColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 28),
                  _TermsClause(number: '1', title: 'Lawful Use Only',
                      body: 'Billify is intended for lawful invoice generation and personal or '
                          'business expense tracking only. Any use of this application for '
                          'illegal purposes is strictly prohibited.'),
                  _TermsClause(number: '2', title: 'Data Privacy & Security',
                      body: 'All user data is stored securely using Google Firebase. Billify '
                          'does not sell, share, or rent your personal or business data to '
                          'any third parties under any circumstances.'),
                  _TermsClause(number: '3', title: 'Invoice Accuracy',
                      body: 'You are solely responsible for the accuracy and legality of any '
                          'invoice you generate using this app. Billify does not verify the '
                          'correctness of the information you input.'),
                  _TermsClause(number: '4', title: 'No Payment Processing',
                      body: 'Billify does not process, collect, or facilitate any payments. '
                          'It only generates invoices for record-keeping and tracking purposes. '
                          'Any actual payment transactions occur outside this app.'),
                  _TermsClause(number: '5', title: 'GST Disclaimer',
                      body: 'GST calculations provided in this app are for reference only '
                          'and may not reflect the latest GST rates or rules. Please consult '
                          'a qualified Chartered Accountant for official GST filings and compliance.'),
                  _TermsClause(number: '6', title: 'Limitation of Liability',
                      body: 'The developers and owners of Billify are not liable for any '
                          'financial, legal, or business disputes, losses, or damages arising '
                          'from the use of this application or the invoices generated through it.'),
                  _TermsClause(number: '7', title: 'Account Termination',
                      body: 'Misuse of this app for fraudulent invoicing, illegal billing '
                          'activities, or any violation of these terms may result in immediate '
                          'account suspension or permanent termination without prior notice.'),
                  _TermsClause(number: '8', title: 'Updates to Terms',
                      body: 'Billify reserves the right to update these Terms & Conditions '
                          'at any time without prior notice. Continued use of the application '
                          'after any changes implies your acceptance of the updated terms.'),

                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: BillifyColors.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: BillifyColors.primary.withOpacity(0.2)),
                    ),
                    child: Text(
                      'By using Billify, you confirm that you are at least 18 years old '
                          'and legally capable of entering into binding agreements.',
                      style: GoogleFonts.nunito(color: BillifyColors.primary, fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // Bottom — checkbox + button
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color:      Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Checkbox
                GestureDetector(
                  onTap: _scrolledToBottom
                      ? () => setState(() => _agreed = !_agreed)
                      : null,
                  child: Row(
                    children: [
                      Checkbox(
                        value:     _agreed,
                        onChanged: _scrolledToBottom
                            ? (val) => setState(() => _agreed = val ?? false)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'I have read and agree to the Terms & Conditions of Billify.',
                          style: GoogleFonts.nunito(
                            fontSize:   14,
                            fontWeight: FontWeight.w600,
                            color: _scrolledToBottom
                                ? BillifyColors.textPrimary
                                : BillifyColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Proceed button
                _loading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                  onPressed: (_agreed && !_loading) ? _accept : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _agreed
                        ? BillifyColors.primary
                        : BillifyColors.divider,
                  ),
                  child: const Text('Proceed to Billify'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TermsClause extends StatelessWidget {
  final String number, title, body;
  const _TermsClause({required this.number, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: BillifyColors.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(number,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600,
                        color: BillifyColors.textPrimary)),
                const SizedBox(height: 4),
                Text(body,
                    style: GoogleFonts.nunito(fontSize: 14, color: BillifyColors.textSecondary,
                        height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  PLACEHOLDER SCREENS
//  (Full implementation added in subsequent phases)
// ════════════════════════════════════════════════════════════
class _PlaceholderScreen extends StatelessWidget {
  final String   title;
  final IconData icon;
  final String   route;

  const _PlaceholderScreen({
    required this.title,
    required this.icon,
    required this.route,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      drawer: BillifyDrawer(activeRoute: route),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: BillifyColors.primary.withOpacity(0.3)),
            const SizedBox(height: 16),
            Text(title,
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600,
                    color: BillifyColors.textPrimary)),
            const SizedBox(height: 8),
            Text('Full screen — Phase 2',
                style: GoogleFonts.nunito(color: BillifyColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// Individual placeholder widgets wired to named routes
// DashboardScreen       → dashboard_screen.dart
// InvoiceListScreen     → invoice_screens.dart
// InvoiceCreateScreen   → invoice_screens.dart
// InvoiceEditScreen     → invoice_screens.dart
// InvoiceDetailScreen   → invoice_screens.dart





// ════════════════════════════════════════════════════════════
//  PROFILE SCREEN — Full implementation
// ════════════════════════════════════════════════════════════
// ════════════════════════════════════════════════════════════
//  PROFILE LOCAL STORAGE KEYS
// ════════════════════════════════════════════════════════════
class _PrefKeys {
  static const String fullName     = 'profile_fullName';
  static const String businessName = 'profile_businessName';
  static const String email        = 'profile_email';
  static const String phone        = 'profile_phone';
  static const String address      = 'profile_address';
  static const String gstNumber    = 'profile_gstNumber';
  static const String panNumber    = 'profile_panNumber';
  static const String logoBase64   = 'profile_logoBase64';
  // Bank / payment details
  static const String bankName     = 'profile_bankName';
  static const String accountName  = 'profile_accountName';
  static const String accountNumber= 'profile_accountNumber';
  static const String ifscCode     = 'profile_ifscCode';
  // Invoice defaults
  static const String termsConditions = 'profile_termsConditions';
  static const String thankYouNote    = 'profile_thankYouNote';
  static const String defaultStatus   = 'profile_defaultStatus';
  // Settings
  static const String themeMode          = 'settings_themeMode';       // system | light | dark
  static const String currencySymbol     = 'settings_currencySymbol';  // ₹ | $ | € | £ | ¥
  static const String dateFormat         = 'settings_dateFormat';      // d MMM yyyy | dd/MM/yyyy | MM/dd/yyyy
  static const String invoicePrefix      = 'settings_invoicePrefix';   // INV
  static const String orderPrefix        = 'settings_orderPrefix';     // ORD
  static const String defaultGst         = 'settings_defaultGst';      // e.g. 18
  static const String biometricLock      = 'settings_biometricLock';
  static const String autoLockMins       = 'settings_autoLockMins';    // 0=off,1,5,15
  static const String showAmountOnList   = 'settings_showAmountOnList';
  static const String compactCards       = 'settings_compactCards';
}

// ════════════════════════════════════════════════════════════
//  PROFILE SCREEN  — StreamBuilder on Firestore doc
// ════════════════════════════════════════════════════════════
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── Text controllers ──
  final _nameCtrl     = TextEditingController();
  final _businessCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _addressCtrl  = TextEditingController();
  final _gstCtrl      = TextEditingController();
  final _panCtrl      = TextEditingController();
  // Bank / payment details
  final _bankNameCtrl  = TextEditingController();
  final _accNameCtrl   = TextEditingController();
  final _accNumCtrl    = TextEditingController();
  final _ifscCtrl      = TextEditingController();
  // Invoice defaults
  final _termsCtrl     = TextEditingController();
  final _tyNoteCtrl    = TextEditingController();

  // ── State ──
  String? _logoBase64;           // base64 image stored locally
  bool    _saving       = false;
  bool    _formDirty    = false;  // true once user edits any field
  bool    _initialised  = false;  // prevent stream from overwriting user edits

  @override
  void initState() {
    super.initState();
    _loadLogoFromPrefs();
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _businessCtrl.dispose(); _emailCtrl.dispose();
    _phoneCtrl.dispose(); _addressCtrl.dispose();
    _gstCtrl.dispose(); _panCtrl.dispose();
    _bankNameCtrl.dispose(); _accNameCtrl.dispose();
    _accNumCtrl.dispose(); _ifscCtrl.dispose();
    _termsCtrl.dispose(); _tyNoteCtrl.dispose();
    super.dispose();
  }

  // ── Load logo from SharedPreferences ───────────────────
  Future<void> _loadLogoFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _logoBase64 = prefs.getString(_PrefKeys.logoBase64));
  }

  // ── Populate form once from Firestore snapshot ──────────
  void _populateForm(Map<String, dynamic> data, User authUser) {
    if (_initialised) return;
    _nameCtrl.text     = data['fullName']     as String? ?? authUser.displayName ?? '';
    _businessCtrl.text = data['businessName'] as String? ?? '';
    _emailCtrl.text    = data['email']        as String? ?? authUser.email ?? '';
    _phoneCtrl.text    = data['phone']        as String? ?? '';
    _addressCtrl.text  = data['address']      as String? ?? '';
    _gstCtrl.text      = data['gstNumber']    as String? ?? '';
    _panCtrl.text      = data['panNumber']    as String? ?? '';
    _bankNameCtrl.text = data['bankName']     as String? ?? '';
    _accNameCtrl.text  = data['accountName']  as String? ?? '';
    _accNumCtrl.text   = data['accountNumber']as String? ?? '';
    _ifscCtrl.text     = data['ifscCode']     as String? ?? '';
    _termsCtrl.text    = data['termsConditions'] as String? ??
        'Payment due within 7 days of invoice date.\nAll creative assets remain property of the creator until full payment.';
    _tyNoteCtrl.text   = data['thankYouNote'] as String? ?? 'Thank you for your business!';
    _initialised = true;
  }

  // ── Missing fields for banner ────────────────────────────
  List<String> get _missingFields {
    final m = <String>[];
    if (_nameCtrl.text.trim().isEmpty)     m.add('Full Name');
    if (_businessCtrl.text.trim().isEmpty) m.add('Business Name');
    if (_phoneCtrl.text.trim().isEmpty)    m.add('Phone');
    if (_addressCtrl.text.trim().isEmpty)  m.add('Address');
    if (_gstCtrl.text.trim().isEmpty)      m.add('GSTIN');
    if (_panCtrl.text.trim().isEmpty)      m.add('PAN');
    if (_bankNameCtrl.text.trim().isEmpty) m.add('Bank Name');
    if (_accNumCtrl.text.trim().isEmpty)   m.add('Account No.');
    if (_ifscCtrl.text.trim().isEmpty)     m.add('IFSC');
    if (_logoBase64 == null)               m.add('Logo');
    return m;
  }

  // ── Pick logo ────────────────────────────────────────────
  Future<void> _pickLogo() async {
    final source = await Get.dialog<ImageSource>(
      const BillifyImageSourceSheet(title: 'Choose Logo'),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source:       source,
      maxWidth:     512,
      maxHeight:    512,
      imageQuality: 85,
    );
    if (picked == null) return;

    final bytes  = await picked.readAsBytes();
    final b64str = base64Encode(bytes);
    final prefs  = await SharedPreferences.getInstance();
    await prefs.setString(_PrefKeys.logoBase64, b64str);
    setState(() {
      _logoBase64 = b64str;
      _formDirty  = true;
    });
  }

  Future<void> _removeLogo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_PrefKeys.logoBase64);
    setState(() { _logoBase64 = null; _formDirty = true; });
  }

  // ── Save ────────────────────────────────────────────────
  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return;

    setState(() => _saving = true);
    try {
      // 1. SharedPreferences — offline-safe, used by invoice prefill
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_PrefKeys.fullName,        _nameCtrl.text.trim());
      await prefs.setString(_PrefKeys.businessName,    _businessCtrl.text.trim());
      await prefs.setString(_PrefKeys.email,           _emailCtrl.text.trim());
      await prefs.setString(_PrefKeys.phone,           _phoneCtrl.text.trim());
      await prefs.setString(_PrefKeys.address,         _addressCtrl.text.trim());
      await prefs.setString(_PrefKeys.gstNumber,       _gstCtrl.text.trim().toUpperCase());
      await prefs.setString(_PrefKeys.panNumber,       _panCtrl.text.trim().toUpperCase());
      await prefs.setString(_PrefKeys.bankName,        _bankNameCtrl.text.trim());
      await prefs.setString(_PrefKeys.accountName,     _accNameCtrl.text.trim());
      await prefs.setString(_PrefKeys.accountNumber,   _accNumCtrl.text.trim());
      await prefs.setString(_PrefKeys.ifscCode,        _ifscCtrl.text.trim().toUpperCase());
      await prefs.setString(_PrefKeys.termsConditions, _termsCtrl.text.trim());
      await prefs.setString(_PrefKeys.thankYouNote,    _tyNoteCtrl.text.trim());

      // 2. Firestore — merge so we don't overwrite other fields
      await FirebaseFirestore.instance
          .collection('users').doc(authUser.uid)
          .set({
        'uid':              authUser.uid,
        'fullName':         _nameCtrl.text.trim(),
        'businessName':     _businessCtrl.text.trim(),
        'email':            _emailCtrl.text.trim(),
        'phone':            _phoneCtrl.text.trim(),
        'address':          _addressCtrl.text.trim(),
        'gstNumber':        _gstCtrl.text.trim().toUpperCase(),
        'panNumber':        _panCtrl.text.trim().toUpperCase(),
        'bankName':         _bankNameCtrl.text.trim(),
        'accountName':      _accNameCtrl.text.trim(),
        'accountNumber':    _accNumCtrl.text.trim(),
        'ifscCode':         _ifscCtrl.text.trim().toUpperCase(),
        'termsConditions':  _termsCtrl.text.trim(),
        'thankYouNote':     _tyNoteCtrl.text.trim(),
        'hasLocalLogo':     _logoBase64 != null,
        'updatedAt':        FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3. Firebase Auth display name
      await authUser.updateDisplayName(_nameCtrl.text.trim());

      setState(() => _formDirty = false);
      Get.snackbar('Saved ✓', 'Profile updated successfully.',
          backgroundColor: BillifyColors.paid, colorText: Colors.white,
          snackPosition: SnackPosition.TOP, duration: const Duration(seconds: 2));
    } catch (e) {
      Get.snackbar('Error', 'Save failed: $e',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── UI helpers ───────────────────────────────────────────
  Widget _sectionCard({required String title, required IconData icon,
    required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: BillifyColors.primary.withOpacity(0.06),
              blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: BillifyColors.primary.withOpacity(0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 16, color: BillifyColors.primary),
                const SizedBox(width: 8),
                Text(title,
                    style: GoogleFonts.poppins(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: BillifyColors.primary)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyTile(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: BillifyColors.primary.withOpacity(0.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.nunito(
                        fontSize: 11, color: BillifyColors.textSecondary,
                        fontWeight: FontWeight.w600)),
                Text(value.isEmpty ? '—' : value,
                    style: GoogleFonts.nunito(
                        fontSize: 15, color: BillifyColors.textPrimary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Icon(Icons.lock_outline_rounded,
              size: 14, color: BillifyColors.textSecondary),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, {
    required String label,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
    int? maxLength,
    TextCapitalization cap = TextCapitalization.none,
    String? hint,
    bool alignLabelWithHint = false,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller:            ctrl,
        keyboardType:          keyboard,
        maxLines:              maxLines,
        maxLength:             maxLength,
        textCapitalization:    cap,
        onChanged:             (_) => setState(() => _formDirty = true),
        validator:             validator,
        decoration: InputDecoration(
          labelText:           label,
          hintText:            hint,
          prefixIcon:          Icon(icon, color: BillifyColors.primary, size: 20),
          alignLabelWithHint:  alignLabelWithHint,
          counterText:         maxLength != null ? '' : null,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(authUser.uid)
          .snapshots(),

      builder: (context, snapshot) {
        // ── Populate form fields on first data event ──────
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          _populateForm(data, authUser);
        }

        // ── Compute completeness from current controller values ──
        final missing        = _missingFields;
        final profileComplete = missing.isEmpty;

        return Scaffold(
          backgroundColor: BillifyColors.background,
          appBar: AppBar(
            title: const Text('My Profile'),
            actions: [
              if (_saving)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)),
                )
              else
                TextButton.icon(
                  onPressed: _formDirty ? _saveProfile : null,
                  icon: Icon(Icons.save_rounded, color: _formDirty ? Colors.white : Colors.white38, size: 18),
                  label: Text('Save',
                      style: GoogleFonts.poppins(
                          color: _formDirty ? Colors.white : Colors.white38,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          drawer: BillifyDrawer(activeRoute: AppRoutes.profile),

          body: Column(
            children: [

              // ── Stream status bar ──────────────────────
              _StreamStatusBar(snapshot: snapshot),

              // ── Incomplete-profile banner ──────────────
              if (!profileComplete)
                _IncompleteBanner(missingFields: missing),

              // ── Body ──────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // ── Hero Avatar Card ──────────────
                        _AvatarCard(
                          nameCtrl:       _nameCtrl,
                          businessCtrl:   _businessCtrl,
                          logoBase64:     _logoBase64,
                          profileComplete: profileComplete,
                          onPickLogo:     _pickLogo,
                          onRemoveLogo:   _removeLogo,
                        ),
                        const SizedBox(height: 4),

                        // ── Account Information ───────────
                        _sectionCard(
                          title: 'Account Information',
                          icon:  Icons.lock_person_rounded,
                          children: [
                            _readOnlyTile(
                                'Email Address',
                                _emailCtrl.text,
                                Icons.email_rounded),
                          ],
                        ),

                        // ── Personal Details ──────────────
                        _sectionCard(
                          title: 'Personal Details',
                          icon:  Icons.person_rounded,
                          children: [
                            _field(_nameCtrl,
                                label: 'Full Name *',
                                icon:  Icons.person_outline_rounded,
                                validator: (v) => (v?.trim().isEmpty ?? true)
                                    ? 'Required' : null),
                            _field(_phoneCtrl,
                                label:    'Phone Number',
                                icon:     Icons.phone_rounded,
                                keyboard: TextInputType.phone),
                          ],
                        ),

                        // ── Business Details ──────────────
                        _sectionCard(
                          title: 'Business Details',
                          icon:  Icons.business_rounded,
                          children: [
                            _field(_businessCtrl,
                                label: 'Business Name *',
                                icon:  Icons.storefront_rounded,
                                validator: (v) => (v?.trim().isEmpty ?? true)
                                    ? 'Required' : null),
                            _field(_addressCtrl,
                                label:              'Business Address',
                                icon:               Icons.location_on_rounded,
                                hint:               'Street, City, State, PIN',
                                maxLines:           3,
                                alignLabelWithHint: true,
                                keyboard: TextInputType.streetAddress),
                          ],
                        ),

                        // ── Tax & Legal ───────────────────
                        _sectionCard(
                          title: 'Tax & Legal',
                          icon:  Icons.account_balance_rounded,
                          children: [
                            _field(_gstCtrl,
                                label:     'GSTIN Number',
                                icon:      Icons.receipt_rounded,
                                hint:      '22AAAAA0000A1Z5',
                                maxLength: 15,
                                cap:       TextCapitalization.characters,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return null;
                                  if (v.trim().length != 15)
                                    return 'GSTIN must be 15 characters';
                                  return null;
                                }),
                            _field(_panCtrl,
                                label:     'PAN Number',
                                icon:      Icons.credit_card_rounded,
                                hint:      'AAAAA1234A',
                                maxLength: 10,
                                cap:       TextCapitalization.characters,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return null;
                                  if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$')
                                      .hasMatch(v.trim().toUpperCase()))
                                    return 'Invalid PAN (e.g. AAAAA1234A)';
                                  return null;
                                }),
                          ],
                        ),

                        // ── Bank Details ──────────────────
                        _sectionCard(
                          title: 'Bank & Payment Details',
                          icon:  Icons.account_balance_rounded,
                          children: [
                            _field(_bankNameCtrl,
                                label:   'Bank Name',
                                icon:    Icons.account_balance_outlined,
                                hint:    'e.g. HDFC Bank'),
                            _field(_accNameCtrl,
                                label:   'Account Holder Name',
                                icon:    Icons.person_outline_rounded,
                                hint:    'Name as on bank account'),
                            _field(_accNumCtrl,
                                label:   'Account Number',
                                icon:    Icons.credit_card_rounded,
                                keyboard: TextInputType.number),
                            _field(_ifscCtrl,
                                label:   'IFSC Code',
                                icon:    Icons.code_rounded,
                                hint:    'e.g. HDFC0001234',
                                cap:     TextCapitalization.characters),
                          ],
                        ),

                        // ── Invoice Defaults ──────────────
                        _sectionCard(
                          title: 'Invoice Defaults',
                          icon:  Icons.description_rounded,
                          children: [
                            _field(_termsCtrl,
                                label:              'Default Terms & Conditions',
                                icon:               Icons.gavel_rounded,
                                maxLines:           3,
                                alignLabelWithHint: true,
                                hint:               'Payment due within 7 days…'),
                            _field(_tyNoteCtrl,
                                label: 'Default Thank You Note',
                                icon:  Icons.favorite_rounded,
                                hint:  'Thank you for your business!'),
                          ],
                        ),

                        // ── Save button ───────────────────
                        AnimatedOpacity(
                          opacity:  _formDirty ? 1.0 : 0.45,
                          duration: const Duration(milliseconds: 250),
                          child: _saving
                              ? const Center(child: CircularProgressIndicator())
                              : ElevatedButton.icon(
                            onPressed: _formDirty ? _saveProfile : null,
                            icon:  const Icon(Icons.save_rounded),
                            label: const Text('Save Profile'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════
//  STREAM STATUS BAR
// ════════════════════════════════════════════════════════════
class _StreamStatusBar extends StatelessWidget {
  final AsyncSnapshot<DocumentSnapshot> snapshot;
  const _StreamStatusBar({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return Container(
        width: double.infinity,
        color: BillifyColors.primary.withOpacity(0.08),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            const SizedBox(
              width: 12, height: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: BillifyColors.primary),
            ),
            const SizedBox(width: 10),
            Text('Loading profile…',
                style: GoogleFonts.nunito(
                    fontSize: 12, color: BillifyColors.primary)),
          ],
        ),
      );
    }
    if (snapshot.hasError) {
      return Container(
        width: double.infinity,
        color: BillifyColors.unpaid.withOpacity(0.08),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 14, color: BillifyColors.unpaid),
            const SizedBox(width: 8),
            Text('Offline — showing cached data',
                style: GoogleFonts.nunito(
                    fontSize: 12, color: BillifyColors.unpaid)),
          ],
        ),
      );
    }
    // Connected & has data — show a subtle live indicator
    return Container(
      width: double.infinity,
      color: BillifyColors.paid.withOpacity(0.06),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        children: [
          Container(
            width: 7, height: 7,
            decoration: const BoxDecoration(
                color: BillifyColors.paid, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text('Live — changes sync automatically',
              style: GoogleFonts.nunito(
                  fontSize: 11,
                  color: BillifyColors.paid,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  INCOMPLETE PROFILE BANNER
// ════════════════════════════════════════════════════════════
class _IncompleteBanner extends StatelessWidget {
  final List<String> missingFields;
  const _IncompleteBanner({required this.missingFields});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: const Color(0xFFE8F0FE),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.edit_note_rounded,
                color: BillifyColors.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${missingFields.length} field${missingFields.length > 1 ? 's' : ''} need your attention',
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: BillifyColors.primary),
                ),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 6, runSpacing: 4,
                  children: missingFields.map((f) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: BillifyColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(f,
                        style: GoogleFonts.nunito(
                            fontSize: 11,
                            color: BillifyColors.primary,
                            fontWeight: FontWeight.w600)),
                  )).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  AVATAR HERO CARD
// ════════════════════════════════════════════════════════════
class _AvatarCard extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController businessCtrl;
  final String?  logoBase64;
  final bool     profileComplete;
  final VoidCallback onPickLogo;
  final VoidCallback onRemoveLogo;

  const _AvatarCard({
    required this.nameCtrl,
    required this.businessCtrl,
    required this.logoBase64,
    required this.profileComplete,
    required this.onPickLogo,
    required this.onRemoveLogo,
  });

  @override
  Widget build(BuildContext context) {
    final name     = nameCtrl.text.trim();
    final business = businessCtrl.text.trim();
    final initials = name.isNotEmpty ? name[0].toUpperCase() : 'B';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [BillifyColors.primary, BillifyColors.primaryLight],
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: BillifyColors.primary.withOpacity(0.35),
              blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        children: [
          // Avatar
          GestureDetector(
            onTap: onPickLogo,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(
                    shape:  BoxShape.circle,
                    color:  Colors.white.withOpacity(0.15),
                    border: Border.all(color: Colors.white54, width: 2.5),
                  ),
                  child: ClipOval(
                    child: logoBase64 != null
                        ? Image.memory(base64Decode(logoBase64!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _InitialsWidget(initials))
                        : _InitialsWidget(initials),
                  ),
                ),
                Positioned(
                  bottom: 2, right: 2,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color:        Colors.white,
                      shape:        BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.15),
                            blurRadius: 6),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        size: 13, color: BillifyColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Name & business
          Text(
            name.isEmpty ? 'Your Name' : name,
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: Colors.white),
          ),
          if (business.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(business,
                style: GoogleFonts.nunito(
                    fontSize: 13, color: Colors.white70)),
          ],
          const SizedBox(height: 12),

          // Logo action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _AvatarChip(
                icon:    Icons.add_photo_alternate_rounded,
                label:   logoBase64 != null ? 'Change Logo' : 'Add Logo',
                onTap:   onPickLogo,
                primary: true,
              ),
              if (logoBase64 != null) ...[
                const SizedBox(width: 8),
                _AvatarChip(
                  icon:    Icons.delete_outline_rounded,
                  label:   'Remove',
                  onTap:   onRemoveLogo,
                  primary: false,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          // Profile complete badge
          if (profileComplete)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: BillifyColors.paid,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified_rounded,
                      size: 13, color: Colors.white),
                  const SizedBox(width: 5),
                  Text('Profile Complete',
                      style: GoogleFonts.nunito(
                          fontSize: 12, color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InitialsWidget extends StatelessWidget {
  final String initials;
  const _InitialsWidget(this.initials);
  @override
  Widget build(BuildContext context) => Center(
    child: Text(initials,
        style: GoogleFonts.poppins(
            fontSize: 36, fontWeight: FontWeight.w800,
            color: Colors.white)),
  );
}

class _AvatarChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  final bool primary;
  const _AvatarChip({required this.icon, required this.label,
    required this.onTap, required this.primary});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:        primary ? Colors.white : Colors.white24,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14,
              color: primary ? BillifyColors.primary : Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.nunito(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: primary ? BillifyColors.primary : Colors.white)),
        ],
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════════
//  LOCK SCREEN — shown when biometric/auto-lock triggers
// ════════════════════════════════════════════════════════════
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  bool _authenticating = false;
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    // Auto-trigger auth immediately on open
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);

    // Tell controller we're already inside auth — prevents onForeground()
    // from pushing another /lock while the system prompt is visible
    SettingsController.to._isNavigatingToLock = true;

    final success = await SettingsController.to.authenticate();

    // Always clear the flag after prompt closes
    SettingsController.to._isNavigatingToLock = false;

    if (!mounted) return;
    setState(() => _authenticating = false);

    if (success) {
      Get.back();
    }
    // On failure, stay on LockScreen — user taps again to retry
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (_) {
        // Silently block back — must authenticate
      },
      child: Scaffold(
        backgroundColor: BillifyColors.primary,
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App logo
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 20, offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: BillifyColors.primary, size: 44),
                ),
                const SizedBox(height: 24),
                Text('Billify is Locked',
                    style: GoogleFonts.poppins(
                        fontSize: 22, fontWeight: FontWeight.w700,
                        color: Colors.white)),
                const SizedBox(height: 8),
                Text('Authenticate to continue',
                    style: GoogleFonts.nunito(
                        fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 52),

                // Fingerprint button
                GestureDetector(
                  onTap: _authenticate,
                  child: ScaleTransition(
                    scale: _pulseAnim,
                    child: Container(
                      width: 90, height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.15),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.5), width: 2),
                      ),
                      child: _authenticating
                          ? const Center(
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                          : const Icon(Icons.fingerprint_rounded,
                          color: Colors.white, size: 50),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(_authenticating ? 'Verifying…' : 'Tap to authenticate',
                    style: GoogleFonts.nunito(
                        fontSize: 13, color: Colors.white60)),
                const SizedBox(height: 48),

                // Use PIN fallback
                TextButton.icon(
                  onPressed: _authenticate,
                  icon: const Icon(Icons.pin_rounded,
                      color: Colors.white54, size: 18),
                  label: Text('Use PIN / Password instead',
                      style: GoogleFonts.nunito(
                          fontSize: 13, color: Colors.white54,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  SETTINGS CONTROLLER  (GetX — persists + applies theme)
// ════════════════════════════════════════════════════════════
class SettingsController extends GetxController {
  // Observable settings
  final themeMode        = 'system'.obs;
  final currencySymbol   = '₹'.obs;
  final dateFormat       = 'd MMM yyyy'.obs;
  final invoicePrefix    = 'INV'.obs;
  final orderPrefix      = 'ORD'.obs;
  final defaultGst       = '18'.obs;
  final biometricLock    = false.obs;
  final autoLockMins     = 0.obs;
  final showAmountOnList = true.obs;
  final compactCards     = false.obs;

  // ── Security state ─────────────────────────────────────────
  final _auth             = LocalAuthentication();
  final isLocked          = false.obs;
  bool  _isNavigatingToLock = false; // prevents re-entrant lock pushes
  DateTime? _backgroundedAt;

  static SettingsController get to => Get.find();

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    themeMode.value        = p.getString(_PrefKeys.themeMode)        ?? 'system';
    currencySymbol.value   = p.getString(_PrefKeys.currencySymbol)   ?? '₹';
    dateFormat.value       = p.getString(_PrefKeys.dateFormat)       ?? 'd MMM yyyy';
    invoicePrefix.value    = p.getString(_PrefKeys.invoicePrefix)    ?? 'INV';
    orderPrefix.value      = p.getString(_PrefKeys.orderPrefix)      ?? 'ORD';
    defaultGst.value       = p.getString(_PrefKeys.defaultGst)       ?? '18';
    biometricLock.value    = p.getBool(_PrefKeys.biometricLock)      ?? false;
    autoLockMins.value     = p.getInt(_PrefKeys.autoLockMins)        ?? 0;
    showAmountOnList.value = p.getBool(_PrefKeys.showAmountOnList)   ?? true;
    compactCards.value     = p.getBool(_PrefKeys.compactCards)       ?? false;
    _applyTheme();

    // Treat cold launch like coming from background so the lock
    // triggers on the first SplashScreen → Dashboard transition.
    if (biometricLock.value || autoLockMins.value > 0) {
      _backgroundedAt = DateTime.now();
    }
  }

  // ── Theme ──────────────────────────────────────────────────
  void _applyTheme() {
    switch (themeMode.value) {
      case 'light':  Get.changeThemeMode(ThemeMode.light);  break;
      case 'dark':   Get.changeThemeMode(ThemeMode.dark);   break;
      default:       Get.changeThemeMode(ThemeMode.system); break;
    }
  }

  Future<void> setThemeMode(String val) async {
    themeMode.value = val;
    _applyTheme();
    final p = await SharedPreferences.getInstance();
    await p.setString(_PrefKeys.themeMode, val);
  }

  // ── Persist helpers ────────────────────────────────────────
  Future<void> _setBool(String key, RxBool obs, bool val) async {
    obs.value = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, val);
  }

  Future<void> _setString(String key, RxString obs, String val) async {
    obs.value = val;
    final p = await SharedPreferences.getInstance();
    await p.setString(key, val);
  }

  Future<void> _setInt(String key, RxInt obs, int val) async {
    obs.value = val;
    final p = await SharedPreferences.getInstance();
    await p.setInt(key, val);
  }

  // ── Security: called by app lifecycle observer ─────────────
  void onBackground() {
    _backgroundedAt = DateTime.now();
  }

  /// Called when app returns to foreground.
  /// Guards against re-entrant calls (system prompt briefly re-triggers resumed).
  Future<void> onForeground() async {
    // Already navigating to lock or already on lock screen — do nothing
    if (_isNavigatingToLock) return;
    if (Get.currentRoute == AppRoutes.lock)  return;
    if (Get.currentRoute == AppRoutes.login) return;
    if (Get.currentRoute == AppRoutes.splash) return;

    final shouldLock = _shouldTriggerLock();
    _backgroundedAt = null; // reset after reading

    if (!shouldLock) return;

    _isNavigatingToLock = true;
    isLocked.value = true;

    // Small delay so Flutter engine settles after resume
    await Future.delayed(const Duration(milliseconds: 150));

    if (isLocked.value && Get.currentRoute != AppRoutes.lock) {
      await Get.toNamed(AppRoutes.lock);
    }
    _isNavigatingToLock = false;
  }

  /// Call this after successful auth to fully reset lock state
  void clearLock() {
    isLocked.value         = false;
    _isNavigatingToLock    = false;
    _backgroundedAt        = null;
  }

  bool _shouldTriggerLock() {
    // Biometric: lock every time app comes to foreground from background
    if (biometricLock.value && _backgroundedAt != null) return true;

    // Auto-lock: only if backgrounded longer than threshold
    if (autoLockMins.value > 0 && _backgroundedAt != null) {
      final elapsed = DateTime.now().difference(_backgroundedAt!);
      if (elapsed.inMinutes >= autoLockMins.value) return true;
    }
    return false;
  }

  Future<bool> authenticate() async {
    try {
      final isDeviceSupported = await _auth.isDeviceSupported();
      if (!isDeviceSupported) {
        await _setBool(_PrefKeys.biometricLock, biometricLock, false);
        await _setInt(_PrefKeys.autoLockMins, autoLockMins, 0);
        clearLock();
        Get.snackbar(
          'Device Not Supported',
          'This device does not support authentication. Security lock disabled.',
          backgroundColor: BillifyColors.overdue,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 4),
        );
        return true;
      }

      final didAuth = await _auth.authenticate(
        localizedReason: 'Authenticate to open Billify',
        options: const AuthenticationOptions(
          stickyAuth:           true,
          biometricOnly:        false,
          sensitiveTransaction: false,
        ),
      );

      if (didAuth) {
        clearLock();
        return true;
      }
      return false;

    } on PlatformException catch (e) {
      final code = e.code;
      // Android codes: NotAvailable, PasscodeNotSet, NotEnrolled
      // iOS codes:     LAErrorPasscodeNotSet, LAErrorBiometryNotAvailable,
      //                LAErrorBiometryNotEnrolled
      if (code == 'NotAvailable'              ||
          code == 'PasscodeNotSet'            ||
          code == 'NotEnrolled'               ||
          code == 'LAErrorPasscodeNotSet'     ||
          code == 'LAErrorBiometryNotAvailable' ||
          code == 'LAErrorBiometryNotEnrolled') {
        await _setBool(_PrefKeys.biometricLock, biometricLock, false);
        await _setInt(_PrefKeys.autoLockMins, autoLockMins, 0);
        clearLock();
        Get.snackbar(
          'Authentication Unavailable',
          'No lock screen credentials found on this device. Security lock disabled.',
          backgroundColor: BillifyColors.overdue,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
          duration: const Duration(seconds: 4),
        );
        return true;
      }
      // Other platform error — stay locked
      Get.snackbar(
        'Authentication Error',
        'Could not authenticate: ${e.message ?? e.code}',
        backgroundColor: BillifyColors.unpaid,
        colorText: Colors.white,
        snackPosition: SnackPosition.TOP,
      );
      return false;
    } catch (_) {
      // Unknown error — stay locked
      return false;
    }
  }
}

// ════════════════════════════════════════════════════════════
//  APP SETTINGS — static accessors used across all screens
// ════════════════════════════════════════════════════════════
class AppSettings {
  /// Active currency symbol (₹ / $ / € / £ / ¥)
  static String get currency {
    if (!Get.isRegistered<SettingsController>()) return '₹';
    return SettingsController.to.currencySymbol.value;
  }

  /// Active date format string (e.g. 'd MMM yyyy')
  static String get dateFormat {
    if (!Get.isRegistered<SettingsController>()) return 'd MMM yyyy';
    return SettingsController.to.dateFormat.value;
  }

  /// Invoice number prefix (e.g. 'INV')
  static String get invoicePrefix {
    if (!Get.isRegistered<SettingsController>()) return 'INV';
    return SettingsController.to.invoicePrefix.value;
  }

  /// Order ID prefix (e.g. 'ORD')
  static String get orderPrefix {
    if (!Get.isRegistered<SettingsController>()) return 'ORD';
    return SettingsController.to.orderPrefix.value;
  }

  /// Default GST % as double
  static double get defaultGst {
    if (!Get.isRegistered<SettingsController>()) return 18.0;
    return double.tryParse(SettingsController.to.defaultGst.value) ?? 18.0;
  }

  /// Whether to show amounts on invoice / expense list cards
  static bool get showAmountOnList {
    if (!Get.isRegistered<SettingsController>()) return true;
    return SettingsController.to.showAmountOnList.value;
  }

  /// Whether to use compact card layout
  static bool get compactCards {
    if (!Get.isRegistered<SettingsController>()) return false;
    return SettingsController.to.compactCards.value;
  }

  /// Currency formatter with correct symbol
  static NumberFormat currencyFmt({int decimals = 0}) =>
      NumberFormat.currency(locale: 'en_IN', symbol: currency, decimalDigits: decimals);

  /// Format a DateTime using the user's chosen date format
  static String formatDate(DateTime d) => DateFormat(dateFormat).format(d);
}

// ════════════════════════════════════════════════════════════
//  SETTINGS SCREEN
// ════════════════════════════════════════════════════════════
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsController _ctrl;

  @override
  void initState() {
    super.initState();
    // Register controller if not already registered
    if (!Get.isRegistered<SettingsController>()) {
      Get.put(SettingsController());
    }
    _ctrl = SettingsController.to;
  }

  // ── Helpers ────────────────────────────────────────────────
  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 20, 0, 8),
    child: Row(
      children: [
        Container(width: 3, height: 16,
            decoration: BoxDecoration(
                color: BillifyColors.primary,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: BillifyColors.primary)),
      ],
    ),
  );

  Widget _card({required List<Widget> children}) => Container(
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(color: BillifyColors.primary.withOpacity(0.06),
            blurRadius: 10, offset: const Offset(0, 3)),
      ],
    ),
    child: Column(children: children),
  );

  Widget _tile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool isLast = false,
  }) {
    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          title: Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w500,
                  color: BillifyColors.textPrimary)),
          subtitle: subtitle != null
              ? Text(subtitle,
              style: GoogleFonts.nunito(
                  fontSize: 12, color: BillifyColors.textSecondary))
              : null,
          trailing: trailing ?? (onTap != null
              ? const Icon(Icons.chevron_right_rounded,
              color: BillifyColors.textSecondary, size: 18)
              : null),
          onTap: onTap,
        ),
        if (!isLast)
          Divider(height: 1, indent: 58,
              color: BillifyColors.divider.withOpacity(0.7)),
      ],
    );
  }

  Widget _switchTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isLast = false,
  }) =>
      _tile(
        icon: icon, iconColor: iconColor,
        title: title, subtitle: subtitle,
        isLast: isLast,
        trailing: Transform.scale(
          scale: 0.85,
          child: Switch(
            value: value, onChanged: onChanged,
            activeColor: BillifyColors.primary,
          ),
        ),
      );

  void _showOptions<T>({
    required String title,
    required List<T> options,
    required T current,
    required String Function(T) label,
    required ValueChanged<T> onSelect,
  }) {
    Get.bottomSheet(
      BillifyOptionsSheet<T>(
        title:    title,
        options:  options,
        current:  current,
        label:    label,
        onSelect: onSelect,
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _showInputDialog({
    required String title,
    required String hint,
    required String current,
    required ValueChanged<String> onSave,
    TextInputType keyboard = TextInputType.text,
  }) async {
    final val = await Get.dialog<String>(
      BillifyInputDialog(
        title:        title,
        hint:         hint,
        initialValue: current,
        keyboard:     keyboard,
      ),
    );
    if (val != null && val.isNotEmpty) onSave(val);
  }

  Future<void> _clearAllData() async {
    final confirm = await Get.dialog<bool>(
      BillifyDialog(
        icon:         Icons.cleaning_services_rounded,
        iconColor:    BillifyColors.overdue,
        title:        'Clear App Data?',
        body:         'This removes all locally cached profile data and settings. '
            'Your invoices and expenses in the cloud are NOT affected.',
        confirmLabel: 'Clear Now',
        confirmColor: BillifyColors.overdue,
        onConfirm:    () => Get.back(result: true),
      ),
    );
    if (confirm != true) return;
    final p = await SharedPreferences.getInstance();
    await p.clear();
    Get.snackbar('Cleared', 'Local app data cleared successfully',
        backgroundColor: BillifyColors.paid, colorText: Colors.white,
        snackPosition: SnackPosition.TOP);
  }

  Future<void> _deleteAccount() async {
    final confirm = await Get.dialog<bool>(
      BillifyDialog(
        icon:         Icons.delete_forever_rounded,
        iconColor:    BillifyColors.unpaid,
        title:        'Delete Account?',
        body:         'This permanently deletes your account and ALL data '
            '(invoices, expenses, profile). This cannot be undone.',
        confirmLabel: 'Delete Forever',
        confirmColor: BillifyColors.unpaid,
        onConfirm:    () => Get.back(result: true),
      ),
    );
    if (confirm != true) return;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        // Delete Firestore user document
        await FirebaseFirestore.instance.collection('users').doc(uid).delete();
      }
      await FirebaseAuth.instance.currentUser?.delete();
      final p = await SharedPreferences.getInstance();
      await p.clear();
      Get.offAllNamed(AppRoutes.login);
    } catch (e) {
      Get.snackbar('Error',
          'Could not delete account. Please re-login and try again.',
          backgroundColor: BillifyColors.unpaid, colorText: Colors.white);
    }
  }

  String _themeModeLabel(String v) {
    switch (v) {
      case 'light': return 'Light';
      case 'dark':  return 'Dark';
      default:      return 'System Default';
    }
  }

  String _lockLabel(int v) {
    switch (v) {
      case 1:  return '1 minute';
      case 5:  return '5 minutes';
      case 15: return '15 minutes';
      default: return 'Off';
    }
  }

  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BillifyColors.background,
      appBar: AppBar(title: const Text('Settings')),
      drawer: const BillifyDrawer(activeRoute: AppRoutes.settings),
      body: Obx(() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [

          // ── APPEARANCE ─────────────────────────────────────
          _section('APPEARANCE'),
          _card(children: [
            _tile(
              icon: Icons.brightness_6_rounded,
              iconColor: const Color(0xFF7C4DFF),
              title: 'Theme',
              subtitle: _themeModeLabel(_ctrl.themeMode.value),
              onTap: () => _showOptions<String>(
                title: 'Choose Theme',
                options: ['system', 'light', 'dark'],
                current: _ctrl.themeMode.value,
                label: _themeModeLabel,
                onSelect: (v) => _ctrl.setThemeMode(v),
              ),
            ),
            _switchTile(
              icon: Icons.view_agenda_rounded,
              iconColor: const Color(0xFF00BCD4),
              title: 'Compact Cards',
              subtitle: _ctrl.compactCards.value
                  ? 'Active — reduced card padding'
                  : 'Standard card size',
              value: _ctrl.compactCards.value,
              onChanged: (v) async {
                await _ctrl._setBool(_PrefKeys.compactCards, _ctrl.compactCards, v);
                Get.snackbar(
                  v ? 'Compact Cards On' : 'Compact Cards Off',
                  'Invoice & expense cards updated.',
                  backgroundColor: const Color(0xFF00BCD4),
                  colorText: Colors.white,
                  duration: const Duration(seconds: 2),
                  snackPosition: SnackPosition.TOP,
                );
              },
            ),
            _switchTile(
              icon: Icons.attach_money_rounded,
              iconColor: BillifyColors.paid,
              title: 'Show Amounts in List',
              subtitle: _ctrl.showAmountOnList.value
                  ? 'Amounts visible on list cards'
                  : 'Amounts hidden on list cards',
              value: _ctrl.showAmountOnList.value,
              onChanged: (v) async {
                await _ctrl._setBool(
                    _PrefKeys.showAmountOnList, _ctrl.showAmountOnList, v);
                Get.snackbar(
                  v ? 'Amounts Shown' : 'Amounts Hidden',
                  'Invoice list cards updated.',
                  backgroundColor: BillifyColors.paid,
                  colorText: Colors.white,
                  duration: const Duration(seconds: 2),
                  snackPosition: SnackPosition.TOP,
                );
              },
              isLast: true,
            ),
          ]),

          // ── INVOICE DEFAULTS ───────────────────────────────
          _section('INVOICE DEFAULTS'),
          _card(children: [
            _tile(
              icon: Icons.tag_rounded,
              iconColor: BillifyColors.primary,
              title: 'Invoice Number Prefix',
              subtitle: _ctrl.invoicePrefix.value,
              onTap: () => _showInputDialog(
                title: 'Invoice Prefix',
                hint: 'e.g. INV, BILL, TAX',
                current: _ctrl.invoicePrefix.value,
                onSave: (v) => _ctrl._setString(
                    _PrefKeys.invoicePrefix, _ctrl.invoicePrefix, v.toUpperCase()),
              ),
            ),
            _tile(
              icon: Icons.confirmation_number_rounded,
              iconColor: BillifyColors.primaryLight,
              title: 'Order ID Prefix',
              subtitle: _ctrl.orderPrefix.value,
              onTap: () => _showInputDialog(
                title: 'Order ID Prefix',
                hint: 'e.g. ORD, JOB, PO',
                current: _ctrl.orderPrefix.value,
                onSave: (v) => _ctrl._setString(
                    _PrefKeys.orderPrefix, _ctrl.orderPrefix, v.toUpperCase()),
              ),
            ),
            _tile(
              icon: Icons.currency_rupee_rounded,
              iconColor: const Color(0xFFFF6F00),
              title: 'Currency Symbol',
              subtitle: _ctrl.currencySymbol.value,
              onTap: () => _showOptions<String>(
                title: 'Currency Symbol',
                options: ['₹', '\$', '€', '£', '¥'],
                current: _ctrl.currencySymbol.value,
                label: (v) {
                  const names = {
                    '₹': '₹  Indian Rupee',
                    '\$': '\$  US Dollar',
                    '€': '€  Euro',
                    '£': '£  British Pound',
                    '¥': '¥  Japanese Yen',
                  };
                  return names[v] ?? v;
                },
                onSelect: (v) => _ctrl._setString(
                    _PrefKeys.currencySymbol, _ctrl.currencySymbol, v),
              ),
            ),
            _tile(
              icon: Icons.calendar_today_rounded,
              iconColor: const Color(0xFF00897B),
              title: 'Date Format',
              subtitle: _ctrl.dateFormat.value,
              onTap: () => _showOptions<String>(
                title: 'Date Format',
                options: ['d MMM yyyy', 'dd/MM/yyyy', 'MM/dd/yyyy', 'yyyy-MM-dd'],
                current: _ctrl.dateFormat.value,
                label: (v) => v,
                onSelect: (v) => _ctrl._setString(
                    _PrefKeys.dateFormat, _ctrl.dateFormat, v),
              ),
            ),
            _tile(
              icon: Icons.percent_rounded,
              iconColor: const Color(0xFFE53935),
              title: 'Default GST Rate',
              subtitle: '${_ctrl.defaultGst.value}%',
              isLast: true,
              onTap: () => _showInputDialog(
                title: 'Default GST %',
                hint: 'e.g. 18',
                current: _ctrl.defaultGst.value,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
                onSave: (v) => _ctrl._setString(
                    _PrefKeys.defaultGst, _ctrl.defaultGst, v),
              ),
            ),
          ]),

          // ── SECURITY ───────────────────────────────────────
          _section('SECURITY'),
          _card(children: [
            _switchTile(
              icon: Icons.fingerprint_rounded,
              iconColor: const Color(0xFF5C6BC0),
              title: 'Biometric Lock',
              subtitle: _ctrl.biometricLock.value
                  ? 'Enabled — app locked on next resume'
                  : 'Require fingerprint / face to open app',
              value: _ctrl.biometricLock.value,
              onChanged: (v) async {
                await _ctrl._setBool(_PrefKeys.biometricLock, _ctrl.biometricLock, v);
                if (v) {
                  Get.snackbar(
                    'Biometric Lock Enabled',
                    'The app will prompt for biometric auth on next resume. '
                        'Ensure biometrics are enrolled in your device settings.',
                    backgroundColor: const Color(0xFF5C6BC0),
                    colorText: Colors.white,
                    duration: const Duration(seconds: 4),
                    snackPosition: SnackPosition.TOP,
                    icon: const Icon(Icons.fingerprint_rounded,
                        color: Colors.white),
                  );
                }
              },
            ),
            _tile(
              icon: Icons.lock_clock_rounded,
              iconColor: const Color(0xFF8D6E63),
              title: 'Auto-Lock',
              subtitle: _ctrl.autoLockMins.value == 0
                  ? 'Disabled'
                  : 'Lock after ${_lockLabel(_ctrl.autoLockMins.value)} of inactivity',
              isLast: true,
              onTap: () => _showOptions<int>(
                title: 'Auto-Lock After',
                options: [0, 1, 5, 15],
                current: _ctrl.autoLockMins.value,
                label: _lockLabel,
                onSelect: (v) async {
                  await _ctrl._setInt(_PrefKeys.autoLockMins, _ctrl.autoLockMins, v);
                  if (v > 0) {
                    Get.snackbar(
                      'Auto-Lock Set',
                      'App will lock after ${_lockLabel(v)} of inactivity.',
                      backgroundColor: const Color(0xFF8D6E63),
                      colorText: Colors.white,
                      snackPosition: SnackPosition.TOP,
                    );
                  }
                },
              ),
            ),
          ]),

          // ── ACCOUNT ────────────────────────────────────────
          _section('ACCOUNT'),
          _card(children: [
            _tile(
              icon: Icons.person_rounded,
              iconColor: BillifyColors.primary,
              title: 'Edit Profile',
              subtitle: 'Name, business, tax & bank details',
              onTap: () {
                Get.back();
                Get.toNamed(AppRoutes.profile);
              },
            ),
            _tile(
              icon: Icons.lock_reset_rounded,
              iconColor: const Color(0xFFFB8C00),
              title: 'Change Password',
              subtitle: 'Send a reset link to your email',
              onTap: () async {
                final user = FirebaseAuth.instance.currentUser;
                if (user?.email == null) return;
                try {
                  await FirebaseAuth.instance
                      .sendPasswordResetEmail(email: user!.email!);
                  Get.snackbar('Email Sent',
                      'Password reset link sent to ${user.email}',
                      backgroundColor: BillifyColors.paid,
                      colorText: Colors.white,
                      snackPosition: SnackPosition.TOP);
                } catch (e) {
                  Get.snackbar('Error', 'Could not send reset email',
                      backgroundColor: BillifyColors.unpaid,
                      colorText: Colors.white);
                }
              },
            ),
            _tile(
              icon: Icons.verified_user_rounded,
              iconColor: BillifyColors.paid,
              title: 'Email Verification',
              subtitle: FirebaseAuth.instance.currentUser?.emailVerified == true
                  ? 'Your email is verified ✓'
                  : 'Tap to send verification email',
              isLast: true,
              onTap: FirebaseAuth.instance.currentUser?.emailVerified == true
                  ? null
                  : () async {
                try {
                  await FirebaseAuth.instance.currentUser
                      ?.sendEmailVerification();
                  Get.snackbar('Verification Sent',
                      'Check your inbox for the verification link',
                      backgroundColor: BillifyColors.paid,
                      colorText: Colors.white,
                      snackPosition: SnackPosition.TOP);
                } catch (_) {
                  Get.snackbar('Error', 'Could not send verification email',
                      backgroundColor: BillifyColors.unpaid,
                      colorText: Colors.white);
                }
              },
            ),
          ]),

          // ── DATA & STORAGE ─────────────────────────────────
          _section('DATA & STORAGE'),
          _card(children: [
            _tile(
              icon: Icons.cleaning_services_rounded,
              iconColor: const Color(0xFF00ACC1),
              title: 'Clear Local Cache',
              subtitle: 'Remove cached profile & settings data',
              onTap: _clearAllData,
            ),
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseAuth.instance.currentUser != null
                  ? FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .snapshots()
                  : const Stream.empty(),
              builder: (context, snap) {
                final isConnected = snap.connectionState == ConnectionState.active
                    && !snap.hasError;
                final isFromCache = snap.data?.metadata.isFromCache ?? false;
                final statusLabel = snap.connectionState == ConnectionState.waiting
                    ? 'Connecting…'
                    : snap.hasError
                    ? 'Offline'
                    : isFromCache
                    ? 'Cached'
                    : 'Live';
                final statusColor = snap.hasError || isFromCache
                    ? BillifyColors.overdue
                    : isConnected
                    ? BillifyColors.paid
                    : BillifyColors.textSecondary;
                return _tile(
                  icon: snap.hasError
                      ? Icons.cloud_off_rounded
                      : Icons.cloud_done_rounded,
                  iconColor: statusColor,
                  title: 'Cloud Sync',
                  subtitle: isConnected && !isFromCache
                      ? 'All data syncing in real-time'
                      : snap.hasError
                      ? 'Check your internet connection'
                      : 'Last synced data shown',
                  isLast: true,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(statusLabel,
                        style: GoogleFonts.nunito(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: statusColor)),
                  ),
                );
              },
            ),
          ]),

          // ── ABOUT ──────────────────────────────────────────
          _section('ABOUT'),
          _card(children: [
            _tile(
              icon: Icons.info_outline_rounded,
              iconColor: BillifyColors.primary,
              title: 'App Version',
              subtitle: 'Billify v1.0.0',
              isLast: false,
              trailing: const SizedBox.shrink(),
            ),
            _tile(
              icon: Icons.description_rounded,
              iconColor: BillifyColors.textSecondary,
              title: 'Terms & Conditions',
              onTap: () => Get.toNamed(AppRoutes.termsConditions),
            ),
            _tile(
              icon: Icons.privacy_tip_rounded,
              iconColor: const Color(0xFF5C6BC0),
              title: 'Privacy Policy',
              subtitle: 'Your data is stored securely on Firebase',
              isLast: true,
              onTap: () => Get.snackbar(
                'Privacy Policy',
                'Billify stores your data securely using Google Firebase. We never sell or share your data.',
                backgroundColor: BillifyColors.primary,
                colorText: Colors.white,
                duration: const Duration(seconds: 5),
                snackPosition: SnackPosition.BOTTOM,
              ),
            ),
          ]),

          // ── DANGER ZONE ────────────────────────────────────
          _section('DANGER ZONE'),
          _card(children: [
            _tile(
              icon: Icons.delete_forever_rounded,
              iconColor: BillifyColors.unpaid,
              title: 'Delete Account',
              subtitle: 'Permanently remove your account & all data',
              isLast: true,
              onTap: _deleteAccount,
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: BillifyColors.unpaid, size: 18),
            ),
          ]),

          const SizedBox(height: 20),

          // Footer
          Center(
            child: Text('Billify · Smart Invoicing. Simple Finance.',
                style: GoogleFonts.nunito(
                    fontSize: 11,
                    color: BillifyColors.textSecondary.withOpacity(0.6))),
          ),
        ],
      )),
    );
  }
}