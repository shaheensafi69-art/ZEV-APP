import 'package:flutter/material.dart';
import '../theme/zev_theme.dart';

/// Next-Generation Modern Input Field for ZEV.
/// Reacts to focus with Electric Cyan (#00D4FF) highlight and subtle ambient glow.
class ZevTextField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData prefixIcon;
  final bool isPassword;
  final bool isObscured;
  final Widget? suffixIcon;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final int maxLines;
  final bool isReadOnly;
  final VoidCallback? onTap;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  const ZevTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.prefixIcon,
    this.isPassword = false,
    this.isObscured = false,
    this.suffixIcon,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.maxLines = 1,
    this.isReadOnly = false,
    this.onTap,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
  });

  @override
  State<ZevTextField> createState() => _ZevTextFieldState();
}

class _ZevTextFieldState extends State<ZevTextField> {
  late FocusNode _internalFocusNode;
  bool _isFocused = false;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = FocusNode();
    _effectiveFocusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() => _isFocused = _effectiveFocusNode.hasFocus);
    }
  }

  @override
  void didUpdateWidget(ZevTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      _effectiveFocusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    _internalFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _isFocused
                  ? ZevColors.primaryBlue
                  : ZevColors.textSecondary,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _isFocused ? Colors.white : ZevColors.softSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isFocused ? ZevColors.primaryBlue : ZevColors.border,
              width: _isFocused ? 1.8 : 1.2,
            ),
            boxShadow: _isFocused
                ? [
                    BoxShadow(
                      color: ZevColors.primaryBlue.withValues(alpha: 0.20),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _effectiveFocusNode,
            readOnly: widget.isReadOnly,
            onTap: widget.onTap,
            obscureText: widget.isObscured,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            autofillHints: widget.autofillHints,
            maxLines: widget.maxLines,
            cursorColor: ZevColors.primaryBlue,
            onChanged: widget.onChanged,
            onSubmitted: widget.onSubmitted,
            style: const TextStyle(
              color: ZevColors.deepNavy,
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: widget.maxLines > 1 ? 14 : 14,
              ),
              hintText: widget.hint,
              hintStyle: const TextStyle(
                color: ZevColors.textMuted,
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: Icon(
                widget.prefixIcon,
                size: 20,
                color: _isFocused
                    ? ZevColors.primaryBlue
                    : ZevColors.textMuted,
              ),
              suffixIcon: widget.suffixIcon,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}
