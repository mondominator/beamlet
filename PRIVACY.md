# Privacy Policy

**Last updated: April 2, 2026**

## Overview

Beamlet is a self-hosted file sharing application. Your data stays on your own server — we do not operate any cloud services or collect any user data.

## Data Collection

Beamlet does **not** collect, store, or transmit any personal data to the developer or any third party. All data (files, messages, contacts, and account information) is stored exclusively on the server you configure and control.

## Data Storage

- **Files and messages** are stored on your self-hosted server
- **Authentication tokens** are stored locally on your device using encrypted storage
- **Push notification tokens** (APNs/FCM) are stored on your server to enable notifications

## Third-Party Services

- **Apple Push Notification service (APNs)**: Used to deliver push notifications to iOS devices. Apple's privacy policy applies to the push delivery infrastructure.
- **Firebase Cloud Messaging (FCM)**: Used to deliver push notifications to Android devices. Google's privacy policy applies to the push delivery infrastructure.

Push notification tokens are sent to your self-hosted server only. No data is sent to the developer.

## Bluetooth

Beamlet uses Bluetooth Low Energy (BLE) to discover nearby users for convenient file sharing. BLE data is broadcast locally and is not transmitted over the internet. You can disable this in Settings under Discoverability.

## Camera

The camera is used solely to scan QR codes for adding contacts. No images from the camera are stored or transmitted.

## Permissions

| Permission | Purpose |
|-----------|---------|
| Internet | Connect to your self-hosted server |
| Camera | Scan QR codes for contact setup |
| Bluetooth | Discover nearby users |
| Notifications | Receive alerts when files are shared with you |
| Photos | Select photos/videos to share, save received photos |

## Children's Privacy

Beamlet is not directed at children under 13. We do not knowingly collect data from children.

## Contact

For questions about this privacy policy, please open an issue at [github.com/mondominator/beamlet](https://github.com/mondominator/beamlet).

## Changes

We may update this policy from time to time. Changes will be posted to this page.
