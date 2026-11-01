import 'package:flutter/material.dart';
import '../models/building_model.dart';

class RoutePickerCard extends StatelessWidget {
  final List<Building> buildings;
  final Building? startBuilding;
  final Building? destinationBuilding;
  final ValueChanged<Building?> onStartChanged;
  final ValueChanged<Building?> onDestinationChanged;
  final VoidCallback onSwap;
  final VoidCallback onStartNavigation;
  final VoidCallback onLogout;

  const RoutePickerCard({
    super.key,
    required this.buildings,
    required this.startBuilding,
    required this.destinationBuilding,
    required this.onStartChanged,
    required this.onDestinationChanged,
    required this.onSwap,
    required this.onStartNavigation,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with App Title & Logout Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.near_me_rounded, color: Color(0xFF0F5B33), size: 22),
                  SizedBox(width: 8),
                  Text(
                    'KenemeRoute',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F5B33),
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22),
                tooltip: 'Log Out',
                onPressed: onLogout,
              ),
            ],
          ),
          const Divider(height: 12),

          // Starting Location Picker
          Row(
            children: [
              const Icon(Icons.my_location_rounded, color: Color(0xFF0F5B33), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Building>(
                    isExpanded: true,
                    hint: const Text('Select Starting Location'),
                    value: startBuilding,
                    items: buildings.map((b) {
                      return DropdownMenuItem(
                        value: b,
                        child: Text(b.name, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: onStartChanged,
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 16),

          // Destination Location Picker + Swap Button
          Row(
            children: [
              const Icon(Icons.location_on_rounded, color: Colors.redAccent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<Building>(
                    isExpanded: true,
                    hint: const Text('Select Destination'),
                    value: destinationBuilding,
                    items: buildings.map((b) {
                      return DropdownMenuItem(
                        value: b,
                        child: Text(b.name, overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: onDestinationChanged,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.swap_vert_rounded, color: Color(0xFF0F5B33)),
                onPressed: onSwap,
                tooltip: 'Swap locations',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Go Now / Start Route Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (startBuilding != null && destinationBuilding != null)
                  ? onStartNavigation
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F5B33),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              icon: const Icon(Icons.navigation_rounded),
              label: const Text(
                'Go Now',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}