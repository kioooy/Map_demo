import 'dart:math';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/place_model.dart';

enum AppMapType {
  normal,
  satellite,
  terrain,
}

enum TravelMode {
  driving,   // Ô tô
  riding,    // Xe máy
  bicycling, // Xe đạp
  walking,   // Đi bộ
  transit,   // Xe buýt (Công cộng)
}

enum IncidentType {
  accident,     // Tai nạn
  construction, // Công trình thi công
  closed,       // Đường đóng
}

class TrafficIncident {
  final String id;
  final String title;
  final String description;
  final double latitude;
  final double longitude;
  final IncidentType type;

  TrafficIncident({
    required this.id,
    required this.title,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.type,
  });
}

class MapState {
  final Position? userPosition;
  final List<PlaceModel> places;
  final List<PlaceModel> unfilteredPlaces; // Lưu trữ danh sách gốc
  final PlaceCategory selectedCategory;
  final PlaceModel? selectedPlace;
  final AppMapType mapType;
  final bool isTrafficEnabled;
  final bool isLoading;
  final String? error;
  
  // Tuyến đường chỉ dẫn và thông số di chuyển
  final List<LatLng> polylinePoints;
  final TravelMode selectedTravelMode;
  final String? travelTimeEstimate;

  // Dữ liệu giao thông giả lập
  final List<TrafficIncident> incidents;
  final List<List<LatLng>> redTrafficRoads; // Đoạn kẹt xe nặng (Màu đỏ)
  final List<List<LatLng>> yellowTrafficRoads; // Đoạn kẹt xe nhẹ (Màu vàng)
  final List<LatLng> busStops; // Danh sách trạm xe buýt giả lập cho tuyến xe buýt

  // Từ khóa tìm kiếm
  final String searchQuery;

  const MapState({
    this.userPosition,
    this.places = const [],
    this.unfilteredPlaces = const [],
    this.selectedCategory = PlaceCategory.atm,
    this.selectedPlace,
    this.mapType = AppMapType.normal,
    this.isTrafficEnabled = false,
    this.isLoading = false,
    this.error,
    this.polylinePoints = const [],
    this.selectedTravelMode = TravelMode.driving,
    this.travelTimeEstimate,
    this.incidents = const [],
    this.redTrafficRoads = const [],
    this.yellowTrafficRoads = const [],
    this.busStops = const [],
    this.searchQuery = '',
  });

