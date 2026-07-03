# 🏃‍♂️ 뚜벅뚜벅 (Ttubuk-Ttubuk)

> **내 기분과 날씨에 맞춘 AI 공원 큐레이션 및 맞춤형 산책 기록 도우미** 🌿

[![Flutter Version](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)](https://flutter.dev/)
[![Backend Supabase](https://img.shields.io/badge/Supabase-Backend-3ECF8E?logo=supabase)](https://supabase.com/)
[![Gemini AI](https://img.shields.io/badge/AI-Gemini_&_Groq-8E75B2?logo=google-gemini)](https://deepmind.google/technologies/gemini/)

### 📥 [Android 앱 다운로드 (APK)](https://drive.google.com/drive/folders/117LmquzpKmVE1SIkFqAMTyw3XKx6n6wb?hl=ko)
![APK Version](https://img.shields.io/badge/APK-v2.1.0-brightgreen?logo=android)
*최신 버전 앱을 다운로드하여 바로 설치해보세요! (최종 업데이트: 2026-06-29)*

## ✨ 주요 기능 (Key Features)

* **🗺️ 실시간 GPS 산책 추적**: 사용자의 이동 경로와 누적 거리를 1km 단위 마일스톤과 함께 직관적으로 기록합니다.
* **🤖 하이브리드 AI 큐레이션**: 
  * 현재 날씨(기온, 맑음/비/눈)와 사용자의 감정 상태를 복합적으로 분석합니다.
  * **Google Gemini 2.5 Flash** 및 **Groq(Llama 3)** 모델을 사용하여 상황에 가장 완벽한 공원과 산책 코스를 추천합니다.
* **🌲 로컬 GIS 데이터 + 공공데이터 매칭**: AI의 추천을 국가 공공데이터 및 Nominatim 기반의 실제 지리 정보(화장실, 벤치 유무 등)와 결합하여 정확도를 극대화했습니다.
* **🎨 모던 UI/UX**: Glassmorphism, 유려한 마이크로 애니메이션, 세련된 다크/라이트 테마를 제공합니다.

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
## 앱 실행하기
위의 APK파일을 다운로드 한 뒤 안드로이드 에뮬레이터나 안드로이드 기기(권장)에 설치하여 앱을 실행하세요

Galaxy 또는 일부 모델에서는 APK파일 설치시 오류 메세지가 표시될 수 있습니다.
오류 발생 시 
설정 = > 보안 및 개인정보 보호 => 보안 위험 자동 차단을 정지 시켜주세요

## 👨‍💻 팀 (Team)
* **Team Asterisk** - *Creating the finest walking experience.*

---
<p align="center">
  <i>Let's take a walk.</i> 🍃
</p>
