import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'firebase_options.dart';
import 'main_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // google_sign_in 7.x must be initialized exactly once before authenticate().
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    await GoogleSignIn.instance.initialize();
  }

  runApp(const TaskProofApp());
}

class TaskProofApp extends StatelessWidget {
  const TaskProofApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TaskProof',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Arial',
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.taskRed,
          brightness: Brightness.light,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

class AppColors {
  static const taskRed = Color(0xFFFF111C);
  static const darkText = Color(0xFF181A20);
  static const secondaryText = Color(0xFF858995);
  static const borderColor = Color(0xFFE5E7EB);
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const MainPage();
        }

        return const LoginPage();
      },
    );
  }
}

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  static Future<void> createAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await credential.user?.updateDisplayName(name.trim());
    await credential.user?.sendEmailVerification();
  }

  static Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  static Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await _auth.signInWithPopup(GoogleAuthProvider());
      return;
    }

    final supported = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    if (!supported) {
      throw UnsupportedError(
        'Google sign-in is not configured for this desktop platform. Use web, Android, iOS, or macOS.',
      );
    }

    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );

    await _auth.signInWithCredential(credential);
  }

  static Future<void> signInWithApple() async {
    final provider = AppleAuthProvider();

    if (kIsWeb) {
      await _auth.signInWithPopup(provider);
    } else {
      await _auth.signInWithProvider(provider);
    }
  }

  static Future<void> signOut() async {
    await _auth.signOut();
  }

  static String readableError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'That email address is not valid.';
        case 'user-disabled':
          return 'This account has been disabled.';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'Incorrect email address or password.';
        case 'email-already-in-use':
          return 'An account already exists with this email address.';
        case 'weak-password':
          return 'Use a stronger password with at least 6 characters.';
        case 'operation-not-allowed':
          return 'This sign-in method has not been enabled in Firebase.';
        case 'too-many-requests':
          return 'Too many attempts. Please wait and try again.';
        case 'network-request-failed':
          return 'No internet connection. Check your connection and try again.';
        case 'popup-closed-by-user':
        case 'canceled-popup-request':
          return 'Sign-in was cancelled.';
        case 'account-exists-with-different-credential':
          return 'An account already exists with this email using another sign-in method.';
        default:
          return error.message ?? 'Authentication failed. Please try again.';
      }
    }

    if (error is UnsupportedError) {
      return error.message ?? 'This sign-in method is not supported here.';
    }

    return 'Something went wrong. Please try again.';
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool obscurePassword = true;
  bool loading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _runAuth(Future<void> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() => loading = true);

    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      _showMessage(AuthService.readableError(error), isError: true);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> logIn() async {
    if (!_formKey.currentState!.validate()) return;

    await _runAuth(
      () => AuthService.signInWithEmail(
        email: emailController.text,
        password: passwordController.text,
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red.shade700 : null,
        ),
      );
  }

  Future<void> _showForgotPasswordDialog() async {
    final controller = TextEditingController(text: emailController.text.trim());

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool sending = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Reset password'),
              content: TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'you@example.com',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: sending ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: sending
                      ? null
                      : () async {
                          final email = controller.text.trim();
                          if (!isValidEmail(email)) {
                            _showMessage('Enter a valid email address.', isError: true);
                            return;
                          }

                          setDialogState(() => sending = true);
                          try {
                            await AuthService.sendPasswordReset(email);
                            if (!mounted) return;
                            // ignore: use_build_context_synchronously
                            Navigator.pop(dialogContext);
                            _showMessage('Password reset email sent.');
                          } catch (error) {
                            _showMessage(
                              AuthService.readableError(error),
                              isError: true,
                            );
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() => sending = false);
                            }
                          }
                        },
                  child: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send'),
                ),
              ],
            );
          },
        );
      },
    );

    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;
            final isVerySmallPhone = screenWidth < 350 || screenHeight < 650;
            final isSmallPhone = screenWidth < 390 || screenHeight < 750;
            final horizontalPadding = screenWidth < 360
                ? 18.0
                : screenWidth < 430
                    ? 22.0
                    : 28.0;
            final logoSize = isVerySmallPhone
                ? 94.0
                : isSmallPhone
                    ? 108.0
                    : 122.0;
            final inputHeight = isVerySmallPhone
                ? 56.0
                : isSmallPhone
                    ? 60.0
                    : 64.0;
            final buttonHeight = isVerySmallPhone
                ? 54.0
                : isSmallPhone
                    ? 58.0
                    : 60.0;

            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                isVerySmallPhone ? 16 : 24,
                horizontalPadding,
                24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TaskProofHeader(
                          logoSize: logoSize,
                          compact: isVerySmallPhone,
                        ),
                        SizedBox(height: isVerySmallPhone ? 20 : 30),
                        Text(
                          'Welcome back',
                          style: TextStyle(
                            color: AppColors.darkText,
                            fontSize: isVerySmallPhone ? 24 : 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Log in to continue',
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: isVerySmallPhone ? 14.5 : 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: isVerySmallPhone ? 22 : 27),
                        TaskProofInput(
                          controller: emailController,
                          hintText: 'Email address',
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          prefixIcon: Icons.mail_outline_rounded,
                          height: inputHeight,
                          compact: isVerySmallPhone,
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (email.isEmpty) return 'Enter your email address.';
                            if (!isValidEmail(email)) return 'Enter a valid email address.';
                            return null;
                          },
                        ),
                        SizedBox(height: isVerySmallPhone ? 12 : 15),
                        TaskProofInput(
                          controller: passwordController,
                          hintText: 'Password',
                          obscureText: obscurePassword,
                          textInputAction: TextInputAction.done,
                          prefixIcon: Icons.lock_outline_rounded,
                          onSubmitted: (_) => logIn(),
                          height: inputHeight,
                          compact: isVerySmallPhone,
                          validator: (value) {
                            if ((value ?? '').isEmpty) return 'Enter your password.';
                            return null;
                          },
                          suffix: IconButton(
                            onPressed: () => setState(
                              () => obscurePassword = !obscurePassword,
                            ),
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColors.darkText,
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: loading ? null : _showForgotPasswordDialog,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                        SizedBox(height: isVerySmallPhone ? 10 : 13),
                        PrimaryButton(
                          label: 'Log in',
                          loading: loading,
                          height: buttonHeight,
                          onPressed: logIn,
                        ),
                        SizedBox(height: isVerySmallPhone ? 20 : 24),
                        OrDivider(compact: isVerySmallPhone),
                        SizedBox(height: isVerySmallPhone ? 20 : 24),
                        SocialLoginButton(
                          label: 'Continue with Google',
                          height: buttonHeight,
                          compact: isVerySmallPhone,
                          icon: Image.asset(
                            'assets/images/icons/google-logo.webp',
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                          ),
                          onPressed: loading
                              ? null
                              : () => _runAuth(AuthService.signInWithGoogle),
                        ),
                        SizedBox(height: isVerySmallPhone ? 11 : 14),
                        SocialLoginButton(
                          label: 'Continue with Apple',
                          height: buttonHeight,
                          compact: isVerySmallPhone,
                          icon: const Icon(Icons.apple, size: 32, color: Colors.black),
                          onPressed: loading
                              ? null
                              : () => _runAuth(AuthService.signInWithApple),
                        ),
                        SizedBox(height: isVerySmallPhone ? 22 : 27),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Don’t have an account?',
                              style: TextStyle(
                                color: AppColors.secondaryText,
                                fontSize: isVerySmallPhone ? 13.5 : 15,
                              ),
                            ),
                            TextButton(
                              onPressed: loading
                                  ? null
                                  : () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => const SignUpPage(),
                                        ),
                                      );
                                    },
                              child: const Text('Sign up'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _formKey = GlobalKey<FormState>();
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool loading = false;

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> createAccount() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() => loading = true);

    try {
      await AuthService.createAccount(
        name: nameController.text,
        email: emailController.text,
        password: passwordController.text,
      );

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created. A verification email was sent.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AuthService.readableError(error)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Text('Create account'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const _TaskProofHeader(logoSize: 92, compact: false),
                    const SizedBox(height: 28),
                    TaskProofInput(
                      controller: nameController,
                      hintText: 'Full name',
                      prefixIcon: Icons.person_outline_rounded,
                      height: 60,
                      compact: false,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if ((value?.trim().length ?? 0) < 2) {
                          return 'Enter your full name.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TaskProofInput(
                      controller: emailController,
                      hintText: 'Email address',
                      prefixIcon: Icons.mail_outline_rounded,
                      height: 60,
                      compact: false,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Enter your email address.';
                        if (!isValidEmail(email)) return 'Enter a valid email address.';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TaskProofInput(
                      controller: passwordController,
                      hintText: 'Password',
                      prefixIcon: Icons.lock_outline_rounded,
                      height: 60,
                      compact: false,
                      obscureText: obscurePassword,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if ((value ?? '').length < 6) {
                          return 'Use at least 6 characters.';
                        }
                        return null;
                      },
                      suffix: IconButton(
                        onPressed: () => setState(
                          () => obscurePassword = !obscurePassword,
                        ),
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TaskProofInput(
                      controller: confirmPasswordController,
                      hintText: 'Confirm password',
                      prefixIcon: Icons.lock_reset_rounded,
                      height: 60,
                      compact: false,
                      obscureText: obscureConfirmPassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => createAccount(),
                      validator: (value) {
                        if (value != passwordController.text) {
                          return 'The passwords do not match.';
                        }
                        return null;
                      },
                      suffix: IconButton(
                        onPressed: () => setState(
                          () => obscureConfirmPassword = !obscureConfirmPassword,
                        ),
                        icon: Icon(
                          obscureConfirmPassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: 'Create account',
                      loading: loading,
                      height: 60,
                      onPressed: createAccount,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: loading ? null : () => Navigator.pop(context),
                      child: const Text('Already have an account? Log in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}



class _TaskProofHeader extends StatelessWidget {
  const _TaskProofHeader({required this.logoSize, required this.compact});

  final double logoSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(logoSize * 0.23),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 22,
                offset: const Offset(0, 9),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(logoSize * 0.23),
            child: Image.asset(
              'assets/images/taskproof_logo.png',
              fit: BoxFit.cover,
            ),
          ),
        ),
        SizedBox(height: compact ? 13 : 17),
        RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: compact ? 29 : 35,
              height: 1,
              letterSpacing: 0.2,
            ),
            children: const [
              TextSpan(
                text: 'TASK',
                style: TextStyle(
                  color: AppColors.darkText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextSpan(
                text: 'PROOF',
                style: TextStyle(
                  color: AppColors.taskRed,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Stay in frame. Stay focused. Get it done.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.secondaryText,
            fontSize: compact ? 13.5 : 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class TaskProofInput extends StatelessWidget {
  const TaskProofInput({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    required this.height,
    required this.compact,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.suffix,
    this.onSubmitted,
    this.validator,
    super.key,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final double height;
  final bool compact;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      obscureText: obscureText,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      cursorColor: AppColors.taskRed,
      style: TextStyle(
        color: AppColors.darkText,
        fontSize: compact ? 15.5 : 17,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: Icon(prefixIcon, color: AppColors.darkText),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white,
        contentPadding: EdgeInsets.symmetric(vertical: compact ? 16 : 19),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFE1E3E7), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: AppColors.taskRed, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.red, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Colors.red, width: 1.4),
        ),
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.loading,
    required this.height,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool loading;
  final double height;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF1722), Color(0xFFED000C)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.taskRed.withValues(alpha: 0.22),
              blurRadius: 13,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: loading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            disabledBackgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            disabledForegroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

class SocialLoginButton extends StatelessWidget {
  const SocialLoginButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    required this.height,
    required this.compact,
    super.key,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final double height;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.darkText,
          side: const BorderSide(color: AppColors.borderColor, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: EdgeInsets.symmetric(horizontal: compact ? 18 : 24),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: compact ? 34 : 40,
                child: Center(child: icon),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 15.5 : 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OrDivider extends StatelessWidget {
  const OrDivider({required this.compact, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0xFFE0E2E6))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 20),
          child: Text(
            'or',
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: compact ? 14 : 15.5,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Color(0xFFE0E2E6))),
      ],
    );
  }
}

bool isValidEmail(String value) {
  return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
}