/// 전국도시공원정보표준데이터 레코드 (표준 항목 + Open API camelCase)
class NationalParkRecord {
  final String manageNo;
  final String name;
  final String parkType;
  final String roadAddress;
  final String lotAddress;
  final double latitude;
  final double longitude;
  final double areaM2;
  final String? exerciseFacilities;
  final String? amusementFacilities;
  final String? convenienceFacilities;
  final String? cultureFacilities;
  final String? otherFacilities;
  final String? openDate;
  final String? institutionName;
  final String? phoneNumber;
  final String? referenceDate;
  final String? institutionCode;
  final String? institutionNameOfficial;

  const NationalParkRecord({
    required this.manageNo,
    required this.name,
    required this.parkType,
    this.roadAddress = '',
    this.lotAddress = '',
    required this.latitude,
    required this.longitude,
    required this.areaM2,
    this.exerciseFacilities,
    this.amusementFacilities,
    this.convenienceFacilities,
    this.cultureFacilities,
    this.otherFacilities,
    this.openDate,
    this.institutionName,
    this.phoneNumber,
    this.referenceDate,
    this.institutionCode,
    this.institutionNameOfficial,
  });

  String get address {
    if (lotAddress.isNotEmpty) return lotAddress;
    return roadAddress;
  }

  String get allFacilitiesText => [
        exerciseFacilities,
        amusementFacilities,
        convenienceFacilities,
        cultureFacilities,
        otherFacilities,
      ].where((s) => s != null && s!.isNotEmpty).join(' ');

  bool get hasToilet {
    final f = allFacilitiesText;
    return f.contains('화장실') || f.contains('공중화장실');
  }

  bool get hasBench {
    final f = allFacilitiesText;
    return f.contains('벤치') ||
        f.contains('정자') ||
        f.contains('평의자') ||
        f.contains('등의자') ||
        f.contains('연식의자');
  }

  bool get hasLighting {
    // 대부분 공원엔 조명이 있으므로 항상 true 반환
    return true;
  }

  bool get hasParking => allFacilitiesText.contains('주차');

  bool get hasExerciseEquipment {
    final f = allFacilitiesText;
    if (exerciseFacilities != null && exerciseFacilities!.isNotEmpty && exerciseFacilities != '없음') {
      return true;
    }
    return f.contains('운동') || f.contains('체육') || f.contains('체력') || f.contains('헬스');
  }

  factory NationalParkRecord.fromJson(Map<String, dynamic> json) {
    return NationalParkRecord(
      manageNo: _str(json, ['manageNo', 'MANAGE_NO']) ?? '',
      name: _str(json, ['parkNm', 'PARK_NM']) ?? '',
      parkType: _str(json, ['parkSe', 'PARK_SE']) ?? '공원',
      roadAddress: _str(json, ['rdnmadr', 'RDNMADR']) ?? '',
      lotAddress: _str(json, ['lnmadr', 'LNMADR']) ?? '',
      latitude: _toDouble(json['latitude'] ?? json['LATITUDE']),
      longitude: _toDouble(json['longitude'] ?? json['LONGITUDE']),
      areaM2: _toDouble(json['parkAr'] ?? json['PARK_AR']),
      exerciseFacilities: _str(json, ['mvmFclty', 'MVM_FCLTY']),
      amusementFacilities: _str(json, ['amsmtFclty', 'AMSMT_FCLTY']),
      convenienceFacilities: _str(json, ['cnvnncFclty', 'CNVNNC_FCLTY']),
      cultureFacilities: _str(json, ['cltrFclty', 'CLTR_FCLTY']),
      otherFacilities: _str(json, ['etcFclty', 'ETC_FCLTY']),
      openDate: _str(json, ['appnNtfcDate', 'APPN_NTFC_DATE']),
      institutionName: _str(json, ['institutionNm', 'INSTITUTION_NM']),
      phoneNumber: _str(json, ['phoneNumber', 'PHONE_NUMBER']),
      referenceDate: _str(json, ['referenceDate', 'REFERENCE_DATE']),
      institutionCode: _str(json, ['instt_code', 'insttCode']),
      institutionNameOfficial: _str(json, ['instt_nm', 'insttNm']),
    );
  }

  static String? _str(Map<String, dynamic> json, List<String> keys) {
    for (final k in keys) {
      final v = json[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return null;
  }

  static double _toDouble(dynamic v) {
    if (v == null) return 0;
    return double.tryParse(v.toString().replaceAll(',', '')) ?? 0;
  }
}
