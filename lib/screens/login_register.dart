import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../services/api_service.dart';

class LoginRegisterScreen extends StatefulWidget {
  const LoginRegisterScreen({super.key});

  @override
  State<LoginRegisterScreen> createState() => _LoginRegisterScreenState();
}

class _LoginRegisterScreenState extends State<LoginRegisterScreen> {
  final PageController pageController = PageController();
  int activeTab = 0;

  // Login Controllers
  final TextEditingController loginUser = TextEditingController();
  final TextEditingController loginPass = TextEditingController();

  // Register Controllers
  final TextEditingController regEmail = TextEditingController();
  final TextEditingController regUser = TextEditingController();
  final TextEditingController regConsumer = TextEditingController();
  final TextEditingController regPass = TextEditingController();

  bool rememberMe = false;
  bool isLoading = false;

  @override
  void dispose() {
    pageController.dispose();
    loginUser.dispose();
    loginPass.dispose();
    regEmail.dispose();
    regUser.dispose();
    regConsumer.dispose();
    regPass.dispose();
    super.dispose();
  }

  // Switch Between Login & Register
  void showForm(int index) {
    setState(() => activeTab = index);
    pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
  }

  // ---------------- REGISTER ----------------
  Future<void> registerUser() async {
    if (regEmail.text.isEmpty ||
        regUser.text.isEmpty ||
        regConsumer.text.isEmpty ||
        regPass.text.isEmpty) {
      _showSnack("Please fill all fields");
      return;
    }

    setState(() => isLoading = true);

    final res = await ApiService.register(
      username: regUser.text.trim(),
      email: regEmail.text.trim(),
      consumerNumber: regConsumer.text.trim(),
      password: regPass.text.trim(),
    );

    setState(() => isLoading = false);

    _showSnack(res['message']);

    if (res['message'] == 'Registration successful') {
      showForm(0); // go to login
    }
  }

  // ---------------- LOGIN ----------------
  Future<void> loginUserFun() async {
    if (loginUser.text.isEmpty || loginPass.text.isEmpty) {
      _showSnack("Enter email and password");
      return;
    }

    setState(() => isLoading = true);

    final success = await ApiService.login(
      email: loginUser.text.trim(),
      password: loginPass.text.trim(),
    );

    setState(() => isLoading = false);

    if (!mounted) return;

    if (success) {
      Navigator.pushReplacementNamed(context, '/dashboard');
    } else {
      _showSnack("Invalid credentials");
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A2A),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.all(25),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Watt Buddy ⚡",
                      style: GoogleFonts.montserrat(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Login or Register to continue",
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 20),

                    // Tabs
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Row(
                        children: [
                          Expanded(child: _tabButton("Login", 0)),
                          Expanded(child: _tabButton("Register", 1)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      height: 420,
                      child: PageView(
                        controller: pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [_buildLoginForm(), _buildRegisterForm()],
                      ),
                    ),

                    if (isLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 15),
                        child: CircularProgressIndicator(
                          color: Colors.blueAccent,
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
  }

  // ---------------- FORMS ----------------

  Widget _buildLoginForm() {
    return Column(
      children: [
        _inputField(loginUser, "Email or Username", FontAwesomeIcons.user),
        _inputField(
          loginPass,
          "Password",
          FontAwesomeIcons.lock,
          isPassword: true,
        ),
        const SizedBox(height: 20),
        _submitButton("Login", loginUserFun),
      ],
    );
  }

  Widget _buildRegisterForm() {
    return Column(
      children: [
        _inputField(regEmail, "Email", FontAwesomeIcons.envelope),
        _inputField(regUser, "Username", FontAwesomeIcons.user),
        _inputField(regConsumer, "Consumer Number", FontAwesomeIcons.hashtag),
        _inputField(
          regPass,
          "Password",
          FontAwesomeIcons.lock,
          isPassword: true,
        ),
        const SizedBox(height: 20),
        _submitButton("Register", registerUser),
      ],
    );
  }

  // ---------------- REUSABLE ----------------

  Widget _tabButton(String title, int index) {
    return GestureDetector(
      onTap: () => showForm(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: activeTab == index
              ? const LinearGradient(
                  colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
                )
              : null,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              color: activeTab == index ? Colors.white : Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputField(
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool isPassword = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.white70, size: 18),
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white12,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(50),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _submitButton(String text, Future<void> Function() onTap) {
    return ElevatedButton(
      onPressed: isLoading ? null : onTap,
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
      ),
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF00C6FF), Color(0xFF0072FF)],
          ),
          borderRadius: BorderRadius.circular(50),
        ),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
