import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

class LoginBrandPanel extends StatelessWidget {
  const LoginBrandPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage(AppAssets.bgLogin),
          fit: BoxFit.cover,
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(52),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x33000000), Color(0xD9000000)],
          ),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.handyman_rounded, color: AppColors.richGold, size: 36),
            SizedBox(height: 18),
            Text(
              'BUILDPRO',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'Cinzel',
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 10),
            SizedBox(
              width: 430,
              child: Text(
                'Hardware operations, inventory, and sales—managed in one reliable workspace.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
