# Kalsubai Farms

Kalsubai Farms farmer intelligence and traceability app.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Render web host

`render.yaml` defines the `grainright-web` Docker service. It builds the Flutter
web app with `Dockerfile.render` and serves deep links, including
`/whatsapp-farm-boundary?token=...`.

After the service is deployed, copy its public HTTPS `onrender.com` URL into
the Supabase Edge Function secret `GRAINRIGHT_APP_URL`. Do not use the
Supabase project URL for this value. Verify the host's `/health` endpoint and
the boundary route before sending a real WhatsApp onboarding link.
