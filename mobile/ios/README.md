# Tapgo iOS

English | [中文](README.zh.md)

The iOS app provides a native list of paired Macs, with editable names during pairing and each Mac's HTTPS address. The current Mac stays visible above the DSH WebKit view; Switch returns to the list, and deleting a row removes that saved connection. Pair each Mac by scanning, pasting, or opening a `dsh-mobile://?url=…` deep link containing its HTTPS URL and one-process `token`. The connection list and tokens stay in this device's Keychain, while Web session cookies stay in WebKit. The Web view stays on the selected origin. The conversation interface remains the shared DSH Web client rather than a native iOS conversation screen.

Generate the Xcode project with `xcodegen generate` in this directory and build the `DshMobile` scheme. The app uses the existing `com.devtools.terminalSimple` bundle ID; signing and distribution require access to its Apple developer team.

On each Mac, run the Tapgo Desktop Host behind Tailscale Serve HTTPS, for example on port 8443 forwarding to the Host's loopback port 19388. Set `TAPGO_MOBILE_HTTPS_ORIGIN` to that Mac's exact HTTPS origin in `~/.tapgo-aicoding/.env` or the launch environment before starting Desktop. The Desktop application menu then offers **Connect iPhone**, which copies the authenticated link. Both devices must belong to the same tailnet. Tailscale Serve is private to the tailnet; do not enable Funnel. The Desktop Host remains bound to loopback, explicitly trusts only its configured HTTPS authority, and uses in-page directory browsing when mobile access is enabled so the phone can choose folders on that Mac.

A process restart rotates the URL token. A WebKit cookie issued earlier may remain valid until its configured expiry. Re-pair that Mac with a fresh link when authentication expires; its saved name is retained. Do not share the link; it grants access to the Harness UI and command execution.
