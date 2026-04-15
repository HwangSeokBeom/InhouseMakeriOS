# InhouseMaker CI/CD

## 개요

이 저장소는 `dev / staging / main` 브랜치 전략을 기준으로 iOS 앱과 NestJS 서버를 분리된 파이프라인으로 운영하도록 정리했다.

- `dev`: 일상 개발과 PR 검증 기준 브랜치
- `staging`: 스테이징 릴리즈와 내부 검증 기준 브랜치
- `main`: 운영 릴리즈 기준 브랜치

워크플로우는 GitHub Actions 기준으로 나뉜다.

- iOS CI: PR / push 시 `InhouseMakeriOS-Dev` scheme 빌드 및 테스트
- iOS Staging Release: `staging` push 시 Fastlane으로 TestFlight 업로드
- iOS Production Release: `main` push 시 Fastlane으로 App Store Connect 업로드
- Server CI: NestJS lint / typecheck / build / test
- Server Staging Deploy: `staging` push 시 EC2 staging 서버 배포
- Server Production Deploy: `main` push 시 EC2 production 서버 배포

## 권장 브랜치 전략

- `feature/*` -> `dev`
- `dev` -> `staging`
- `staging` -> `main`
- 운영 긴급 수정은 `hotfix/*` 를 `main` 에서 분기
- `hotfix/*` -> `main` 머지 후 동일 변경을 `staging`, `dev` 로 역병합

운영 브랜치에서 직접 기능 개발하지 않는 것을 기본 원칙으로 잡는다.

## iOS 구조

### Scheme / Configuration

공유 scheme 3개를 추가했다.

- `InhouseMakeriOS-Dev`
- `InhouseMakeriOS-Staging`
- `InhouseMakeriOS-Production`

빌드 configuration 3개를 사용한다.

- `Dev`
- `Staging`
- `Production`

### xcconfig 계층

설정 파일은 [InhouseMakeriOS/Configurations](/Users/hwangseokbeom/Documents/GitHub/InhouseIOS/InhouseMakeriOS/Configurations) 에 있다.

- `App.Base.xcconfig`: 공통 앱 설정
- `App.Shared.xcconfig`: 공통 + 로컬 secrets include
- `App.Dev.xcconfig`: dev 환경값
- `App.Staging.xcconfig`: staging 환경값
- `App.Production.xcconfig`: production 환경값
- `UnitTests.*`, `UITests.*`: 테스트 타깃용 bundle id / host 설정
- `Environment.secrets.template.xcconfig`: 로컬 개발용 템플릿

로컬 개발에서는 아래처럼 사용한다.

1. [Environment.secrets.template.xcconfig](/Users/hwangseokbeom/Documents/GitHub/InhouseIOS/InhouseMakeriOS/Configurations/Environment.secrets.template.xcconfig) 를 복사해서 `InhouseMakeriOS/Configurations/Local/Environment.secrets.xcconfig` 생성
2. `INHOUSE_API_BASE_URL`, `INHOUSE_GOOGLE_CLIENT_ID`, `INHOUSE_GOOGLE_REVERSED_CLIENT_ID`, `INHOUSE_DEVELOPMENT_TEAM` 입력

현재 분리된 값은 `Info.plist` 에서 build setting 으로 주입된다.

- `APP_ENV`
- `API_BASE_URL`
- `APP_DISPLAY_NAME`
- `GOOGLE_CLIENT_ID`
- `GOOGLE_REVERSED_CLIENT_ID`

### 번들 ID 전략

- app target: 모든 환경에서 `com.hwb.InhouseIOS`
- 테스트 타깃: 충돌 방지를 위해 별도 bundle id 유지

### Widget / Extension 확장 방법

현재 저장소에는 Widget/Extension 타깃이 없지만, 추가할 때는 다음 원칙만 지키면 된다.

- 새 타깃에도 `Dev / Staging / Production` configuration 추가
- 해당 타깃 전용 xcconfig 를 만들어 같은 suffix 규칙 적용
- staging / production scheme 의 Build Action 에 새 타깃 포함
- provisioning profile 이 extension bundle id 까지 커버하는지 확인

## Fastlane

Fastlane 파일은 [fastlane](/Users/hwangseokbeom/Documents/GitHub/InhouseIOS/fastlane) 아래에 있다.

- `beta_staging`: staging archive + TestFlight 업로드
- `release_production`: production archive + App Store Connect 업로드

현재 릴리즈 lane 은 `App Store Connect API Key + Xcode automatic signing` 조합으로 설계했다.

