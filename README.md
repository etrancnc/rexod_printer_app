# REXOD RX830-V120 프린터 제어 애플리케이션 (Flutter Windows)

현재 usb 인식만 가능하면 프린터는 되지 않고 있다 

C# Windows Forms 기반의 REXOD 프린터 샘플 애플리케이션을 Flutter Windows 데스크톱 애플리케이션으로 변환한 프로젝트입니다.

## 주요 기능

### 연결 관리
- COM 포트 선택 (COM1-COM7, USB)
- Baud Rate 설정 (9600-115200)
- Flow Control 설정 (None, Xon/Xoff, Hardware)
- 실시간 연결 상태 표시

### 프린터 기능
- **텍스트 인쇄**: 다양한 텍스트 속성 (일반, 더블 너비, 더블 높이, 굵게)
- **바코드 인쇄**: CODE128 바코드 지원
- **QR코드 인쇄**: 다양한 크기의 QR코드 생성
- **PDF417 인쇄**: 2D 바코드 지원
- **샘플 영수증 인쇄**: 완전한 영수증 형태의 샘플 출력
- **프린터 상태 확인**: 용지 상태, 오류 상태 등 실시간 모니터링
- **프린터 재부팅**: 프린터 시스템 재시작

### 사용자 인터페이스
- Material Design 3 기반의 현대적인 UI
- 반응형 레이아웃으로 다양한 화면 크기 지원
- 실시간 상태 피드백 및 알림 시스템
- 영수증 미리보기 기능

## 기술 스택

- **Framework**: Flutter 3.24.3
- **Platform**: Windows Desktop
- **State Management**: Provider
- **Serial Communication**: flutter_libserialport
- **UI Components**: Material Design 3, Material Design Icons

## 설치 및 실행 방법

### 1. 개발 환경 설정

#### Flutter SDK 설치
1. [Flutter 공식 사이트](https://flutter.dev/docs/get-started/install/windows)에서 Flutter SDK 다운로드
2. 압축 해제 후 PATH 환경 변수에 `flutter/bin` 경로 추가
3. 명령 프롬프트에서 `flutter doctor` 실행하여 설치 확인

#### Visual Studio 설치 (Windows 빌드용)
1. Visual Studio 2022 Community 설치
2. "C++를 사용한 데스크톱 개발" 워크로드 선택
3. Windows 10/11 SDK 포함

#### Windows 데스크톱 지원 활성화
```bash
flutter config --enable-windows-desktop
```

### 2. 프로젝트 실행

#### 개발 모드 실행
```bash
# 프로젝트 디렉토리로 이동
cd rexod_printer_app

# 패키지 설치
flutter pub get

# 개발 모드 실행
flutter run -d windows
```

#### 릴리즈 빌드
```bash
# Windows 실행 파일 빌드
flutter build windows --release

# 빌드된 파일 위치: build/windows/x64/runner/Release/
```

### 3. 배포

빌드 완료 후 `build/windows/x64/runner/Release/` 폴더의 모든 파일을 대상 컴퓨터에 복사하여 실행할 수 있습니다.

## 프로젝트 구조

```
lib/
├── main.dart                 # 메인 애플리케이션
├── models/                   # 데이터 모델
│   ├── printer_config.dart   # 프린터 설정 모델
│   └── printer_status.dart   # 프린터 상태 모델
└── services/                 # 비즈니스 로직
    └── printer_service.dart  # 프린터 제어 서비스
```

## 주요 클래스

### PrinterService
프린터 연결 및 제어를 담당하는 메인 서비스 클래스
- 시리얼 포트 통신 관리
- ESC/POS 명령어 처리
- 상태 관리 및 알림

### PrinterConfig
프린터 연결 설정 정보를 담는 모델 클래스
- 포트, Baud Rate, Flow Control 설정
- 연결 상태 관리

### PrinterStatus
프린터 상태 정보를 담는 모델 클래스
- 오류 및 경고 상태
- 기계 타입 및 버전 정보

## ESC/POS 명령어 지원

### 기본 명령어
- 프린터 초기화
- 텍스트 인쇄 (정렬, 크기, 스타일)
- 줄 바꿈 및 용지 자르기

### 바코드/QR코드
- CODE128 바코드
- QR코드 (다양한 크기)
- PDF417 2D 바코드

### 프린터 제어
- 상태 확인
- 재부팅
- 직접 명령어 전송

## 실제 프린터 연동

이 애플리케이션은 실제 REXOD 프린터와 시리얼 포트를 통해 통신할 수 있습니다:

1. **하드웨어 연결**: 프린터를 COM 포트 또는 USB로 컴퓨터에 연결
2. **포트 설정**: 애플리케이션에서 올바른 포트와 통신 설정 선택
3. **연결**: '연결' 버튼을 클릭하여 프린터와 연결
4. **테스트**: 각종 인쇄 기능을 테스트하여 정상 작동 확인

## 문제 해결

### 연결 오류
- 프린터가 올바르게 연결되었는지 확인
- 다른 애플리케이션에서 포트를 사용하고 있지 않은지 확인
- 프린터 드라이버가 설치되었는지 확인

### 빌드 오류
- Flutter SDK가 최신 버전인지 확인
- Visual Studio가 올바르게 설치되었는지 확인
- `flutter clean` 후 다시 빌드 시도

- **원본 C# 버전**: REXOD 프린터 샘플 애플리케이션
- **개발 일자**: 2025년 8월
