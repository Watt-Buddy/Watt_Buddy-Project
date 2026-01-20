import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../utils/responsive_scaffold.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Account info
  String username = 'Not set';
  String email = 'Not set';
  String consumerNumber = 'Not set';

  // Editable fields
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadProfileDetails();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final storedUser = prefs.getString('wattBuddyUser');

    if (storedUser != null) {
      final user = jsonDecode(storedUser);
      setState(() {
        username = user['username'] ?? 'Not set';
        email = user['email'] ?? 'Not set';
        consumerNumber = user['consumer'] ?? 'Not set';
      });
    }
  }

  Future<void> _loadProfileDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final storedProfile = prefs.getString('profileDetails');

    if (storedProfile != null) {
      final data = jsonDecode(storedProfile);
      _fullNameController.text = data['fullName'] ?? '';
      _phoneController.text = data['phone'] ?? '';
      _addressController.text = data['address'] ?? '';
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final prefs = await SharedPreferences.getInstance();
    final data = {
      'fullName': _fullNameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'address': _addressController.text.trim(),
    };

    await prefs.setString('profileDetails', jsonEncode(data));

    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Success"),
          content: const Text("Profile updated successfully."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("OK"),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScaffold(
      currentRoute: '/profile',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER
            const Text(
              "Account Settings",
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Manage your account and personal information",
              style: TextStyle(color: Colors.white70),
            ),

            const SizedBox(height: 30),

            // PROFILE CARD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white24),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ACCOUNT INFO
                    const Text(
                      "Account Information",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),

                    _readOnlyField("Username", username),
                    const SizedBox(height: 15),
                    _readOnlyField("Email", email),
                    const SizedBox(height: 15),
                    _readOnlyField("Consumer Number", consumerNumber),

                    const SizedBox(height: 30),
                    Divider(color: Colors.white24),
                    const SizedBox(height: 25),

                    // PERSONAL DETAILS
                    const Text(
                      "Personal Details",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),

                    _inputField(
                      controller: _fullNameController,
                      label: "Full Name",
                    ),
                    const SizedBox(height: 15),

                    _inputField(
                      controller: _phoneController,
                      label: "Phone Number",
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 15),

                    _inputField(
                      controller: _addressController,
                      label: "Address",
                      maxLines: 3,
                    ),

                    const SizedBox(height: 25),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _updateProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0072FF),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          "Update Profile",
                          style: TextStyle(fontSize: 16),
                        ),
                      ),
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

  // ---------------- WIDGETS ----------------

  Widget _readOnlyField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 5),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Text(value, style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      validator: (v) => v == null || v.isEmpty ? "Required field" : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blue),
        ),
      ),
    );
  }
}