- `APP_STORE_CONNECT_API_KEY_CONTENT` 를 임시 `.p8` 파일로 생성
- `gym` 에 `-allowProvisioningUpdates` 를 넘겨 archive 수행
- release workflow 는 `IOS_FASTLANE_APP_IDENTIFIER` 를 `com.hwb.InhouseIOS` 로 고정해서 App Store Connect 대상 앱을 명시
- staging 은 `upload_to_testflight`
- production 은 `upload_to_app_store`

향후 `fastlane match` 로 옮기려면 다음 값을 추가하고 lane 안에서 `match(...)` 를 `gym` 앞에 넣으면 된다.

- `MATCH_PASSWORD`
- `MATCH_GIT_URL`
- 필요 시 `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`

### 버전 / 빌드 번호 전략

- `MARKETING_VERSION`: 사람이 관리
- `CURRENT_PROJECT_VERSION`: CI 에서 자동 증가

현재 build number 는 기본적으로 `github.run_number` 를 사용하고, CI 외 실행에서는 timestamp fallback 을 사용한다.

## 서버 구조

서버 관련 기본 골격은 [server](/Users/hwangseokbeom/Documents/GitHub/InhouseIOS/server) 아래에 있다.

- NestJS 기본 앱
- `/health` endpoint
- `.env`, `.env.staging`, `.env.production` 구조
- PM2 ecosystem
- 배포 스크립트

중요:

- 이 저장소에는 방금 추가한 최소 Nest 골격만 있다.
- 실제 서비스 모듈을 붙이기 전까지는 health endpoint 중심의 최소 서버만 동작한다.
- `package-lock.json` 은 아직 커밋되지 않았으므로, 첫 의존성 확정 후 반드시 생성해서 커밋해야 한다.

### PM2 프로세스명

- `inhouse-maker-server-staging`
- `inhouse-maker-server-production`

### 배포 스크립트

스크립트는 [scripts/server](/Users/hwangseokbeom/Documents/GitHub/InhouseIOS/scripts/server) 아래에 있다.

- `deploy-staging.sh`
- `deploy-production.sh`
- `deploy-common.sh`
- `health-check.sh`

배포 순서는 아래와 같다.

1. `git fetch / checkout / pull --ff-only`
2. `npm ci` 또는 lockfile 없으면 `npm install`
3. `prisma generate` 존재 시 수행
4. `npm run build`
5. `prisma migrate deploy` 존재 시 수행
6. `pm2 reload` 또는 최초 `pm2 start`
7. health check

실패 시 코드 레벨 롤백을 시도한다. 단, Prisma migration 은 자동 롤백하지 않는다. 운영에서는 backward-compatible migration 을 먼저 배포하는 방식으로 운영하는 것이 안전하다.

## GitHub Actions 요약

### iOS

- [ios-ci.yml](/Users/hwangseokbeom/Documents/GitHub/InhouseIOS/.github/workflows/ios-ci.yml): PR / push 빌드 검증
- [ios-staging-release.yml](/Users/hwangseokbeom/Documents/GitHub/InhouseIOS/.github/workflows/ios-staging-release.yml): `staging` 전용 TestFlight 릴리즈
- [ios-production-release.yml](/Users/hwangseokbeom/Documents/GitHub/InhouseIOS/.github/workflows/ios-production-release.yml): `main` 전용 App Store Connect 릴리즈

### 서버

- [server-ci.yml](/Users/hwangseokbeom/Documents/GitHub/InhouseIOS/.github/workflows/server-ci.yml): lint / typecheck / build / test
- [server-staging-deploy.yml](/Users/hwangseokbeom/Documents/GitHub/InhouseIOS/.github/workflows/server-staging-deploy.yml): `staging` 전용 EC2 배포
- [server-production-deploy.yml](/Users/hwangseokbeom/Documents/GitHub/InhouseIOS/.github/workflows/server-production-deploy.yml): `main` 전용 EC2 배포

모든 release/deploy workflow 에는 다음 안전장치를 넣었다.

- 브랜치별 트리거 분리
- job level branch guard
- shell level branch guard
- concurrency 로 중복 배포 취소
- `workflow_dispatch` 지원

## 필요한 GitHub Secrets

### iOS

