import 'package:flutter/material.dart';
import '../../creator_studio/screens/zev_creator_studio_screen.dart';

/// Legacy adapter for UploadReelScreen - delegates to ZevCreatorStudioScreen
class UploadReelScreen extends StatelessWidget {
  const UploadReelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ZevCreatorStudioScreen(initialTab: 1);
  }
}
