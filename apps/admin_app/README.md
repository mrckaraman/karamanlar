# admin_app

A new Flutter project.

## Web (Firebase Hosting)

Admin web build'inde Supabase config derleme zamanında verilmelidir; aksi halde login sırasında istekler Firebase Hosting'e gider ve HTML döndüğü için `FormatException: Unexpected token '<' ...` görülebilir.

- Release build:
	- `flutter build web --release --dart-define-from-file=.dart-define-admin-web.json`
- Deploy:
	- `firebase deploy --only hosting`

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
