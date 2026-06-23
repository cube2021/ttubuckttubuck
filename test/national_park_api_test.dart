import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:latlong2/latlong.dart';
import 'package:project_achasan/models/national_park_record.dart';
import 'package:project_achasan/services/national_park_api_service.dart';
import 'package:project_achasan/services/config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('전국도시공원정보표준데이터 API', () {
    setUpAll(() async {
      await dotenv.load(fileName: '.env');
    });

    test('camelCase JSON 파싱', () {
      final rec = NationalParkRecord.fromJson({
        'manageNo': '11740-00072',
        'parkNm': '어린이대공원',
        'parkSe': '근린공원',
        'lnmadr': '서울특별시 광진구 능동',
        'latitude': '37.548',
        'longitude': '127.077',
        'parkAr': '202360',
        'cnvnncFclty': '화장실,벤치',
        'mvmFclty': '산책로',
        'appnNtfcDate': '1973-05-05',
      });

      expect(rec.name, '어린이대공원');
      expect(rec.parkType, '근린공원');
      expect(rec.latitude, closeTo(37.548, 0.001));
      expect(rec.hasToilet, isTrue);
      expect(rec.hasBench, isTrue);
    });

    // flutter test는 HttpClient를 모킹해 실제 네트워크가 차단됩니다.
    // 실제 API 연동은 앱 실행 후 추천 탭에서 확인하세요.
  });
}
