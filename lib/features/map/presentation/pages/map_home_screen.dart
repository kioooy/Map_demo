import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/map_notifier.dart';
import '../../domain/models/place_model.dart';

class MapHomeScreen extends ConsumerStatefulWidget {
  const MapHomeScreen({super.key});

  @override
  ConsumerState<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends ConsumerState<MapHomeScreen> {
  final MapController _mapController = MapController();

  void _zoomToUser() {
    final state = ref.read(mapProvider);
    if (state.userPosition != null) {
      _mapController.move(
        LatLng(state.userPosition!.latitude, state.userPosition!.longitude),
        15.0,
      );
    }
  }

  void _fitBounds(LatLng p1, LatLng p2) {
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(p1, p2),
        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 120),
      ),
    );
  }

  String _getTileUrl(AppMapType type) {
    switch (type) {
      case AppMapType.normal:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case AppMapType.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case AppMapType.terrain:
        return 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(mapProvider);

    // Xử lý tự động di chuyển camera đến vị trí người dùng lần đầu
    ref.listen<MapState>(mapProvider, (previous, next) {
      if (previous?.userPosition == null && next.userPosition != null) {
        _zoomToUser();
      }
    });

    // Xây dựng danh sách Marker
    final List<Marker> mapMarkers = [];

    // 1. Thêm vị trí người dùng
    if (state.userPosition != null) {
      mapMarkers.add(
        Marker(
          point: LatLng(state.userPosition!.latitude, state.userPosition!.longitude),
          width: 45,
          height: 45,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(40),
              shape: BoxShape.circle,
            ),
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade700,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(40),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: const Icon(
                Icons.person,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
        ),
      );
    }

    // 2. Thêm vị trí các cửa hàng lân cận
    for (var place in state.places) {
      final isSelected = state.selectedPlace?.id == place.id;
      final categoryColor = _getCategoryColor(place.category);

      mapMarkers.add(
        Marker(
          point: LatLng(place.latitude, place.longitude),
          width: 50,
          height: 50,
          child: GestureDetector(
            onTap: () {
              ref.read(mapProvider.notifier).selectPlace(place);
              if (state.userPosition != null) {
                _fitBounds(
                  LatLng(state.userPosition!.latitude, state.userPosition!.longitude),
                  LatLng(place.latitude, place.longitude),
                );
              }
            },
            child: AnimatedScale(
              scale: isSelected ? 1.25 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.location_on,
                    color: isSelected ? Colors.deepPurple : categoryColor,
                    size: 40,
                  ),
                  Positioned(
                    top: 8,
                    child: Icon(
                      _getCategoryIcon(place.category),
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 3. Thêm vị trí các sự cố giao thông (nếu bật Traffic)
    if (state.isTrafficEnabled) {
      for (var incident in state.incidents) {
        mapMarkers.add(
          Marker(
            point: LatLng(incident.latitude, incident.longitude),
            width: 38,
            height: 38,
            child: GestureDetector(
              onTap: () {
                _showIncidentDialog(context, incident);
              },
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                  ],
                ),
                child: Icon(
                  _getIncidentIcon(incident.type),
                  color: _getIncidentColor(incident.type),
                  size: 24,
                ),
              ),
            ),
          ),
        );
      }
    }

    // 4. Thêm các Marker trạm dừng xe buýt dọc tuyến đường (nếu chỉ đường bằng xe buýt)
    if (state.selectedTravelMode == TravelMode.transit && state.polylinePoints.isNotEmpty) {
      for (int i = 0; i < state.busStops.length; i++) {
        mapMarkers.add(
          Marker(
            point: state.busStops[i],
            width: 32,
            height: 32,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.deepOrange,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                ],
              ),
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        );
      }
    }

    // Xây dựng danh sách Polylines
    final List<Polyline> mapPolylines = [];

    // 1. Vẽ tuyến đường giao thông kẹt xe đỏ/vàng (nếu bật Traffic)
    if (state.isTrafficEnabled) {
      for (var points in state.redTrafficRoads) {
        mapPolylines.add(
          Polyline(
            points: points,
            color: Colors.red.withAlpha(200),
            strokeWidth: 6.0,
            strokeJoin: StrokeJoin.round,
            strokeCap: StrokeCap.round,
          ),
        );
      }
      for (var points in state.yellowTrafficRoads) {
        mapPolylines.add(
          Polyline(
            points: points,
            color: Colors.amber.withAlpha(200),
            strokeWidth: 6.0,
            strokeJoin: StrokeJoin.round,
            strokeCap: StrokeCap.round,
          ),
        );
      }
    }

    // 2. Vẽ đường dẫn hướng chính
    if (state.polylinePoints.isNotEmpty) {
      mapPolylines.add(
        Polyline(
          points: state.polylinePoints,
          color: _getRouteColor(state.selectedTravelMode),
          strokeWidth: 6.0,
          strokeJoin: StrokeJoin.round,
          strokeCap: StrokeCap.round,
          // Đi bộ vẽ nét đứt
          isDotted: state.selectedTravelMode == TravelMode.walking,
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // 1. Bản đồ chính
          state.userPosition == null && state.isLoading
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(color: Colors.deepPurple),
                      SizedBox(height: 16),
                      Text(
                        'Đang lấy vị trí GPS...',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple),
                      )
                    ],
                  ),
                )
              : FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: state.userPosition != null
                        ? LatLng(state.userPosition!.latitude, state.userPosition!.longitude)
                        : const LatLng(10.8751312, 106.8007233),
                    initialZoom: 15.0,
                    minZoom: 3.0,
                    maxZoom: 18.0,
                    onTap: (_, _) {
                      ref.read(mapProvider.notifier).clearSelection();
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _getTileUrl(state.mapType),
                      userAgentPackageName: 'com.techzone.techzone_ai',
                      subdomains: const ['a', 'b', 'c'],
                    ),
                    PolylineLayer(polylines: mapPolylines),
                    MarkerLayer(markers: mapMarkers),
                  ],
                ),

          // 2. Thanh tìm kiếm và chọn danh mục trên cùng
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MapSearchBar(
                  state: state,
                  mapController: _mapController,
                ),

              ],
            ),
          ),

          // 3. Các nút chức năng nổi bên phải
          Positioned(
            right: 16,
            bottom: state.selectedPlace != null ? 360 : 16,
            child: Column(
              children: [
                _buildFloatingButton(
                  icon: Icons.layers_outlined,
                  onPressed: ref.read(mapProvider.notifier).toggleMapType,
                  tooltip: 'Đổi loại bản đồ',
                ),
                const SizedBox(height: 12),
                _buildFloatingButton(
                  icon: Icons.my_location,
                  onPressed: _zoomToUser,
                  tooltip: 'Vị trí của tôi',
                ),
              ],
            ),
          ),

          // 4. Panel chi tiết địa điểm ở dưới cùng
          if (state.selectedPlace != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _buildPlaceDetailPanel(state),
            ),

          // 5. Loading Overlay
          if (state.isLoading && state.userPosition != null)
            Container(
              color: Colors.black12,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.deepPurple),
              ),
            ),

          // 6. Thông báo lỗi
          if (state.error != null)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Card(
                color: Colors.red[50],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          state.error!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.red),
                        onPressed: ref.read(mapProvider.notifier).getUserLocation,
                      )
                    ],
                  ),
                ),
              ),
            ),
            
          // 7. Nhãn bản quyền
          Positioned(
            left: 8,
            bottom: state.selectedPlace != null ? 360 : 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: Colors.white.withAlpha(150),
              child: const Text(
                '© OpenStreetMap contributors',
                style: TextStyle(fontSize: 9, color: Colors.black54),
              ),
            ),
          ),
        ],
      ),
    );
  }


  // Giao diện chọn danh mục ngang


  Color _getCategoryColor(PlaceCategory category) {
    switch (category) {
      case PlaceCategory.atm:
        return const Color(0xFF1E88E5);
      case PlaceCategory.restaurant:
        return const Color(0xFFFB8C00);
      case PlaceCategory.gas:
        return const Color(0xFF43A047);
      case PlaceCategory.hospital:
        return const Color(0xFFE53935);
      case PlaceCategory.school:
        return const Color(0xFF8E24AA); // Tím
      case PlaceCategory.store:
        return const Color(0xFF00ACC1); // Xanh lam
      case PlaceCategory.publicPlace:
        return const Color(0xFF7CB342); // Xanh đọt chuối
    }
  }

  IconData _getCategoryIcon(PlaceCategory category) {
    switch (category) {
      case PlaceCategory.atm:
        return Icons.local_atm;
      case PlaceCategory.restaurant:
        return Icons.restaurant;
      case PlaceCategory.gas:
        return Icons.local_gas_station;
      case PlaceCategory.hospital:
        return Icons.local_hospital;
      case PlaceCategory.school:
        return Icons.school;
      case PlaceCategory.store:
        return Icons.storefront;
      case PlaceCategory.publicPlace:
        return Icons.park;
    }
  }

  Color _getRouteColor(TravelMode mode) {
    switch (mode) {
      case TravelMode.driving:
        return Colors.indigo.shade700; // Xanh dương đậm
      case TravelMode.riding:
        return Colors.teal; // Xanh ngọc
      case TravelMode.bicycling:
        return Colors.green.shade600; // Xanh lá
      case TravelMode.walking:
        return Colors.red.shade700; // Đỏ gạch
      case TravelMode.transit:
        return Colors.deepOrange; // Cam
    }
  }

  // Nút la bàn tròn nổi
  Widget _buildFloatingButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    Color? color,
    Color? iconColor,
  }) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color ?? Colors.white.withAlpha(235),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Icon(
              icon,
              color: iconColor ?? Colors.black87,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  // Panel chi tiết thông tin địa điểm (Nâng cao)
  Widget _buildPlaceDetailPanel(MapState state) {
    final place = state.selectedPlace!;
    final isRouteDrawn = state.polylinePoints.isNotEmpty;

    return Hero(
      tag: place.id,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 18,
              offset: const Offset(0, 4),
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Khung hiển thị hình ảnh carousel (ảnh giả lập doanh nghiệp)
            SizedBox(
              height: 100,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  place.imageUrl.startsWith('assets/')
                      ? Image.asset(
                          place.imageUrl,
                          fit: BoxFit.cover,
                        )
                      : Image.network(
                          place.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.image_not_supported, color: Colors.grey),
                            );
                          },
                        ),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.black54, Colors.transparent],
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 16,
                    child: Text(
                      place.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(1, 1))
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 16,
                      child: IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.black54),
                        onPressed: ref.read(mapProvider.notifier).clearSelection,
                      ),
                    ),
                  )
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 2. Rating, Trạng thái & Giờ mở cửa
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        place.rating.toStringAsFixed(1),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: place.isOpenNow ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          place.isOpenNow ? 'ĐANG MỞ CỬA' : 'ĐÃ ĐÓNG CỬA',
                          style: TextStyle(
                            color: place.isOpenNow ? Colors.green.shade700 : Colors.red.shade700,
                            fontWeight: FontWeight.w700,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        place.openingHours,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 3. Địa chỉ & Website
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Colors.grey, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          place.address,
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.language, color: Colors.grey, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          place.website,
                          style: const TextStyle(color: Colors.blue, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 4. Nếu đã bấm "Chỉ đường" -> Hiển thị thanh chọn phương tiện di chuyển
                  if (isRouteDrawn) ...[
                    const Divider(height: 12),
                    _buildTravelModeSelector(state),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer_outlined, color: Colors.deepPurple.shade700, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Thời gian đi dự kiến: ',
                            style: TextStyle(color: Colors.deepPurple.shade900, fontSize: 13),
                          ),
                          Text(
                            state.travelTimeEstimate ?? '',
                            style: TextStyle(
                              color: Colors.deepPurple.shade900,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 5. Khoảng cách (Nếu chưa vẽ đường đi)
                  if (!isRouteDrawn && place.distance != null) ...[
                    Text(
                      'Khoảng cách: ${place.distance!.toStringAsFixed(2)} km',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // 6. Các nút hành động chính (Gọi điện, Street View, Chỉ đường)
                  Row(
                    children: [
                      _buildActionButton(
                        icon: Icons.phone,
                        label: 'Gọi điện',
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Đang kết nối: ${place.phoneNumber}')),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildActionButton(
                        icon: Icons.panorama_horizontal_select,
                        label: '360° View',
                        color: Colors.teal.shade50,
                        textColor: Colors.teal.shade800,
                        iconColor: Colors.teal.shade800,
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => StreetViewDialog(placeName: place.name),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurple,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(isRouteDrawn ? Icons.close : Icons.directions),
                          label: Text(isRouteDrawn ? 'Hủy chỉ đường' : 'Chỉ đường'),
                          onPressed: () {
                            if (isRouteDrawn) {
                              ref.read(mapProvider.notifier).clearSelection();
                            } else {
                              ref.read(mapProvider.notifier).drawRoute(place);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
    Color? textColor,
    Color? iconColor,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: color != null ? BorderSide.none : BorderSide(color: Colors.grey.shade300),
      ),
      icon: Icon(icon, size: 16, color: iconColor ?? Colors.black87),
      label: Text(label, style: TextStyle(color: textColor ?? Colors.black87, fontSize: 13)),
      onPressed: onPressed,
    );
  }

  // Widget chọn Phương tiện di chuyển (Travel Mode)
  Widget _buildTravelModeSelector(MapState state) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildTravelModeButton(TravelMode.driving, Icons.directions_car, state.selectedTravelMode),
        _buildTravelModeButton(TravelMode.riding, Icons.two_wheeler, state.selectedTravelMode),
        _buildTravelModeButton(TravelMode.bicycling, Icons.directions_bike, state.selectedTravelMode),
        _buildTravelModeButton(TravelMode.walking, Icons.directions_walk, state.selectedTravelMode),
        _buildTravelModeButton(TravelMode.transit, Icons.directions_bus, state.selectedTravelMode),
      ],
    );
  }

  Widget _buildTravelModeButton(TravelMode mode, IconData icon, TravelMode currentMode) {
    final isSelected = mode == currentMode;
    return IconButton(
      icon: Icon(icon),
      color: isSelected ? Colors.deepPurple : Colors.grey.shade600,
      style: isSelected
          ? IconButton.styleFrom(
              backgroundColor: Colors.deepPurple.shade50,
            )
          : null,
      onPressed: () {
        ref.read(mapProvider.notifier).changeTravelMode(mode);
      },
    );
  }

  // Hiển thị chi tiết sự cố giao thông
  void _showIncidentDialog(BuildContext context, TrafficIncident incident) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(_getIncidentIcon(incident.type), color: _getIncidentColor(incident.type)),
            const SizedBox(width: 10),
            Text(incident.title),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              incident.description,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Text(
              'Tọa độ: ${incident.latitude.toStringAsFixed(4)}, ${incident.longitude.toStringAsFixed(4)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          )
        ],
      ),
    );
  }

  IconData _getIncidentIcon(IncidentType type) {
    switch (type) {
      case IncidentType.accident:
        return Icons.warning_amber_rounded;
      case IncidentType.construction:
        return Icons.construction_rounded;
      case IncidentType.closed:
        return Icons.block_rounded;
    }
  }

  Color _getIncidentColor(IncidentType type) {
    switch (type) {
      case IncidentType.accident:
        return Colors.red.shade700;
      case IncidentType.construction:
        return Colors.amber.shade700;
      case IncidentType.closed:
        return Colors.red.shade900;
    }
  }
}

// Widget giả lập Street View 360 độ vuốt xoay kèm compass
class StreetViewDialog extends StatefulWidget {
  final String placeName;
  const StreetViewDialog({super.key, required this.placeName});

  @override
  State<StreetViewDialog> createState() => _StreetViewDialogState();
}

class _StreetViewDialogState extends State<StreetViewDialog> {
  double _scrollPosition = 0.5;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Stack(
        children: [
          // 1. Ảnh panorama giả lập hỗ trợ vuốt xoay 360 độ
          GestureDetector(
            onHorizontalDragUpdate: (details) {
              setState(() {
                // Tăng độ nhạy bằng cách chia cho 800 thay vì 1200
                _scrollPosition = (_scrollPosition - details.delta.dx / 800) % 1.0;
              });
            },
            child: Container(
              color: Colors.black,
              width: double.infinity,
              height: double.infinity,
              alignment: Alignment.center,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return FractionallySizedBox(
                    alignment: Alignment(
                      _scrollPosition * 2 - 1,
                      0.0,
                    ),
                    widthFactor: 4.0, // Kéo dãn ngang rộng gấp 4 lần màn hình để tạo cảm giác xoay chân thực
                    heightFactor: 1.0,
                    child: Image.asset(
                      'assets/street_view_360.jpg', // Ảnh panorama đường phố thực tế dạng equirectangular
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Text(
                            'Không thể tải ảnh thực tế từ assets.',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
          
          // 2. La bàn xoay (Compass) giả lập góc trên bên trái
          Positioned(
            top: 40,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  Transform.rotate(
                    angle: _scrollPosition * 2 * 3.1415926535,
                    child: const Icon(Icons.navigation, color: Colors.red, size: 20),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Hướng: ${(360 - _scrollPosition * 360).round()}°',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  )
                ],
              ),
            ),
          ),

          // 3. Nút đóng
          Positioned(
            top: 40,
            right: 20,
            child: FloatingActionButton.small(
              backgroundColor: Colors.white24,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.pop(context),
              child: const Icon(Icons.close),
            ),
          ),

          // 4. Panel thông tin hiển thị ở dưới cùng
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xem hình ảnh thực tế (Street View 360°)',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.placeName,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Icon(Icons.swipe, color: Colors.white70, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Vuốt sang trái hoặc phải để xoay góc nhìn 360 độ',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      )
                    ],
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Widget Search Bar và danh sách gợi ý Autocomplete độc lập giúp giữ vững Compose State gõ tiếng Việt có dấu
class MapSearchBar extends ConsumerStatefulWidget {
  final MapState state;
  final MapController mapController;

  const MapSearchBar({
    super.key,
    required this.state,
    required this.mapController,
  });

  @override
  ConsumerState<MapSearchBar> createState() => _MapSearchBarState();
}

class _MapSearchBarState extends ConsumerState<MapSearchBar> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchTextChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<MapState>(mapProvider, (previous, next) {
      if (previous?.searchQuery != next.searchQuery && next.searchQuery.isEmpty) {
        _searchController.removeListener(_onSearchTextChanged);
        _searchController.clear();
        _searchController.addListener(_onSearchTextChanged);
      }
    });

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withAlpha(245),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Icon(Icons.search, color: Colors.grey),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Tìm kiếm địa điểm, địa chỉ...',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  style: const TextStyle(fontSize: 15, color: Colors.black87),
                  onSubmitted: (value) {
                    ref.read(mapProvider.notifier).setSearchQuery(value);
                  },
                  onChanged: (value) {
                    if (_debounce?.isActive ?? false) _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), () {
                      ref.read(mapProvider.notifier).updateSearchSuggestions(value);
                    });
                  },
                ),
              ),
              if (_searchController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(mapProvider.notifier).setSearchQuery('');
                  },
                ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.mic, color: Colors.deepPurple, size: 22),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tính năng tìm kiếm bằng giọng nói giả lập!')),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _buildCategorySelector(widget.state),
        _buildSuggestionsList(widget.state),
      ],
    );
  }

  Widget _buildCategorySelector(MapState state) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(235),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildCategoryChip(
            category: PlaceCategory.atm,
            label: 'ATM',
            icon: Icons.local_atm,
            isSelected: state.selectedCategory == PlaceCategory.atm,
          ),
          _buildCategoryChip(
            category: PlaceCategory.restaurant,
            label: 'Ăn uống',
            icon: Icons.restaurant,
            isSelected: state.selectedCategory == PlaceCategory.restaurant,
          ),
          _buildCategoryChip(
            category: PlaceCategory.gas,
            label: 'Trạm xăng',
            icon: Icons.local_gas_station,
            isSelected: state.selectedCategory == PlaceCategory.gas,
          ),
          _buildCategoryChip(
            category: PlaceCategory.hospital,
            label: 'Y tế',
            icon: Icons.local_hospital,
            isSelected: state.selectedCategory == PlaceCategory.hospital,
          ),
          _buildCategoryChip(
            category: PlaceCategory.school,
            label: 'Trường học',
            icon: Icons.school,
            isSelected: state.selectedCategory == PlaceCategory.school,
          ),
          _buildCategoryChip(
            category: PlaceCategory.store,
            label: 'Cửa hàng',
            icon: Icons.storefront,
            isSelected: state.selectedCategory == PlaceCategory.store,
          ),
          _buildCategoryChip(
            category: PlaceCategory.publicPlace,
            label: 'Công viên',
            icon: Icons.park,
            isSelected: state.selectedCategory == PlaceCategory.publicPlace,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip({
    required PlaceCategory category,
    required String label,
    required IconData icon,
    required bool isSelected,
  }) {
    final activeColor = _getCategoryColor(category);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
      child: RawChip(
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
        avatar: Icon(
          icon,
          color: isSelected ? Colors.white : activeColor,
          size: 18,
        ),
        backgroundColor: Colors.transparent,
        selectedColor: activeColor,
        selected: isSelected,
        showCheckmark: false,
        onSelected: (_) {
          ref.read(mapProvider.notifier).selectCategory(category);
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? Colors.transparent : Colors.grey.shade300,
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionsList(MapState state) {
    // 1. Xác định danh sách phần tử cần hiển thị trong dropdown
    final List<PlaceModel> itemsToShow = state.searchSuggestions.isNotEmpty
        ? state.searchSuggestions
        : (state.isCategoryDropdownOpen ? state.places : const []);

    if (itemsToShow.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: itemsToShow.length,
        separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (context, index) {
          final place = itemsToShow[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: _getCategoryColor(place.category).withAlpha(30),
              child: Icon(
                _getCategoryIcon(place.category),
                color: _getCategoryColor(place.category),
                size: 18,
              ),
            ),
            title: Text(
              place.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
            ),
            subtitle: Text(
              place.address,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: place.distance != null
                ? Text(
                    '${place.distance!.toStringAsFixed(1)} km',
                    style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
                  )
                : null,
            onTap: () {
              ref.read(mapProvider.notifier).selectPlace(place);
              _searchController.text = place.name;
              widget.mapController.move(LatLng(place.latitude, place.longitude), 15.0);
              FocusScope.of(context).unfocus();
            },
          );
        },
      ),
    );
  }

  Color _getCategoryColor(PlaceCategory category) {
    switch (category) {
      case PlaceCategory.atm: return const Color(0xFF1E88E5);
      case PlaceCategory.restaurant: return const Color(0xFFFB8C00);
      case PlaceCategory.gas: return const Color(0xFF43A047);
      case PlaceCategory.hospital: return const Color(0xFFE53935);
      case PlaceCategory.school: return const Color(0xFF8E24AA);
      case PlaceCategory.store: return const Color(0xFF00ACC1);
      case PlaceCategory.publicPlace: return const Color(0xFF7CB342);
    }
  }

  IconData _getCategoryIcon(PlaceCategory category) {
    switch (category) {
      case PlaceCategory.atm: return Icons.local_atm;
      case PlaceCategory.restaurant: return Icons.restaurant;
      case PlaceCategory.gas: return Icons.local_gas_station;
      case PlaceCategory.hospital: return Icons.local_hospital;
      case PlaceCategory.school: return Icons.school;
      case PlaceCategory.store: return Icons.storefront;
      case PlaceCategory.publicPlace: return Icons.park;
    }
  }
}

