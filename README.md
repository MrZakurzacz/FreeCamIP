# FreeCamIP

FreeCamIP is the iPhone sender for [FreeCam](https://github.com/MrZakurzacz/FreeCam).

It captures video from the iPhone camera, encodes it with Apple's hardware video stack, and sends it over the local network to the FreeCam receiver on Windows.

## Project goals

- free and open source
- no account
- no cloud requirement
- no watermark
- no artificial resolution or time limits
- reliable reconnect behavior
- Windows 10 and Windows 11 receiver compatibility

## Initial target

The first milestone is deliberately small:

```text
iPhone camera
  -> AVFoundation
  -> VideoToolbox H.264
  -> transport interface
  -> FreeCam Windows receiver
```

Initial video mode: **1280x720 at 30 fps**.

## Protocol

The canonical protocol specification lives in the main FreeCam repository:

[docs/protocol.md](https://github.com/MrZakurzacz/FreeCam/blob/main/docs/protocol.md)

FreeCamIP must follow that document instead of maintaining a separate protocol fork.

## Development

Native iOS builds require Apple's iOS toolchain. The repository uses XcodeGen so the generated `.xcodeproj` file does not need to be maintained by hand.

GitHub Actions can compile the application on a macOS runner. Testing the real camera and installing development builds on an iPhone still requires Apple code signing.

## License

FreeCamIP is intended to be released under GPL-3.0 together with the FreeCam project.
