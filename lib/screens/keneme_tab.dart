import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

import '../models/building_model.dart';
import '../widgets/route_picker_card.dart';
import '../widgets/building_info_card.dart';

enum TravelMode { walk, drive }

class KenemeTab extends StatefulWidget {
  const KenemeTab({super.key});

  @override
  State<KenemeTab> createState() => _KenemeTabState();
}

class _KenemeTabState extends State<KenemeTab> {
  final MapController _mapController = MapController();
  final _supabase = Supabase.instance.client;

  static final LatLng _essuCenter = LatLng(11.659873, 125.443931);
  LatLng _userLocation = LatLng(11.659873347621199, 125.446549721744);

  StreamSubscription<Position>? _positionStream;

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
    _initLiveLocationTracking();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  Future<void> _initLiveLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    _updateUserLocation(LatLng(position.latitude, position.longitude));

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen((Position pos) {
      _updateUserLocation(LatLng(pos.latitude, pos.longitude));
    });
  }

  void _updateUserLocation(LatLng newLocation) {
    setState(() {
      _userLocation = newLocation;
    });

    if (_startBuilding == null && _buildings.isNotEmpty) {
      _autoSetNearestStartBuilding(newLocation);
    }
  }

  void _autoSetNearestStartBuilding(LatLng pos) {
    const Distance distanceCalc = Distance();
    Building? closest;
    double minDistance = double.infinity;

    for (var b in _buildings) {
      final double dist = distanceCalc.as(
        LengthUnit.Meter,
        pos,
        LatLng(b.latitude, b.longitude),
      );
      if (dist < minDistance) {
        minDistance = dist;
        closest = b;
      }
    }

    if (closest != null) {
      setState(() {
        _startBuilding = closest;
      });
    }
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

      _autoSetNearestStartBuilding(_userLocation);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchRoute(LatLng start, LatLng dest, TravelMode mode) async {
    setState(() => _isFetchingRoute = true);

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

          final int minutes = (durationSeconds / 60).round();
          final String timeStr = minutes < 1 ? '1 min' : '$minutes min';
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
      }
    } catch (_) {
      // Fallback
    } finally {
      setState(() => _isFetchingRoute = false);
    }
  }

  void _recenterMap() {
    _mapController.move(_userLocation, 18.0);
  }

  Future<void> _startNavigation() async {
    if (_startBuilding == null || _destinationBuilding == null) return;

    setState(() => _isNavigating = true);

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

              if (_isNavigating && _routePoints.isNotEmpty) ...[
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 6.0,
                      color: const Color(0xFF0F5B33),
                    ),
                  ],
                ),
              ],

              MarkerLayer(
                markers: [
                  // User GPS Location Marker
                  Marker(
                    point: _userLocation,
                    width: 48,
                    height: 48,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                        ),
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.blueAccent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Campus Buildings
                  ..._buildings.map((b) {
                    final isStart = _startBuilding?.id == b.id;
                    final isDest = _destinationBuilding?.id == b.id;
                    final isSelected = _selectedBuildingMarker?.id == b.id;

                    Color pinColor = const Color(0xFF0F5B33);
                    if (isSelected) pinColor = Colors.orangeAccent;
                    if (isStart) pinColor = Colors.blue;
                    if (isDest) pinColor = Colors.red;

                    return Marker(
                      point: LatLng(b.latitude, b.longitude),
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedBuildingMarker = b),
                        child: Container(
                          decoration: BoxDecoration(
                            color: pinColor,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isStart ? Icons.my_location : Icons.location_on,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    );
                  }),

                  // Estimated Route Card
                  if (_isNavigating &&
                      _estimatedCardPosition != null &&
                      !_isFetchingRoute)
                    Marker(
                      point: _estimatedCardPosition!,
                      width: 130,
                      height: 50,
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
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _selectedTravelMode == TravelMode.walk
                                  ? Icons.directions_walk
                                  : Icons.directions_car,
                              color: const Color(0xFF0F5B33),
                              size: 20,
                            ),
                            const SizedBox(width: 6),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _estimatedTime,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                Text(
                                  _estimatedDistance,
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.grey),
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

          // Route Picker Card
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
                            child: CircularProgressIndicator(
                              color: Color(0xFF0F5B33),
                            ),
                          ),
                        )
                      : RoutePickerCard(
                          buildings: _buildings,
                          startBuilding: _startBuilding,
                          destinationBuilding: _destinationBuilding,
                          onStartChanged: (val) =>
                              setState(() => _startBuilding = val),
                          onDestinationChanged: (val) =>
                              setState(() => _destinationBuilding = val),
                          onSwap: () {
                            setState(() {
                              final temp = _startBuilding;
                              _startBuilding = _destinationBuilding;
                              _destinationBuilding = temp;
                            });
                          },
                          onLogout: () {},
                          onStartNavigation: _startNavigation,
                        ),
                  const SizedBox(height: 8),

                  // Walk / Drive Mode Switcher
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

          // Floating Buttons
          if (_isNavigating)
            Positioned(
              left: 16,
              bottom: 24,
              child: FloatingActionButton.extended(
                onPressed: _cancelNavigation,
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                label: const Text('End Route'),
                icon: const Icon(Icons.close),
              ),
            ),

          Positioned(
            right: 16,
            bottom: _selectedBuildingMarker != null ? 180 : 24,
            child: FloatingActionButton(
              onPressed: _recenterMap,
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location, color: Color(0xFF0F5B33)),
            ),
          ),

          // Selected Building Info Card
          if (_selectedBuildingMarker != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BuildingInfoCard(
                building: _selectedBuildingMarker!,
                onClose: () =>
                    setState(() => _selectedBuildingMarker = null),
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