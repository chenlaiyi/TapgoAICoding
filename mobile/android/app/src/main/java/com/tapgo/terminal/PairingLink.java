package com.tapgo.terminal;

import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;

/** HTTPS root pairing link; never include this value in diagnostics. */
public final class PairingLink {
    public final String origin;
    public final String url;
    public final String name;
    private PairingLink(String origin, String url, String name) {
        this.origin = origin; this.url = url; this.name = name;
    }
    /** Parse an authenticated HTTPS link or the desktop's dsh-mobile deep link. */
    public static PairingLink parse(String value) {
        try {
            URI uri = new URI(value.trim());
            if ("dsh-mobile".equals(uri.getScheme())) {
                String nested = query(uri).get("url");
                if (nested == null) throw new IllegalArgumentException();
                uri = new URI(nested);
            }
            Map<String, String> params = query(uri);
            String token = params.get("token");
            if (!"https".equals(uri.getScheme()) || uri.getHost() == null || uri.getUserInfo() != null
                    || uri.getFragment() != null || uri.getPort() == 0 || uri.getPort() > 65535
                    || !(uri.getPath().isEmpty() || uri.getPath().equals("/"))
                    || token == null || token.trim().isEmpty()) throw new IllegalArgumentException();
            String origin = new URI("https", null, uri.getHost().toLowerCase(java.util.Locale.ROOT), uri.getPort(), "", null, null).toString();
            String name = params.getOrDefault("name", uri.getHost()).trim();
            if (name.isEmpty()) name = uri.getHost();
            if (name.length() > 80) name = name.substring(0, 80);
            return new PairingLink(origin, uri.toASCIIString(), name);
        } catch (Exception exception) {
            throw new IllegalArgumentException("Invalid pairing link");
        }
    }
    /** Compare scheme, host and effective HTTPS port without trusting a string prefix. */
    public static boolean sameOrigin(String origin, String destination) {
        try {
            URI a = URI.create(origin), b = URI.create(destination);
            return "https".equals(b.getScheme()) && b.getUserInfo() == null && a.getHost().equalsIgnoreCase(b.getHost())
                    && (a.getPort() < 0 ? 443 : a.getPort()) == (b.getPort() < 0 ? 443 : b.getPort());
        } catch (Exception exception) { return false; }
    }
    private static Map<String, String> query(URI uri) throws java.io.UnsupportedEncodingException {
        Map<String, String> values = new LinkedHashMap<>();
        if (uri.getRawQuery() == null) return values;
        for (String part : uri.getRawQuery().split("&")) {
            String[] pair = part.split("=", 2);
            String key = URLDecoder.decode(pair[0], StandardCharsets.UTF_8.name());
            if (values.containsKey(key)) throw new IllegalArgumentException();
            values.put(key, pair.length == 2 ? URLDecoder.decode(pair[1], StandardCharsets.UTF_8.name()) : "");
        }
        return values;
    }
}
