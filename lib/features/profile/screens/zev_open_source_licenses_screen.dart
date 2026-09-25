import 'package:flutter/material.dart';
import '../../../core/widgets/responsive_layout.dart';

class ZevOpenSourceLicensesScreen extends StatelessWidget {
  const ZevOpenSourceLicensesScreen({super.key});

  static const Color primaryPink = Color(0xFFFC466B);
  static const Color surfaceWhite = Color(0xFFFFFFFF);
  static const Color textDark = Color(0xFF0F172A);
  static const Color textGrey = Color(0xFF64748B);
  static const Color cardBorder = Color(0xFFF1F5F9);
  static const Color lightPinkBg = Color(0xFFFFF1F2);

  final List<Map<String, String>> _packages = const [
    {
      "name": "Flutter Framework",
      "version": "v3.11+",
      "license": "BSD-3-Clause",
      "author": "Google LLC & Flutter Contributors",
      "description": "Google's UI toolkit for building beautiful native apps.",
    },
    {
      "name": "supabase_flutter",
      "version": "^2.16.0",
      "license": "MIT",
      "author": "Supabase Community",
      "description":
          "Open source Firebase alternative for backend, authentication and real-time database.",
    },
    {
      "name": "local_auth",
      "version": "^3.0.1",
      "license": "BSD-3-Clause",
      "author": "Flutter Team",
      "description":
          "Biometric authentication plugin supporting fingerprint and Face ID.",
    },
    {
      "name": "cached_network_image",
      "version": "^3.4.1",
      "license": "MIT",
      "author": "Baseflow",
      "description":
          "Cached image loading for high-performance fluid feed scrolling.",
    },
    {
      "name": "video_player",
      "version": "^2.9.2",
      "license": "BSD-3-Clause",
      "author": "Flutter Team",
      "description": "Native high-performance video playback for ZEV Reels.",
    },
    {
      "name": "device_info_plus",
      "version": "^11.2.0",
      "license": "BSD-3-Clause",
      "author": "Flutter Community",
      "description": "Device telemetry and hardware specifications detection.",
    },
    {
      "name": "shared_preferences",
      "version": "^2.3.2",
      "license": "BSD-3-Clause",
      "author": "Flutter Team",
      "description":
          "Persistent local key-value storage for secure user preferences.",
    },
    {
      "name": "intl",
      "version": "latest",
      "license": "BSD-3-Clause",
      "author": "Dart Team",
      "description":
          "Internationalization and multi-language formatting across 19 global languages.",
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: surfaceWhite,
      appBar: AppBar(
        backgroundColor: surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: textDark,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Open Source Licenses",
          style: TextStyle(
            color: textDark,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: ResponsiveLayout.feedConstraint(
        maxWidth: 700,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            const Text(
              "Built With Open Source",
              style: TextStyle(
                color: textDark,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "ZEV is powered by premier open-source software libraries. We gratefully acknowledge the creators and contributors:",
              style: TextStyle(color: textGrey, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 20),

            for (var p in _packages)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surfaceWhite,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            p["name"]!,
                            style: const TextStyle(
                              color: textDark,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: lightPinkBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            p["license"]!,
                            style: const TextStyle(
                              color: primaryPink,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Author: ${p["author"]} • ${p["version"]}",
                      style: const TextStyle(color: textGrey, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      p["description"]!,
                      style: const TextStyle(
                        color: textDark,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  showLicensePage(
                    context: context,
                    applicationName: "ZEV Social",
                    applicationVersion: "1.0.0 (Build 2026.1)",
                    applicationLegalese:
                        "© 2026 ZEV Technologies Inc. All rights reserved.",
                  );
                },
                icon: const Icon(
                  Icons.article_outlined,
                  color: primaryPink,
                  size: 18,
                ),
                label: const Text(
                  "View Complete System Package Licenses",
                  style: TextStyle(
                    color: primaryPink,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
