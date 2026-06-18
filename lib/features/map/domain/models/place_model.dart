enum PlaceCategory {
  all,
  atm,
  restaurant,
  gas,
  hospital,
  school,
  store,
  publicPlace,
}

class PlaceModel {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String address;
  final PlaceCategory category;
  final double rating;
  final bool isOpenNow;
  final String phoneNumber;
  final double? distance;
  final String imageUrl;
  final String website;
  final String openingHours;

  PlaceModel({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.category,
    required this.rating,
    required this.isOpenNow,
    required this.phoneNumber,
    required this.imageUrl,
    required this.website,
    required this.openingHours,
    this.distance,
  });

  PlaceModel copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    String? address,
    PlaceCategory? category,
    double? rating,
    bool? isOpenNow,
    String? phoneNumber,
    String? imageUrl,
    String? website,
    String? openingHours,
    double? distance,
  }) {
    return PlaceModel(
      id: id ?? this.id,
      name: name ?? this.name,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
      category: category ?? this.category,
      rating: rating ?? this.rating,
      isOpenNow: isOpenNow ?? this.isOpenNow,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      imageUrl: imageUrl ?? this.imageUrl,
      website: website ?? this.website,
      openingHours: openingHours ?? this.openingHours,
      distance: distance ?? this.distance,
    );
  }
}
