// lib/common/widgets/connectivity_banner.dart

import 'package:flutter/material.dart';
import 'package:face_auth_compatible/services/connectivity_service.dart';
import 'package:face_auth_compatible/constants/theme.dart';

class ConnectivityBanner extends StatelessWidget {
  final ConnectivityService connectivityService;

  const ConnectivityBanner({
    Key? key,
    required this.connectivityService
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectionStatus>(
      stream: connectivityService.connectionStatusStream,
      builder: (context, snapshot) {
        if (snapshot.data == ConnectionStatus.offline) {
          return Container(
            color: Colors.red,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'You are offline. Data will sync when connection is restored.',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          );
        }

        return const SizedBox.shrink(); // Nothing shown when online
      },
    );
  }
}