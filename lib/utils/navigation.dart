import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NavigationHelper {
  static void navigateTo(BuildContext context, String routeName) {
    // Don't navigate if already on that route
    if (ModalRoute.of(context)?.settings.name == routeName) {
      return;
    }

    // Use pushReplacement for main pages to avoid back stack issues
    if (routeName == '/dashboard' ||
        routeName == '/profile' ||
        routeName == '/bill-prediction' ||
        routeName == '/rewards' ||
        routeName == '/devices' ||
        routeName == '/recommendations') {
      Navigator.pushReplacementNamed(context, routeName);
    } else {
      Navigator.pushNamed(context, routeName);
    }
  }

  static Widget createSidebar({
    required BuildContext context,
    required String currentRoute,
    required bool isOpen,
    required VoidCallback onToggle,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: isOpen ? 260 : 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.04),
          ],
        ),
        border: Border(
          right: BorderSide(color: Colors.white.withOpacity(0.15), width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with toggle button
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggle,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isOpen)
                    Text(
                      "Watt Buddy ⚡",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        isOpen ? Icons.menu_open : Icons.menu,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Divider(color: Colors.white.withOpacity(0.1), height: 1),

          const SizedBox(height: 20),

          // Navigation Menu
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                children: [
                  _navItem(
                    context: context,
                    icon: Icons.dashboard,
                    label: "Dashboard",
                    route: '/dashboard',
                    currentRoute: currentRoute,
                    isOpen: isOpen,
                  ),
                  _navItem(
                    context: context,
                    icon: Icons.trending_up,
                    label: "Bill Predictor",
                    route: '/bill-prediction',
                    currentRoute: currentRoute,
                    isOpen: isOpen,
                  ),
                  _navItem(
                    context: context,
                    icon: Icons.person,
                    label: "Profile",
                    route: '/profile',
                    currentRoute: currentRoute,
                    isOpen: isOpen,
                  ),
                  _navItem(
                    context: context,
                    icon: Icons.card_giftcard,
                    label: "Rewards",
                    route: '/rewards',
                    currentRoute: currentRoute,
                    isOpen: isOpen,
                  ),
                  // In the createSidebar method, add this nav item:
                  _navItem(
                    context: context,
                    icon: Icons.devices,
                    label: "Devices",
                    route: '/devices',
                    currentRoute: currentRoute,
                    isOpen: isOpen,
                  ),
                  _navItem(
                    context: context,
                    icon: Icons.shopping_bag,
                    label: "Recommendations",
                    route: '/recommendations',
                    currentRoute: currentRoute,
                    isOpen: isOpen,
                  ),
                  const Spacer(),
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.logout, color: Colors.redAccent),
                      title: isOpen
                          ? Text(
                              "Logout",
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: 14,
                              ),
                            )
                          : null,
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool('isLoggedIn', false);
                        Navigator.pushReplacementNamed(context, '/login');
                      },
                      contentPadding: const EdgeInsets.symmetric(horizontal: 5),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _navItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String route,
    required String currentRoute,
    required bool isOpen,
  }) {
    bool isActive = currentRoute == route;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isActive
            ? const Color(0xFF00D4FF).withOpacity(0.2)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isActive
            ? Border.all(color: const Color(0xFF00D4FF).withOpacity(0.4))
            : null,
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isActive
              ? const Color(0xFF00D4FF)
              : Colors.white.withOpacity(0.6),
          size: 22,
        ),
        title: isOpen
            ? Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? const Color(0xFF00D4FF)
                      : Colors.white.withOpacity(0.7),
                  fontSize: 14,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                ),
              )
            : null,
        onTap: isActive
            ? null
            : () => NavigationHelper.navigateTo(context, route),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
        minLeadingWidth: 30,
      ),
    );
  }
}
