import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../services/theme_provider.dart';

class DisplaySettingsScreen extends StatelessWidget {
  const DisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final cardColor = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('화면 설정', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LucideIcons.chevronLeft, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('테마 및 색상', textColor),
            const SizedBox(height: 12),
            _buildSettingsContainer(
              cardColor,
              textColor,
              [
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
                    return SwitchListTile(
                      title: Text('다크 모드', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                      secondary: Icon(
                        themeProvider.themeMode == ThemeMode.dark ? LucideIcons.moon : LucideIcons.sun,
                        color: const Color(0xFF2EA043),
                      ),
                      value: themeProvider.themeMode == ThemeMode.dark,
                      onChanged: (value) => themeProvider.toggleTheme(value),
                      activeColor: const Color(0xFF2EA043),
                    );
                  },
                ),
                _buildDivider(textColor),
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
                    return SwitchListTile(
                      title: Text('색약자 지원 모드', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                      secondary: const Icon(LucideIcons.eye, color: Color(0xFF2EA043)),
                      value: themeProvider.isColorBlindMode,
                      onChanged: (value) => themeProvider.toggleColorBlindMode(value),
                      activeColor: const Color(0xFF2EA043),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 32),
            _buildSectionTitle('가독성', textColor),
            const SizedBox(height: 12),
            _buildSettingsContainer(
              cardColor,
              textColor,
              [
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, child) {
                    return SwitchListTile(
                      title: Text('큰 글자 모드', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor)),
                      secondary: const Icon(LucideIcons.type, color: Color(0xFF2EA043)),
                      value: themeProvider.textScaleFactor > 1.0,
                      onChanged: (value) => themeProvider.setTextScaleFactor(value ? 1.2 : 1.0),
                      activeColor: const Color(0xFF2EA043),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color textColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(title, style: TextStyle(color: textColor.withOpacity(0.5), fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSettingsContainer(Color cardColor, Color textColor, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withOpacity(0.1)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider(Color textColor) {
    return Divider(height: 1, color: textColor.withOpacity(0.05), indent: 56, endIndent: 16);
  }
}
