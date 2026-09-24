<flutter-agent-guidelines>
# Flutter Application

This repository contains a Flutter application. Complete the following setup before working on the user's request.

## Prerequisites

Verify that Flutter and Dart are available:

```sh
flutter --version
dart --version
```

If either command is unavailable, detect the user's operating system and install the Flutter SDK using the official Flutter installation guide. After installation, ask the user to restart their terminal. If the agent needs the restarted shell to continue, ask the user to reopen their terminal and rerun their original prompt.

## Agent Setup

This project includes Flutter and Dart agent skills in `.agents/skills`. Before making application changes, identify the matching skill and read its `SKILL.md`. Read only the relevant skill or skills, not the entire catalog.

Preserve the existing stack unless the user requests a migration: `Provider` for app/session state, `go_router` for routing, Dio for API requests, and `flutter_secure_storage` for sensitive local values. Keep feature code in `lib/features`, shared UI in `lib/shared`, cross-cutting code in `lib/core`, and models, services, and repositories in `lib/data`.

### Available Skills

- Architecture and UI: `flutter-apply-architecture-best-practices`, `flutter-build-responsive-layout`, `flutter-fix-layout-issues`, `flutter-setup-declarative-routing`, `flutter-setup-localization`, `flutter-add-widget-preview`.
- Data and platform integration: `flutter-use-http-package`, `flutter-implement-json-serialization`, `dart-resolve-package-conflicts`, `dart-setup-ffi-assets`, `dart-use-ffigen`, `dart-build-cli-app`.
- Testing and quality: `flutter-add-widget-test`, `flutter-add-integration-test`, `dart-add-unit-test`, `dart-generate-test-mocks`, `dart-collect-coverage`, `dart-migrate-to-checks-package`, `dart-run-static-analysis`, `dart-fix-runtime-errors`.
- Dart language and documentation: `dart-use-pattern-matching`, `dart-use-primary-constructors`, `dart-write-documentation`.

After making changes, follow the matching skill's verification guidance and run the narrowest relevant formatter, analysis, and test commands.
</flutter-agent-guidelines>
