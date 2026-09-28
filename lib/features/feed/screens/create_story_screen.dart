import 'package:flutter/material.dart';
import '../../creator_studio/screens/zev_creator_studio_screen.dart';

/// Legacy adapter for CreateStoryScreen - delegates to ZevCreatorStudioScreen
class CreateStoryScreen extends StatelessWidget {
  const CreateStoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ZevCreatorStudioScreen(initialTab: 2);
  }
}
