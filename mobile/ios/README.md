# Tapgo iOS

English | [中文](README.zh.md)

The iOS app presents the running DSH Web interface in a WebKit view. It accepts an HTTPS URL with DSH's one-process `token` query parameter by scan, paste, or `dsh-mobile://?url=…` deep link. The URL is stored in this device's Keychain; the Web session cookie stays in WebKit. Disconnect removes the saved URL. The Web view stays on the paired origin.

Generate the Xcode project with `xcodegen generate` in this directory and build the `DshMobile` scheme. The app uses the existing `com.devtools.terminalSimple` bundle ID; signing and distribution require access to its Apple developer team.

On the Mac, run the Tapgo Desktop Host behind Tailscale Serve HTTPS, for example on port 8443 forwarding to the Host's loopback port 19388. Set `TAPGO_MOBILE_HTTPS_ORIGIN` to that exact HTTPS origin in `~/.tapgo-aicoding/.env` or the launch environment before starting Desktop. The Desktop application menu then offers **Connect iPhone**, which copies the authenticated link. Both devices must belong to the same tailnet. Tailscale Serve is private to the tailnet; do not enable Funnel. The Desktop Host remains bound to loopback and explicitly trusts only the configured HTTPS authority.

A process restart rotates the URL token. A WebKit cookie issued earlier may remain valid until its configured expiry. Recopy the link if the app needs to authenticate again. Do not share the link; it grants access to the Harness UI and command execution.
