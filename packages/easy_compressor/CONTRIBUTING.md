# Contributing to easy_compressor

Thank you for your interest in contributing!

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/KHKikani/easy_compressor.git`
3. Create a feature branch: `git checkout -b feature/my-feature`
4. Make your changes
5. Submit a pull request

## Development Setup

### General

- Flutter SDK >= 3.19.0
- Dart SDK >= 3.2.0

### Android

- Android Studio (latest stable)
- Android SDK with API 34
- Kotlin 1.9+

### iOS / macOS

- Xcode 15+
- CocoaPods: `gem install cocoapods`
- iOS 13+ / macOS 10.15+ deployment target

### Windows

- Visual Studio 2022 with "Desktop development with C++" workload
- Windows 10 SDK
- CMake (included with VS)

## Running Tests

```bash
# Dart unit tests
flutter test

# Run the example app
cd example
flutter run
```

## Code Style

- **Dart**: Follow `flutter_lints` rules. Run `dart format .` before committing.
- **Kotlin**: Follow standard Kotlin conventions.
- **Swift**: Follow standard Swift conventions.
- **C++**: C++17 standard, follow existing patterns in the codebase.

## Architecture

See [ARCHITECTURE.md](ARCHITECTURE.md) for technical details on how the plugin is structured.

## Pull Request Process

1. Ensure all tests pass
2. Update CHANGELOG.md if adding features or fixing bugs
3. Update README.md if changing public API
4. Keep PRs focused — one feature or fix per PR
5. Write clear commit messages

## Reporting Issues

Use GitHub Issues with the following templates:

**Bug Report**: Include platform, Flutter version, steps to reproduce, expected vs actual behavior.

**Feature Request**: Describe the use case and proposed solution.
