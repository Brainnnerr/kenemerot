import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

import 'models/building_model.dart';
import 'widgets/route_picker_card.dart';
import 'widgets/building_info_card.dart';
import 'login_screen.dart';

enum TravelMode { walk, drive }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MapController _mapController = MapController();
  final _supabase = Supabase.instance.client;

  // ESSU Main Campus Center Coordinates
  static final LatLng _essuCenter = LatLng(11.659873, 125.443931);

  // Current Position
  final LatLng _userLocation = LatLng(11.659873347621199, 125.446549721744);

  List<Building> _buildings = [];
  Building? _startBuilding;
  Building? _destinationBuilding;
  Building? _selectedBuildingMarker;

  TravelMode _selectedTravelMode = TravelMode.walk;

  bool _isLoading = true;
  bool _isNavigating = false;
  bool _isFetchingRoute = false;

  List<LatLng> _routePoints = [];
  String _estimatedTime = "";
  String _estimatedDistance = "";
  LatLng? _estimatedCardPosition;

  @override
  void initState() {
    super.initState();
    _fetchBuildings();
  }

  Future<void> _fetchBuildings() async {
    try {
      final data = await _supabase.from('buildings').select();
      final List<Building> loaded =
          (data as List).map((json) => Building.fromJson(json)).toList();

      setState(() {
        _buildings = loaded;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load campus locations: $e')),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  // Fetch route from OSRM based on selected travel mode (foot or driving)
  Future<void> _fetchRoute(LatLng start, LatLng dest, TravelMode mode) async {
    setState(() {
      _isFetchingRoute = true;
    });

    final String profile = mode == TravelMode.walk ? 'foot' : 'driving';
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/$profile/${start.longitude},${start.latitude};${dest.longitude},${dest.latitude}?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final geometry = route['geometry'];
          final List<dynamic> coordinates = geometry['coordinates'];

          final List<LatLng> points = coordinates.map((coord) {
            return LatLng(coord[1] as double, coord[0] as double);
          }).toList();

          final double distanceMeters = (route['distance'] as num).toDouble();
          final double durationSeconds = (route['duration'] as num).toDouble();

          // Calculate time in minutes or seconds
          final int minutes = (durationSeconds / 60).round();
          final String timeStr = minutes < 1
              ? '1 min'
              : (minutes >= 60
                  ? '${(minutes / 60).floor()} hr ${minutes % 60} min'
                  : '$minutes min');

          final String distanceStr = distanceMeters >= 1000
              ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
              : '${distanceMeters.round()} m';

          setState(() {
            _routePoints = points;
            _estimatedTime = timeStr;
            _estimatedDistance = distanceStr;
            if (points.isNotEmpty) {
              _estimatedCardPosition = points[points.length ~/ 2];
            }
          });
        }
      } else {
        _useFallbackRoute(start, dest, mode);
      }
    } catch (e) {
      _useFallbackRoute(start, dest, mode);
    } finally {
      setState(() {
        _isFetchingRoute = false;
      });
    }
  }

  void _useFallbackRoute(LatLng start, LatLng dest, TravelMode mode) {
    const Distance distanceCalc = Distance();
    final double distanceMeters = distanceCalc.as(LengthUnit.Meter, start, dest);

    // Speed estimates: Walk ~ 1.38 m/s (5 km/h), Drive ~ 8.33 m/s (30 km/h)
    final double speed = mode == TravelMode.walk ? 1.38 : 8.33;
    final int minutes = (distanceMeters / speed / 60).round().clamp(1, 120);

    final String distanceStr = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(1)} km'
        : '${distanceMeters.round()} m';

    setState(() {
      _routePoints = [start, dest];
      _estimatedTime = '$minutes min';
      _estimatedDistance = distanceStr;
      _estimatedCardPosition = LatLng(
        (start.latitude + dest.latitude) / 2,
        (start.longitude + dest.longitude) / 2,
      );
    });
  }

  Future<void> _handleLogout() async {
    await _supabase.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _swapLocations() {
    setState(() {
      final temp = _startBuilding;
      _startBuilding = _destinationBuilding;
      _destinationBuilding = temp;
      if (_isNavigating) {
        _startNavigation();
      }
    });
  }

  void _recenterMap() {
    _mapController.move(_userLocation, 17.5);
  }

  Future<void> _startNavigation() async {
    if (_startBuilding == null || _destinationBuilding == null) return;

    setState(() {
      _isNavigating = true;
    });

    final startLatLng =
        LatLng(_startBuilding!.latitude, _startBuilding!.longitude);
    final destLatLng =
        LatLng(_destinationBuilding!.latitude, _destinationBuilding!.longitude);

    await _fetchRoute(startLatLng, destLatLng, _selectedTravelMode);

    if (_routePoints.isNotEmpty) {
      final bounds = LatLngBounds.fromPoints(_routePoints);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(70)),
      );
    }
  }

  void _cancelNavigation() {
    setState(() {
      _isNavigating = false;
      _routePoints.clear();
      _estimatedCardPosition = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Fullscreen Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _essuCenter,
              initialZoom: 17.5,
              minZoom: 15.0,
              maxZoom: 19.0,
              onTap: (tapPosition, point) =>
                  setState(() => _selectedBuildingMarker = null),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.kenemeroute.app',
              ),

              // 2. Navigation Polyline & Walking Dots
              if (_isNavigating && _routePoints.isNotEmpty) ...[
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 8.0,
                      color: const Color(0xFF4A90E2).withValues(alpha: 0.8),
                    ),
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 4.0,
                      color: const Color(0xFF1F73B8),
                    ),
                  ],
                ),

                // Walking Dots (shown only in walk mode)
                if (_selectedTravelMode == TravelMode.walk)
                  MarkerLayer(
                    markers: _routePoints.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final point = entry.value;

                      if (idx == 0 ||
                          idx == _routePoints.length - 1 ||
                          idx % 2 != 0) {
                        return Marker(
                          point: point,
                          width: 1,
                          height: 1,
                          child: const SizedBox.shrink(),
                        );
                      }

                      return Marker(
                        point: point,
                        width: 10,
                        height: 10,
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF3F51B5),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],

              // 3. User & Building Markers
              MarkerLayer(
                markers: [
                  // User Current Location Blue Dot
                  Marker(
                    point: _userLocation,
                    width: 48,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.25),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Campus Building Markers
                  ..._buildings.map((b) {
                    final isSelected = _selectedBuildingMarker?.id == b.id;
                    final isStart = _startBuilding?.id == b.id;
                    final isDest = _destinationBuilding?.id == b.id;

                    Color pinColor = const Color(0xFF0F5B33);
                    if (isSelected) pinColor = Colors.orangeAccent;
                    if (isStart) pinColor = const Color(0xFF2196F3);
                    if (isDest) pinColor = const Color(0xFFF44336);

                    return Marker(
                      point: LatLng(b.latitude, b.longitude),
                      width: isSelected ? 50 : 40,
                      height: isSelected ? 50 : 40,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _selectedBuildingMarker = b);
                          _mapController.move(
                            LatLng(b.latitude, b.longitude),
                            18.0,
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: pinColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: Icon(
                            isStart
                                ? Icons.my_location_rounded
                                : (isDest
                                    ? Icons.location_on_rounded
                                    : Icons.location_city_rounded),
                            color: Colors.white,
                            size: isSelected ? 28 : 22,
                          ),
                        ),
                      ),
                    );
                  }),

                  // Floating Travel Time / Distance Card
                  if (_isNavigating &&
                      _estimatedCardPosition != null &&
                      !_isFetchingRoute)
                    Marker(
                      point: _estimatedCardPosition!,
                      width: 140,
                      height: 60,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                          border:
                              Border.all(color: Colors.grey.shade300, width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _selectedTravelMode == TravelMode.walk
                                  ? Icons.directions_walk_rounded
                                  : Icons.directions_car_rounded,
                              color: const Color(0xFF0F5B33),
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _estimatedTime,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                                Text(
                                  _estimatedDistance,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),

          // 4. Floating Top Route Selection Card with Walk / Drive Mode Selector
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _isLoading
                      ? const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Color(0xFF0F5B33),
                              ),
                            ),
                          ),
                        )
                      : RoutePickerCard(
                          buildings: _buildings,
                          startBuilding: _startBuilding,
                          destinationBuilding: _destinationBuilding,
                          onStartChanged: (val) {
                            setState(() {
                              _startBuilding = val;
                              _isNavigating = false;
                            });
                          },
                          onDestinationChanged: (val) {
                            setState(() {
                              _destinationBuilding = val;
                              _isNavigating = false;
                            });
                          },
                          onSwap: _swapLocations,
                          onLogout: _handleLogout,
                          onStartNavigation: _startNavigation,
                        ),

                  const SizedBox(height: 8),

                  // Walk / Drive Segmented Mode Switcher
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ChoiceChip(
                          label: const Row(
                            children: [
                              Icon(Icons.directions_walk_rounded, size: 18),
                              SizedBox(width: 4),
                              Text('Walk'),
                            ],
                          ),
                          selected: _selectedTravelMode == TravelMode.walk,
                          selectedColor: const Color(0xFF0F5B33),
                          labelStyle: TextStyle(
                            color: _selectedTravelMode == TravelMode.walk
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedTravelMode = TravelMode.walk;
                              });
                              if (_isNavigating) _startNavigation();
                            }
                          },
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Row(
                            children: [
                              Icon(Icons.directions_car_rounded, size: 18),
                              SizedBox(width: 4),
                              Text('Drive'),
                            ],
                          ),
                          selected: _selectedTravelMode == TravelMode.drive,
                          selectedColor: const Color(0xFF0F5B33),
                          labelStyle: TextStyle(
                            color: _selectedTravelMode == TravelMode.drive
                                ? Colors.white
                                : Colors.black87,
                            fontWeight: FontWeight.bold,
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _selectedTravelMode = TravelMode.drive;
                              });
                              if (_isNavigating) _startNavigation();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Loading Banner
          if (_isFetchingRoute)
            const Positioned(
              top: 250,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF0F5B33),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text("Calculating route"),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // 5. End Route Button
          if (_isNavigating)
            Positioned(
              left: 16,
              bottom: 24,
              child: FloatingActionButton.extended(
                heroTag: 'cancel_nav_btn',
                onPressed: _cancelNavigation,
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.close_rounded),
                label: const Text('End Route'),
              ),
            ),

          // 6. Recenter Location Button
          Positioned(
            right: 16,
            bottom: _selectedBuildingMarker != null ? 180 : 24,
            child: FloatingActionButton(
              heroTag: 'recenter_btn',
              onPressed: _recenterMap,
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0F5B33),
              child: const Icon(Icons.my_location_rounded),
            ),
          ),

          // 7. Bottom Selected Building Info Card
          if (_selectedBuildingMarker != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BuildingInfoCard(
                building: _selectedBuildingMarker!,
                onClose: () => setState(() => _selectedBuildingMarker = null),
                onSetAsDestination: () {
                  setState(() {
                    _destinationBuilding = _selectedBuildingMarker;
                    _selectedBuildingMarker = null;
                  });
                },
              ),
            ),
        ],
      ),
    );
  }
}