import 'package:flutter/material.dart';

class SpinnerOverlay extends StatelessWidget {
  const SpinnerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/app_identify.png',
            width: 80,
            fit: BoxFit.cover,
          ),
          SizedBox(height: 12),
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
