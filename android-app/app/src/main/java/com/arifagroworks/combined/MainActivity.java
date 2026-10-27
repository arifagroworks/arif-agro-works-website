package com.arifagroworks.combined;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.os.Handler;
import android.os.Looper;
import android.os.ParcelFileDescriptor;
import android.print.PageRange;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintManager;
import android.util.Base64;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowInsets;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import org.json.JSONObject;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Collections;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {
    private static final int IMPORT_FILE = 301, SAVE_FILE = 302;
    private static final String BASE = NativePolicy.BASE;
    private WebView web, printWeb;
    private ValueCallback<Uri[]> fileCallback;
    private File pendingExport;
    private String nativeScript;
    private boolean restoring;
    private final ExecutorService fileWorker = Executors.newSingleThreadExecutor();
    private final Handler splashHandler = new Handler(Looper.getMainLooper());
    // Package-private access for synthetic emulator tests; no exported IPC/test URL.
    public WebView testWebView() { return web; }
    public volatile Uri lastSavedUri;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_splash);
        protectInsets(findViewById(R.id.splash_root));
        if (state != null && state.getString("pendingExport") != null) {
            File saved = new File(getCacheDir(), state.getString("pendingExport"));
            if (saved.getParentFile().equals(getCacheDir()) && saved.getName().startsWith("aaw-export-") && saved.exists()) pendingExport = saved;
        }
        try (InputStream in = getAssets().open("native-support.js")) {
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192]; int count;
            while ((count = in.read(buffer)) != -1) out.write(buffer, 0, count);
            nativeScript = out.toString("UTF-8");
        } catch (Exception error) { nativeScript = ""; }
        splashHandler.postDelayed(() -> {
            if (!isFinishing() && !isDestroyed()) openWebsite(state);
        }, 1000);
    }

    private void openWebsite(Bundle state) {
        web = new WebView(this);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(true); // Only user-selected content:// imports.
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setSupportMultipleWindows(true);
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(web, "AAWNative", Collections.singleton(NativePolicy.ORIGIN),
                (view, message, origin, mainFrame, reply) -> {
                    if (!NativePolicy.trusted(view.getUrl()) || !NativePolicy.trustedOrigin(origin.toString())) return;
                    try {
                        String payload = message.getData();
                        if (payload == null || payload.length() > NativePolicy.MAX_BYTES * 2) throw new Exception("Document is too large.");
                        JSONObject data = new JSONObject(payload);
                        if ("save".equals(data.optString("action"))) saveExport(data);
                        else if ("print".equals(data.optString("action"))) printDocument(data);
                    } catch (Exception error) { toast(error.getMessage()); }
                });
            if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
                WebViewCompat.addDocumentStartJavaScript(web, nativeScript, Collections.singleton(NativePolicy.ORIGIN));
            }
        } else toast("Update Android System WebView to enable in-app PDF and file exports.");
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                if (!request.isForMainFrame()) return false;
                String url = request.getUrl().toString();
                if (NativePolicy.trusted(url)) return false;
                openExternal(url); return true;
            }
            @Override public void onPageFinished(WebView view, String url) {
                if (!NativePolicy.trusted(url)) return;
                // Fallback for WebView providers without document-start script support.
                String source = JSONObject.quote(nativeScript);
                view.evaluateJavascript("(function(){const s=" + source + ";function run(w){try{w.eval(s);w.document.querySelectorAll('iframe').forEach(f=>{if(!f.dataset.aawNativeHook){f.dataset.aawNativeHook='1';f.addEventListener('load',()=>run(f.contentWindow));}run(f.contentWindow)});}catch(e){}}run(window);if(!window.aawNativeObserver){window.aawNativeObserver=new MutationObserver(()=>run(window));window.aawNativeObserver.observe(document.documentElement,{childList:true,subtree:true});}})()", null);
            }
            @Override public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame() && !isFinishing()) new AlertDialog.Builder(MainActivity.this)
                    .setTitle("Unable to open page / पेज नहीं खुला")
                    .setMessage("Check your internet connection. / इंटरनेट कनेक्शन जाँचें।")
                    .setPositiveButton("Retry / फिर कोशिश", (dialog, which) -> web.loadUrl(BASE))
                    .setNegativeButton("Close / बंद", null).show();
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (fileCallback != null) fileCallback.onReceiveValue(null);
                fileCallback = callback;
                try { startActivityForResult(params.createIntent().addCategory(Intent.CATEGORY_OPENABLE), IMPORT_FILE); }
                catch (ActivityNotFoundException error) { fileCallback.onReceiveValue(null); fileCallback = null; toast("No file picker is available."); }
                return true;
            }
            @Override public boolean onCreateWindow(WebView view, boolean dialog, boolean gesture, android.os.Message result) {
                if (!gesture) return false;
                final WebView popup = new WebView(MainActivity.this);
                popup.setWebViewClient(new WebViewClient() {
                    private boolean handled;
                    private boolean route(String url) {
                        if (handled || "about:blank".equals(url)) return false;
                        handled = true;
                        if (NativePolicy.trusted(url)) web.loadUrl(url); else openExternal(url);
                        popup.post(popup::destroy); return true;
                    }
                    @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest request) { return route(request.getUrl().toString()); }
                    @Override public void onPageStarted(WebView v, String url, android.graphics.Bitmap icon) { route(url); }
                });
                ((WebView.WebViewTransport) result.obj).setWebView(popup); result.sendToTarget(); return true;
            }
        });
        web.setDownloadListener((url, agent, disposition, mime, length) -> {
            if (NativePolicy.trusted(web.getUrl())) web.evaluateJavascript("window.AAWNativeSupport&&AAWNativeSupport.saveUrl(" + JSONObject.quote(url) + ",'AAW-export.bin').catch(e=>alert(e.message))", null);
        });
        FrameLayout viewport = new FrameLayout(this);
        viewport.setBackgroundColor(Color.rgb(245, 240, 223));
        web.setBackgroundColor(Color.rgb(245, 240, 223));
        viewport.addView(web, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        protectInsets(viewport); setContentView(viewport); viewport.requestApplyInsets();
        if (state != null && state.getBundle("webState") != null && web.restoreState(state.getBundle("webState")) != null) restoring = true;
        if (!restoring) {
            boolean smoke = (getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
                && getIntent().getBooleanExtra("aawNativeSmoke", false);
            if (smoke) web.loadDataWithBaseURL(BASE+"native-fixture.html", "<!doctype html><title>AAW synthetic fixture</title>", "text/html", "UTF-8", null);
            else web.loadUrl(BASE);
        }
    }

    private void saveExport(JSONObject data) throws Exception {
        if (pendingExport != null) throw new Exception("Finish the current Save dialog first.");
        String encoded = data.getString("data");
        if (encoded.length() > (NativePolicy.MAX_BYTES * 4L / 3L + 4) || !encoded.matches("[A-Za-z0-9+/]*={0,2}")) throw new Exception("Invalid or oversized export.");
        byte[] bytes = Base64.decode(encoded, Base64.DEFAULT);
        if (bytes.length > NativePolicy.MAX_BYTES) throw new Exception("Export exceeds 12 MB.");
        pendingExport = File.createTempFile("aaw-export-", ".bin", getCacheDir());
        try (OutputStream out = new FileOutputStream(pendingExport)) { out.write(bytes); }
        String mime = data.optString("mime", "application/octet-stream").split(";", 2)[0];
        if (!mime.matches("[A-Za-z0-9!#$&^_.+\\-]+/[A-Za-z0-9!#$&^_.+\\-]+")) mime = "application/octet-stream";
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
            .setType(mime).putExtra(Intent.EXTRA_TITLE, NativePolicy.fileName(data.optString("name")));
        try { startActivityForResult(intent, SAVE_FILE); }
        catch (ActivityNotFoundException error) { pendingExport.delete(); pendingExport = null; throw new Exception("No file saving app is available."); }
    }

    private void printDocument(JSONObject data) throws Exception {
        if (printWeb != null) throw new Exception("Finish the current print preview first.");
        String base = data.getString("base"), html = data.getString("html");
        if (!NativePolicy.trusted(base) || html.getBytes(StandardCharsets.UTF_8).length > NativePolicy.MAX_BYTES) throw new Exception("Invalid print document.");
        final String name = NativePolicy.fileName(data.optString("title", "AAW Document"));
        printWeb = new WebView(this);
        printWeb.getSettings().setJavaScriptEnabled(false);
        printWeb.getSettings().setAllowFileAccess(false);
        printWeb.getSettings().setAllowContentAccess(false);
        printWeb.setWebViewClient(new WebViewClient() {
            boolean started;
            @Override public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest r) {
                if (NativePolicy.trusted(r.getUrl().toString()) || "data".equals(r.getUrl().getScheme())) return null;
                return new WebResourceResponse("text/plain", "UTF-8", new ByteArrayInputStream(new byte[0]));
            }
            @Override public void onPageFinished(WebView v, String url) {
                if (started) return; started = true;
                v.postDelayed(() -> {
                    if (isFinishing() || printWeb != v) return;
                    PrintDocumentAdapter delegate = v.createPrintDocumentAdapter(name);
                    PrintManager manager = (PrintManager) getSystemService(PRINT_SERVICE);
                    if (manager == null) { v.destroy(); printWeb = null; toast("Print service unavailable."); return; }
                    manager.print(name, new PrintDocumentAdapter() {
                        @Override public void onStart() { delegate.onStart(); }
                        @Override public void onLayout(PrintAttributes old, PrintAttributes next, CancellationSignal signal, LayoutResultCallback callback, Bundle extras) { delegate.onLayout(old, next, signal, callback, extras); }
                        @Override public void onWrite(PageRange[] ranges, ParcelFileDescriptor destination, CancellationSignal signal, WriteResultCallback callback) { delegate.onWrite(ranges, destination, signal, callback); }
                        @Override public void onFinish() { delegate.onFinish(); if (printWeb == v) { v.destroy(); printWeb = null; } }
                    }, new PrintAttributes.Builder().setMediaSize(PrintAttributes.MediaSize.ISO_A4).build());
                }, 400);
            }
        });
        printWeb.loadDataWithBaseURL(base, html, "text/html", "UTF-8", null);
    }

    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == IMPORT_FILE && fileCallback != null) {
            Uri[] selected = WebChromeClient.FileChooserParams.parseResult(result, data);
            if (selected != null) for (Uri uri : selected) if (!"content".equals(uri.getScheme())) { selected = null; break; }
            fileCallback.onReceiveValue(selected); fileCallback = null;
        } else if (request == SAVE_FILE && pendingExport != null) {
            File source = pendingExport; pendingExport = null;
            Uri destination = result == RESULT_OK && data != null ? data.getData() : null;
            if (destination == null || !"content".equals(destination.getScheme())) { source.delete(); return; }
            fileWorker.execute(() -> {
                try (InputStream in = new FileInputStream(source); OutputStream out = getContentResolver().openOutputStream(destination, "w")) {
                    if (out == null) throw new Exception("No write permission.");
                    byte[] buffer = new byte[8192]; int n; while ((n = in.read(buffer)) != -1) out.write(buffer, 0, n);
                    lastSavedUri = destination; toast("File saved / फ़ाइल सहेजी गई");
                } catch (Exception error) { toast("Save failed: " + error.getMessage()); }
                finally { source.delete(); }
            });
        }
    }

    private void openExternal(String url) {
        if (!NativePolicy.externalScheme(url)) { toast("Unsupported link."); return; }
        try { startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE)); }
        catch (ActivityNotFoundException error) { toast("No app is available for this link."); }
    }
    private void toast(String message) { runOnUiThread(() -> Toast.makeText(this, message == null ? "Action failed." : message, Toast.LENGTH_LONG).show()); }
    private void protectInsets(View root) {
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                Insets safe = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
                view.setPadding(safe.left, safe.top, safe.right, safe.bottom);
            } else view.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(), insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            return insets;
        });
        root.requestApplyInsets();
    }
    @Override protected void onSaveInstanceState(Bundle state) {
        if (web != null) { Bundle webState = new Bundle(); web.saveState(webState); state.putBundle("webState", webState); }
        if (pendingExport != null) state.putString("pendingExport", pendingExport.getName());
        super.onSaveInstanceState(state);
    }
    @Override protected void onDestroy() {
        splashHandler.removeCallbacksAndMessages(null);
        if (fileCallback != null) { fileCallback.onReceiveValue(null); fileCallback = null; }
        if (web != null) web.destroy();
        if (printWeb != null) { printWeb.destroy(); printWeb = null; }
        if (isFinishing() && pendingExport != null) pendingExport.delete();
        fileWorker.shutdown(); super.onDestroy();
    }
    @Override public void onBackPressed() { if (web != null && web.canGoBack()) web.goBack(); else super.onBackPressed(); }
}
