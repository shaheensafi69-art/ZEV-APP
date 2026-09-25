import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CircularFlag extends StatelessWidget {
  final String countryCode;
  final double size;

  const CircularFlag({super.key, required this.countryCode, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final code = countryCode.trim().toLowerCase();
    final flagUrl = 'https://flagcdn.com/w80/$code.png';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black.withOpacity(0.08), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: flagUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              Container(color: const Color(0xFFF3F4F6)),
          errorWidget: (context, url, error) => Container(
            color: const Color(0xFFFC466B).withOpacity(0.1),
            alignment: Alignment.center,
            child: Text(
              countryCode.toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.35,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFFC466B),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
