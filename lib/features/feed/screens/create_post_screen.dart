import 'package:flutter/material.dart';
import '../../creator_studio/screens/zev_creator_studio_screen.dart';

/// Legacy adapter for CreatePostScreen - delegates to ZevCreatorStudioScreen
class CreatePostScreen extends StatelessWidget {
  final VoidCallback? onPostSuccess;
  final VoidCallback? onCancel;

  const CreatePostScreen({
    super.key,
    this.onPostSuccess,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return ZevCreatorStudioScreen(
      initialTab: 0,
      onBack: onCancel,
    );
  }
}