  MapState copyWith({
    Position? userPosition,
    List<PlaceModel>? places,
    List<PlaceModel>? unfilteredPlaces,
    PlaceCategory? selectedCategory,
    PlaceModel? selectedPlace,
    AppMapType? mapType,
    bool? isTrafficEnabled,
    bool? isLoading,
    String? error,
    List<LatLng>? polylinePoints,
    TravelMode? selectedTravelMode,
    String? travelTimeEstimate,
    List<TrafficIncident>? incidents,
    List<List<LatLng>>? redTrafficRoads,
    List<List<LatLng>>? yellowTrafficRoads,
    List<LatLng>? busStops,
    String? searchQuery,
    bool clearSelectedPlace = false,
    bool clearRoute = false,
  }) {
    return MapState(
      userPosition: userPosition ?? this.userPosition,
      places: places ?? this.places,
      unfilteredPlaces: unfilteredPlaces ?? this.unfilteredPlaces,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      selectedPlace: clearSelectedPlace ? null : (selectedPlace ?? this.selectedPlace),
      mapType: mapType ?? this.mapType,
      isTrafficEnabled: isTrafficEnabled ?? this.isTrafficEnabled,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      polylinePoints: clearRoute ? const [] : (polylinePoints ?? this.polylinePoints),
      selectedTravelMode: selectedTravelMode ?? this.selectedTravelMode,
      travelTimeEstimate: clearRoute ? null : (travelTimeEstimate ?? this.travelTimeEstimate),
      incidents: incidents ?? this.incidents,
      redTrafficRoads: redTrafficRoads ?? this.redTrafficRoads,
      yellowTrafficRoads: yellowTrafficRoads ?? this.yellowTrafficRoads,
      busStops: clearRoute ? const [] : (busStops ?? this.busStops),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

class MapNotifier extends StateNotifier<MapState> {
  MapNotifier() : super(const MapState()) {
    getUserLocation();
  }

  final _uuid = const Uuid();
  final _random = Random();

  Future<String> _getLocalAddressTail(double lat, double lng) async {
    try {
      final client = HttpClient();
      client.userAgent = 'google_maps_demo_app/1.0';
      final request = await client.getUrl(Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&accept-language=vi'));
      final response = await request.close();
      if (response.statusCode == 200) {
        final responseBody = await response.transform(utf8.decoder).join();
        final data = json.decode(responseBody);
        final address = data['address'];
        if (address != null) {
          final suburb = address['suburb'] ?? address['quarter'] ?? address['village'] ?? '';
          final city = address['city'] ?? address['town'] ?? address['state'] ?? '';
          final county = address['county'] ?? '';
          
          List<String> parts = [];
          if (suburb.isNotEmpty) parts.add(suburb.toString());
          if (county.isNotEmpty) parts.add(county.toString());
          if (city.isNotEmpty) parts.add(city.toString());
          
          if (parts.isNotEmpty) {
            return ', ${parts.join(', ')}';
          }
        }
      }
    } catch (e) {
      debugPrint('DEBUG: Error parsing local address: $e');
    }
    return ', Quận Thanh Xuân, Hà Nội';
  }

  Future<void> getUserLocation() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Dịch vụ định vị GPS bị tắt. Vui lòng bật GPS.');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Quyền truy cập vị trí bị từ chối.');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Quyền truy cập vị trí bị từ chối vĩnh viễn.');
      }

      Position? position = await Geolocator.getLastKnownPosition();

      if (position == null) {
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              timeLimit: Duration(seconds: 5),
            ),
          );
        } catch (timeoutErr) {
          position = Position(
            latitude: 10.8751312,
            longitude: 106.8007233,
            timestamp: DateTime.now(),
            accuracy: 0.0,
            altitude: 0.0,
            altitudeAccuracy: 0.0,
            heading: 0.0,
            headingAccuracy: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
          );
          debugPrint('DEBUG: Định vị bị timeout trên Emulator. Sử dụng vị trí mặc định.');
        }
      }

      // Kiểm tra xem vị trí có phải là mặc định của máy ảo Android Emulator ở Mỹ (Mountain View) không
      if ((position.latitude - 37.42).abs() < 0.1 && 
          (position.longitude - (-122.08)).abs() < 0.1) {
        debugPrint('DEBUG: Phát hiện vị trí mặc định Android Emulator (Mỹ). Tự động override về Nhà văn hóa Sinh viên ĐHQG TP.HCM.');
        position = Position(
          latitude: 10.8751312, // Nhà văn hóa Sinh viên ĐHQG TP.HCM
          longitude: 106.8007233,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );
      }

      state = state.copyWith(
        userPosition: position,
        isLoading: false,
      );

      await _generateMockPlaces(position, state.selectedCategory);
      _generateMockTraffic(position);
    } catch (e) {
      final defaultPos = Position(
        latitude: 10.8751312,
        longitude: 106.8007233,
        timestamp: DateTime.now(),
        accuracy: 0.0,
        altitude: 0.0,
        altitudeAccuracy: 0.0,
        heading: 0.0,
        headingAccuracy: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
      );
      state = state.copyWith(
        userPosition: defaultPos,
        isLoading: false,
        error: 'Không thể lấy vị trí GPS: ${e.toString()}. Đã chuyển sang vị trí mặc định.',
      );
      await _generateMockPlaces(defaultPos, state.selectedCategory);
      _generateMockTraffic(defaultPos);
    }
  }

  Future<void> selectCategory(PlaceCategory category) async {
    state = state.copyWith(
      selectedCategory: category,
      clearSelectedPlace: true,
      clearRoute: true,
      searchQuery: '', // Reset ô tìm kiếm khi chuyển tab
    );

    if (state.userPosition != null) {
      await _generateMockPlaces(state.userPosition!, category);
    }
  }

  void selectPlace(PlaceModel place) {
    state = state.copyWith(
      selectedPlace: place,
      clearRoute: true,
    );
  }

  void clearSelection() {
    state = state.copyWith(
      clearSelectedPlace: true,
      clearRoute: true,
    );
  }

  void toggleMapType() {
    AppMapType nextType;
    switch (state.mapType) {
      case AppMapType.normal:
        nextType = AppMapType.satellite;
        break;
      case AppMapType.satellite:
        nextType = AppMapType.terrain;
        break;
      case AppMapType.terrain:
        nextType = AppMapType.normal;
        break;
    }
    state = state.copyWith(mapType: nextType);
  }

  void toggleTraffic() {
    state = state.copyWith(isTrafficEnabled: !state.isTrafficEnabled);
  }

  void changeTravelMode(TravelMode mode) {
    state = state.copyWith(selectedTravelMode: mode);
    if (state.selectedPlace != null) {
      drawRoute(state.selectedPlace!);
    }
  }

  void drawRoute(PlaceModel destination) {
    if (state.userPosition == null) return;

    final start = LatLng(state.userPosition!.latitude, state.userPosition!.longitude);
    final end = LatLng(destination.latitude, destination.longitude);

    List<LatLng> routePoints = [];
    List<LatLng> stops = [];
    routePoints.add(start);

    int steps = 5;
    double offsetScale = 0.0003;

    if (state.selectedTravelMode == TravelMode.walking) {
      steps = 3;
      offsetScale = 0.0001;
    } else if (state.selectedTravelMode == TravelMode.transit) {
      steps = 6;
      offsetScale = 0.0004;
    }

    for (int i = 1; i < steps; i++) {
      double ratio = i / steps;
      double lat = start.latitude + (end.latitude - start.latitude) * ratio;
      double lng = start.longitude + (end.longitude - start.longitude) * ratio;

      double offsetLat = offsetScale * (i % 2 == 0 ? 1 : -1) * (1 - ratio);
      double offsetLng = offsetScale * (i % 2 != 0 ? 1 : -1) * ratio;
      
      final point = LatLng(lat + offsetLat, lng + offsetLng);
      routePoints.add(point);

      if (state.selectedTravelMode == TravelMode.transit && (i == 2 || i == 4)) {
        stops.add(point);
      }
    }

    routePoints.add(end);

    final distance = destination.distance ?? 0.0;
    double speedKmh = 40.0;
    switch (state.selectedTravelMode) {
      case TravelMode.driving:
        speedKmh = 40.0;
        break;
      case TravelMode.riding:
        speedKmh = 30.0;
        break;
      case TravelMode.bicycling:
        speedKmh = 15.0;
        break;
      case TravelMode.walking:
        speedKmh = 5.0;
        break;
      case TravelMode.transit:
        speedKmh = 22.0;
        break;
    }

    double durationHours = distance / speedKmh;
    double durationMinutes = durationHours * 60;
    
    String timeEstimate;
    if (durationMinutes < 1) {
      timeEstimate = 'Dưới 1 phút';
    } else if (durationMinutes < 60) {
      timeEstimate = '${durationMinutes.round()} phút';
    } else {
      int hours = (durationMinutes / 60).floor();
      int mins = (durationMinutes % 60).round();
      timeEstimate = '$hours giờ $mins phút';
    }

    if (state.selectedTravelMode == TravelMode.transit) {
      final busNumber = 10 + _random.nextInt(90);
      timeEstimate = '$timeEstimate (Đón xe buýt số $busNumber)';
    }

    state = state.copyWith(
      polylinePoints: routePoints,
      travelTimeEstimate: timeEstimate,
      busStops: stops,
    );
  }

  Future<void> setSearchQuery(String query) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(
        searchQuery: '',
        places: state.unfilteredPlaces,
      );
      return;
    }

    final lowerQuery = query.toLowerCase();
    
    // Lọc danh sách địa điểm gốc
    final List<PlaceModel> filtered = state.unfilteredPlaces.where((place) {
      return place.name.toLowerCase().contains(lowerQuery) ||
             place.address.toLowerCase().contains(lowerQuery);
    }).toList();

    // Nếu không tìm thấy, sinh động địa điểm giả lập mới tương ứng từ khóa
    if (filtered.isEmpty && state.userPosition != null) {
      final userPos = state.userPosition!;
      final formattedName = query[0].toUpperCase() + query.substring(1);
      final mockNames = [
        '$formattedName Gần Đây',
        'Cửa Hàng $formattedName Tiện Lợi',
        'Trung Tâm $formattedName'
      ];
      
      final addressTail = await _getLocalAddressTail(userPos.latitude, userPos.longitude);
      
      for (int i = 0; i < mockNames.length; i++) {
        double offsetLat = (0.003 + _random.nextDouble() * 0.008) * (_random.nextBool() ? 1 : -1);
        double offsetLng = (0.003 + _random.nextDouble() * 0.008) * (_random.nextBool() ? 1 : -1);

        double placeLat = userPos.latitude + offsetLat;
        double placeLng = userPos.longitude + offsetLng;

        double distanceInMeters = Geolocator.distanceBetween(
          userPos.latitude,
          userPos.longitude,
          placeLat,
          placeLng,
        );

        final imgId = 10 + _random.nextInt(80);

        filtered.add(
          PlaceModel(
            id: _uuid.v4(),
            name: mockNames[i],
            latitude: placeLat,
            longitude: placeLng,
            address: 'Số ${30 + _random.nextInt(100)} Đường Nguyễn Trãi$addressTail',
            category: state.selectedCategory,
            rating: 4.0 + _random.nextDouble(),
            isOpenNow: true,
            phoneNumber: '09${_random.nextInt(90000000) + 10000000}',
            website: 'www.${query.replaceAll(' ', '').toLowerCase()}service.vn',
            openingHours: '08:00 - 22:00 Hằng ngày',
            imageUrl: 'https://picsum.photos/id/$imgId/600/400',
            distance: distanceInMeters / 1000.0,
          ),
        );
      }
    }

    state = state.copyWith(
      searchQuery: query,
      places: filtered,
    );

    // Tự chọn địa điểm đầu tiên tìm thấy
    if (filtered.isNotEmpty) {
      selectPlace(filtered.first);
    }
  }

  void _generateMockTraffic(Position userPos) {
    final lat = userPos.latitude;
    final lng = userPos.longitude;

    final mockIncidents = [
      TrafficIncident(
        id: _uuid.v4(),
        title: 'Va chạm giao thông',
        description: 'Tai nạn nhẹ giữa 2 xe máy. Cản trở làn đường bên phải.',
        latitude: lat + 0.0035,
        longitude: lng + 0.0042,
        type: IncidentType.accident,
      ),
      TrafficIncident(
        id: _uuid.v4(),
        title: 'Công trình thi công',
        description: 'Đang sửa chữa nâng cấp đường ống nước. Làn đường bị thu hẹp.',
        latitude: lat - 0.0051,
        longitude: lng + 0.0028,
        type: IncidentType.construction,
      ),
      TrafficIncident(
        id: _uuid.v4(),
        title: 'Đóng đường tạm thời',
        description: 'Cấm đường phục vụ sự kiện công cộng. Vui lòng đi đường tránh.',
        latitude: lat + 0.0021,
        longitude: lng - 0.0065,
        type: IncidentType.closed,
      ),
    ];

    final List<List<LatLng>> redRoads = [];
    final List<List<LatLng>> yellowRoads = [];

    redRoads.add([
      LatLng(lat + 0.002, lng - 0.004),
      LatLng(lat + 0.002, lng + 0.004),
    ]);

    redRoads.add([
      LatLng(lat - 0.003, lng + 0.001),
      LatLng(lat - 0.001, lng + 0.003),
    ]);

    yellowRoads.add([
      LatLng(lat - 0.004, lng - 0.004),
      LatLng(lat - 0.002, lng - 0.002),
    ]);

    yellowRoads.add([
      LatLng(lat + 0.004, lng + 0.002),
      LatLng(lat + 0.001, lng + 0.005),
    ]);

    state = state.copyWith(
      incidents: mockIncidents,
      redTrafficRoads: redRoads,
      yellowTrafficRoads: yellowRoads,
    );
  }

  Future<void> _generateMockPlaces(Position userPos, PlaceCategory category) async {
    List<PlaceModel> mockList = [];
    final names = _getCategoryNames(category);
    final streets = [
      'Nguyễn Trãi',
      'Trần Hưng Đạo',
      'Phố Huế',
      'Lê Lợi',
      'Cách Mạng Tháng Tám',
      'Nguyễn Thị Minh Khai',
      'Kim Mã',
      'Lê Duẩn',
      'Nguyễn Huệ',
      'Độc Lập',
      'Hai Bà Trưng',
      'Phan Chu Trinh'
    ];

    final addressTail = await _getLocalAddressTail(userPos.latitude, userPos.longitude);
    final categoryColorName = category.name;

    for (int i = 0; i < names.length; i++) {
      double offsetLat = (0.003 + _random.nextDouble() * 0.012) * (_random.nextBool() ? 1 : -1);
      double offsetLng = (0.003 + _random.nextDouble() * 0.012) * (_random.nextBool() ? 1 : -1);

      double placeLat = userPos.latitude + offsetLat;
      double placeLng = userPos.longitude + offsetLng;

      double distanceInMeters = Geolocator.distanceBetween(
        userPos.latitude,
        userPos.longitude,
        placeLat,
        placeLng,
      );

      final openHour = 7 + _random.nextInt(2);
      final closeHour = 21 + _random.nextInt(2);
      final imgId = 10 + _random.nextInt(80);

      mockList.add(
        PlaceModel(
          id: _uuid.v4(),
          name: names[i],
          latitude: placeLat,
          longitude: placeLng,
          address: 'Số ${10 + _random.nextInt(150)} Đường ${streets[_random.nextInt(streets.length)]}$addressTail',
          category: category,
          rating: 3.8 + _random.nextDouble() * 1.2,
          isOpenNow: _random.nextBool(),
          phoneNumber: '09${_random.nextInt(90000000) + 10000000}',
          website: 'www.${categoryColorName}service${i + 1}.vn',
          openingHours: '0$openHour:00 - $closeHour:00 Hằng ngày',
          imageUrl: 'https://picsum.photos/id/$imgId/600/400',
          distance: distanceInMeters / 1000.0,
        ),
      );
    }

    mockList.sort((a, b) => (a.distance ?? 0.0).compareTo(b.distance ?? 0.0));

    state = state.copyWith(
      places: mockList,
      unfilteredPlaces: mockList, // Lưu trữ danh sách gốc
    );
  }

  List<String> _getCategoryNames(PlaceCategory category) {
    switch (category) {
      case PlaceCategory.atm:
        return [
          'ATM Techcombank Chi Nhánh Trung Tâm',
          'ATM Vietcombank 24/7',
          'ATM BIDV Phòng Giao Dịch Số 4',
          'ATM Agribank Điểm Rút Tiền Nhanh',
          'ATM VietinBank Cạnh Trạm Bus'
        ];
      case PlaceCategory.restaurant:
        return [
          'Phở Bò Gia Truyền Nam Định',
          'Bún Chả Cự Đà Gia Truyền',
          'Cơm Tấm Sườn Bì Chả Sài Gòn',
          'Pizza & Pasta Ý Cổ Điển',
          'Nhà Hàng Lẩu Nướng BBQ Buffet'
        ];
      case PlaceCategory.gas:
        return [
          'Trạm Xăng Petrolimex Số 18',
          'Cửa Hàng Xăng Dầu PV Oil Việt Nam',
          'Trạm Bán Lẻ Xăng Dầu Quân Đội',
          'Trạm Xăng Hào Nam Petrol',
          'Trạm Xăng MIPEC Hà Đông'
        ];
      case PlaceCategory.hospital:
        return [
          'Bệnh Viện Đa Khoa Trung Tâm',
          'Phòng Khám Đa Khoa Quốc Tế CarePlus',
          'Trung Tâm Y Tế Quận Dự Phòng',
          'Phòng Khám Tai Mũi Họng Nhi Đồng',
          'Nhà Thuốc & Phòng Khám Đa Khoa An Tâm'
        ];
      case PlaceCategory.school:
        return [
          'Trường Tiểu Học Nguyễn Trãi',
          'Trường THPT Chuyên Hà Nội - Amsterdam',
          'Đại Học Bách Khoa Hà Nội',
          'Trường THCS Lê Quý Đôn',
          'Trường Mầm Non Họa Mi Cổ Tích'
        ];
      case PlaceCategory.store:
        return [
          'Siêu Thị WinMart+ Tiện Lợi',
          'Trung Tâm Thương Mại Lotte Center',
          'Cửa Hàng Thiết Bị Công Nghệ TechZone',
          'Nhà Sách Trí Tuệ Nguyễn Văn Cừ',
          'Cửa Hàng Tiện Ích Circle K 24/7'
        ];
      case PlaceCategory.publicPlace:
        return [
          'Công Viên Thống Nhất Trung Tâm',
          'Vườn Hoa Lý Thái Tổ Hồ Gươm',
          'Nhà Hát Lớn Thành Phố',
          'Quảng Trường Cách Mạng Tháng Tám',
          'Hồ Ngọc Khánh Địa Điểm Thư Giãn'
        ];
    }
  }
}

final mapProvider = StateNotifierProvider<MapNotifier, MapState>((ref) {
  return MapNotifier();
});
