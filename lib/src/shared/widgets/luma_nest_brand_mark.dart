import 'package:flutter/material.dart';

/// Compact product logo shared by in-app brand surfaces.
class LumaNestBrandMark extends StatelessWidget {
  const LumaNestBrandMark({super.key, this.size = 30});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: '栖光产品标识',
    child: SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * .28),
        child: Image.asset(
          'assets/brand/lumanest-logo.png',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      ),
    ),
  );
}
