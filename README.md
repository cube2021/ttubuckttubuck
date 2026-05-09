# 🏃 뚜벅뚜벅 (Ttubuk-Ttubuk)

나만의 산책 경로를 기록하고, 내 기분과 날씨에 딱 맞는 주변 공원을 추천받는 맞춤형 산책 도우미 앱입니다.

## 주요 기능
- **GPS 산책 기록**: 실시간으로 이동 경로와 거리를 기록합니다. (1km마다 마일스톤 표시)
- **직접 경로 그리기**: 지도를 탭하여 나만의 산책로를 미리 계획해볼 수 있습니다.
- **AI 공원 추천**: 
  - 현재 날씨(맑음, 비, 눈 등) 반영
  - 내 기분(신나요, 평온해요, 지쳐요, 우울해요)에 따른 가중치 분석
  - 내 이동 경로 주변의 최적 공원 리스트업
- **산책 히스토리**: 과거에 걸었던 경로와 통계를 한눈에 확인합니다.
- **OTA 업데이트**: Shorebird를 통해 앱 재설치 없이 항상 최신 기능을 유지합니다.

## 기술 스택
- **Framework**: Flutter
- **Backend**: Supabase (Auth, Database)
- **Map**: flutter_map (OpenStreetMap based)
- **API**: Overpass API (Park data), OpenWeatherMap (Weather data)
- **Deployment**: Shorebird (Code Push)

## 시작하기

### 1. 환경 설정
프로젝트 루트에 `.env` 파일을 생성하고 아래 정보를 입력하세요:
```env
SUPABASE_URL=your_url
SUPABASE_ANON_KEY=your_key
WEATHER_API_KEY=your_weather_api_key
```

### 2. 의존성 설치
```bash
flutter pub get
```

### 3. 앱 실행
```bash
flutter run
```

## 개발자
- **Team Asterisk**
