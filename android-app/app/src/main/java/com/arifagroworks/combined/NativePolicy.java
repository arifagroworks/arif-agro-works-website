package com.arifagroworks.combined;

import java.net.URI;

/** Pure validation shared by native handlers and local regression tests. */
public final class NativePolicy {
    public static final String ORIGIN = "https://arifagroworks.github.io";
    public static final String BASE = ORIGIN + "/arif-agro-works-website/";
    public static final int MAX_BYTES = 12 * 1024 * 1024;
    private NativePolicy() {}
    public static boolean trusted(String value) {
        try {
            URI uri = new URI(value).normalize();
            return "https".equalsIgnoreCase(uri.getScheme())
                && "arifagroworks.github.io".equalsIgnoreCase(uri.getHost())
                && uri.getUserInfo() == null && (uri.getPort() == -1 || uri.getPort() == 443)
                && uri.getPath().startsWith("/arif-agro-works-website/")
                && !uri.getPath().contains("/../");
        } catch (Exception invalid) { return false; }
    }
    public static boolean trustedOrigin(String value) {
        try {
            URI uri = new URI(value);
            return "https".equalsIgnoreCase(uri.getScheme()) && "arifagroworks.github.io".equalsIgnoreCase(uri.getHost())
                && uri.getUserInfo() == null && (uri.getPort() == -1 || uri.getPort() == 443)
                && (uri.getPath() == null || uri.getPath().isEmpty() || "/".equals(uri.getPath()));
        } catch (Exception invalid) { return false; }
    }
    public static String fileName(String value) {
        String name = value == null ? "" : value.replaceAll("[\\p{Cntrl}/\\\\:*?\"<>|]", "_").trim();
        while (name.startsWith(".")) name = name.substring(1);
        if (name.length() > 120) { int dot = name.lastIndexOf('.'); String suffix = dot > 0 && name.length() - dot <= 15 ? name.substring(dot) : ""; name = name.substring(0, 100) + suffix; }
        return name.isEmpty() ? "AAW-export.bin" : name;
    }
    public static boolean externalScheme(String value) {
        try {
            String scheme = new URI(value).getScheme();
            return "https".equalsIgnoreCase(scheme) || "tel".equalsIgnoreCase(scheme)
                || "mailto".equalsIgnoreCase(scheme) || "whatsapp".equalsIgnoreCase(scheme);
        } catch (Exception invalid) { return false; }
    }
}