- `IOS_DEVELOPMENT_TEAM`
- `IOS_API_BASE_URL_STAGING`
- `IOS_API_BASE_URL_PRODUCTION`
- `IOS_GOOGLE_CLIENT_ID_STAGING`
- `IOS_GOOGLE_CLIENT_ID_PRODUCTION`
- `IOS_GOOGLE_REVERSED_CLIENT_ID_STAGING`
- `IOS_GOOGLE_REVERSED_CLIENT_ID_PRODUCTION`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_CONTENT`

선택:

- `APP_STORE_CONNECT_TEAM_ID`
- `MATCH_PASSWORD`
- `MATCH_GIT_URL`
- `FASTLANE_APPLE_APPLICATION_SPECIFIC_PASSWORD`

`IOS_FASTLANE_APP_IDENTIFIER` 는 secret 이 아니라 release 실행 시 Fastlane에 넘기는 app identifier override 값이다.

- staging / production 공통: `com.hwb.InhouseIOS`

### 서버

- `EC2_HOST_STAGING`
- `EC2_HOST_PRODUCTION`
- `EC2_PORT_STAGING`
- `EC2_PORT_PRODUCTION`
- `EC2_USER`
- `EC2_SSH_KEY`
- `SERVER_APP_DIR_STAGING`
- `SERVER_APP_DIR_PRODUCTION`
- `SERVER_HEALTHCHECK_URL_STAGING`
- `SERVER_HEALTHCHECK_URL_PRODUCTION`

`SERVER_APP_DIR_*` 는 EC2 에서 이 저장소가 clone 된 루트 경로다.

예:

- `/srv/inhouse-maker`
- `/home/ec2-user/apps/inhouse-maker`

## GitHub Environments 권장값

아래 이름으로 GitHub Environments 를 만들어 secrets 를 나누는 것을 권장한다.

- `ios-staging`
- `ios-production`
- `server-staging`
- `server-production`

## 로컬 수동 실행

### iOS CI 확인

```bash
xcodebuild test \
  -project InhouseMakeriOS.xcodeproj \
  -scheme InhouseMakeriOS-Dev \
  -configuration Dev \
  -destination "platform=iOS Simulator,name=iPhone 17"
```

### Fastlane staging 릴리즈

```bash
bundle install
export IOS_FASTLANE_APP_IDENTIFIER="com.hwb.InhouseIOS"
export IOS_API_BASE_URL_STAGING="https://staging-api.example.com" # TODO: 실제 값으로 교체
export IOS_GOOGLE_CLIENT_ID_STAGING="TODO"
export IOS_GOOGLE_REVERSED_CLIENT_ID_STAGING="TODO"
export IOS_DEVELOPMENT_TEAM="TODO"
export APP_STORE_CONNECT_API_KEY_ID="TODO"
export APP_STORE_CONNECT_ISSUER_ID="TODO"
export APP_STORE_CONNECT_API_KEY_CONTENT="TODO"
bundle exec fastlane beta_staging
```

### 서버 로컬 실행

```bash
cd server
npm install
cp .env.example .env
npm run start:dev
```

### 서버 수동 배포

EC2 에서 저장소 루트 기준으로 실행한다.

```bash
bash scripts/server/deploy-staging.sh
bash scripts/server/deploy-production.sh
```

## 최초 세팅 체크리스트

1. iOS staging / production bundle identifier 를 Apple Developer 에 등록
2. Google Sign-In client id 와 reversed client id 를 환경별로 발급
3. App Store Connect API Key 생성
4. EC2 에 저장소 clone
5. EC2 에 `pm2` 설치
6. `server/.env.staging`, `server/.env.production` 생성
7. `server/package-lock.json` 생성 후 커밋
8. 필요한 경우 Prisma schema 추가

## 장애 시 점검 포인트

### iOS

- release workflow 가 바로 실패하면 secrets 누락인지 먼저 확인
- signing 실패면 `IOS_DEVELOPMENT_TEAM`, bundle id, Apple Developer 권한 확인
- Google 로그인 URL scheme 오작동이면 `GOOGLE_REVERSED_CLIENT_ID` 값 확인
- API 통신이 dev URL 로 붙으면 생성된 CI xcconfig 와 `Info.plist` 값 주입 여부 확인

### 서버

- `git pull --ff-only` 실패면 서버 작업 트리가 dirty 상태인지 확인
- `npm ci` 실패면 lockfile 유무와 Node 버전 확인
- Prisma 단계 실패면 DB 접속 값과 migration 상태 확인
- PM2 reload 후 health check 실패면 `.env.staging` / `.env.production` 의 `PORT`, `SERVER_HEALTHCHECK_URL` 확인
- 롤백 후에도 장애가 남으면 DB migration 이 forward-only 였는지 확인

## 운영 권장 방식

- iOS 는 staging 에서 TestFlight 검수 후 `staging -> main` 으로 승격
- 서버는 staging 과 production EC2 를 분리 운영
- production deploy 는 squash merge 또는 release PR 기준으로만 허용
- `main` 직접 push 는 막고 branch protection 으로 강제
- DB migration 은 production 코드보다 먼저 호환 가능한 형태로 배포
