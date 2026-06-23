# 🏃‍♂️ 뚜벅뚜벅 (Ttubuk-Ttubuk)

> **내 기분과 날씨에 맞춘 AI 공원 큐레이션 및 맞춤형 산책 기록 도우미** 🌿

[![Flutter Version](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)](https://flutter.dev/)
[![Backend Supabase](https://img.shields.io/badge/Supabase-Backend-3ECF8E?logo=supabase)](https://supabase.com/)
[![Gemini AI](https://img.shields.io/badge/AI-Gemini_&_Groq-8E75B2?logo=google-gemini)](https://deepmind.google/technologies/gemini/)

## ✨ 주요 기능 (Key Features)

* **🗺️ 실시간 GPS 산책 추적**: 사용자의 이동 경로와 누적 거리를 1km 단위 마일스톤과 함께 직관적으로 기록합니다.
* **🤖 하이브리드 AI 큐레이션**: 
  * 현재 날씨(기온, 맑음/비/눈)와 사용자의 감정 상태를 복합적으로 분석합니다.
  * **Google Gemini 2.5 Flash** 및 **Groq(Llama 3)** 모델을 사용하여 상황에 가장 완벽한 공원과 산책 코스를 추천합니다.
* **🌲 로컬 GIS 데이터 + 공공데이터 매칭**: AI의 추천을 국가 공공데이터 및 Nominatim 기반의 실제 지리 정보(화장실, 벤치 유무 등)와 결합하여 정확도를 극대화했습니다.
* **🎨 모던 UI/UX**: Glassmorphism, 유려한 마이크로 애니메이션, 세련된 다크/라이트 테마를 제공합니다.
* **⚡ Shorebird OTA 업데이트**: 앱 스토어 심사 대기 없이 실시간으로 최신 기능과 버그 픽스를 푸시받을 수 있습니다.

---

## 🛠️ 기술 스택 (Tech Stack)

### Frontend
* **Framework**: Flutter (`>=3.0.0`)
* **State Management**: Provider
* **Map Engine**: `flutter_map` (OpenStreetMap 기반)
* **Design**: `google_fonts`, `lucide_icons_flutter`, `glassmorphism`

### Backend & AI
* **Database & Auth**: Supabase
* **AI Models**: Google Generative AI (Gemini), Groq API (Fallback)
* **Location APIs**: OpenStreetMap, Geolocator, 공공데이터 포털 API

### DevOps
* **Code Push**: Shorebird

---

## 🚀 시작하기 (Getting Started)

### 1. 환경 변수 설정
프로젝트 루트 디렉토리에 `.env` 파일을 생성하고 아래의 키를 채워주세요.
```env
SUPABASE_URL=your_supabase_project_url
SUPABASE_ANON_KEY=your_supabase_anon_key
WEATHER_API_KEY=your_openweather_api_key
GEMINI_API_KEY=your_gemini_api_key
GROQ_API_KEY=your_groq_api_key
```

### 2. 패키지 설치
```bash
flutter pub get
```

### 3. 프로젝트 실행
```bash
# 디버그 모드 실행
flutter run

# 안드로이드 릴리즈 빌드 (Shorebird 활용 시)
shorebird release android
```

---

## 👨‍💻 팀 (Team)
* **Team Asterisk** - *Creating the finest walking experience.*

---
<p align="center">
  <i>Let's take a walk.</i> 🍃
</p>
