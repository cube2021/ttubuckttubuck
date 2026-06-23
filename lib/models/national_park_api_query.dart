/// 전국도시공원정보표준데이터 Open API 요청변수
/// https://www.data.go.kr/data/15012890/standard.do#tab_layer_open
class NationalParkApiQuery {
  final int pageNo;
  final int numOfRows;
  final String type;
  final String? manageNo;
  final String? parkNm;
  final String? parkSe;
  final String? rdnmadr;
  final String? lnmadr;
  final String? insttCode;
  final String? insttNm;

  const NationalParkApiQuery({
    this.pageNo = 1,
    this.numOfRows = 100,
    this.type = 'json',
    this.manageNo,
    this.parkNm,
    this.parkSe,
    this.rdnmadr,
    this.lnmadr,
    this.insttCode,
    this.insttNm,
  });

  /// 공공데이터포털 일반 인증키는 Uri.replace 재인코딩 시 400이 날 수 있어
  /// 쿼리 문자열을 직접 조합합니다.
  String toRequestUrl(String baseUrl, String serviceKey) {
    final buf = StringBuffer(baseUrl);
    buf.write('?serviceKey=$serviceKey');
    buf.write('&pageNo=$pageNo');
    buf.write('&numOfRows=${numOfRows.clamp(1, 1000)}');
    buf.write('&type=$type');
    void append(String key, String? value) {
      if (value != null && value.trim().isNotEmpty) {
        buf.write('&$key=${Uri.encodeQueryComponent(value.trim())}');
      }
    }
    append('MANAGE_NO', manageNo);
    append('PARK_NM', parkNm);
    append('PARK_SE', parkSe);
    append('RDNMADR', rdnmadr);
    append('LNMADR', lnmadr);
    append('instt_code', insttCode);
    append('instt_nm', insttNm);
    return buf.toString();
  }
}

/// API 응답 메타 (페이징)
class NationalParkApiPage {
  final List<Map<String, dynamic>> items;
  final int totalCount;
  final String resultCode;
  final String? resultMsg;

  const NationalParkApiPage({
    required this.items,
    required this.totalCount,
    required this.resultCode,
    this.resultMsg,
  });

  bool get isSuccess => resultCode == '00';
}
