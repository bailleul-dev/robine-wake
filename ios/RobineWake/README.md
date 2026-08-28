# Robine Wake iOS

The Xcode project is generated and must not be edited as source configuration.

```sh
brew install xcodegen
cd ios/RobineWake
xcodegen generate
open RobineWake.xcodeproj
```

The prototype deliberately performs no pairing or application-level
authentication. It connects to the first nearby device advertising the Robine
Wake BLE service.

Philips Hue setup lives in the `Réveil` tab. The app discovers `_hue._tcp` bridges
through Bonjour and resolves their LAN address automatically; manual entry remains
available as a fallback. Press the bridge link button and select it to pair. The
alarm editor then offers a per-alarm Hue room or zone and progressive brightness
controls. Hue traffic is sent by the Robine Wake device over the local network,
not by the iPhone directly.
