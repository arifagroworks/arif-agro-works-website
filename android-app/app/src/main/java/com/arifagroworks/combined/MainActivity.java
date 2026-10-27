
package com.arifagroworks.combined;

import android.app.Activity;
import android.os.Bundle;
import android.os.Build;
import android.graphics.Insets;
import android.graphics.Color;
import android.view.View;
import android.view.WindowInsets;
import android.widget.FrameLayout;
import android.os.Handler;
import android.os.Looper;
import android.view.ViewGroup;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;

public class MainActivity extends Activity {

    private WebView web;
    private final Handler splashHandler = new Handler(Looper.getMainLooper());

    private static final String BASE =
        "https://arifagroworks.github.io/arif-agro-works-website/";

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);

        // Show branded splash screen
        setContentView(R.layout.activity_splash);
        protectInsets(findViewById(R.id.splash_root));

        splashHandler.postDelayed(
            new Runnable() {
                @Override
                public void run() {
                    if (!isFinishing() && !isDestroyed()) openWebsite();
                }
            },
            1800
        );
    }

    private void openWebsite() {
        web = new WebView(this);

        web.setWebViewClient(new WebViewClient());
        web.setWebChromeClient(new WebChromeClient());

        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);

        FrameLayout viewport = new FrameLayout(this);
        viewport.setBackgroundColor(Color.WHITE);
        viewport.addView(web, new FrameLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        protectInsets(viewport);
        setContentView(viewport);
        viewport.requestApplyInsets();

        web.loadUrl(BASE);
    }

    // Keep page content below system bars/cutouts, including Android 15 edge-to-edge.
    private void protectInsets(View root) {
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                Insets safe = insets.getInsets(WindowInsets.Type.systemBars()
                    | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
                view.setPadding(safe.left, safe.top, safe.right, safe.bottom);
            } else {
                view.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                    insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            }
            return insets;
        });
        root.requestApplyInsets();
    }

    @Override
    protected void onDestroy() {
        splashHandler.removeCallbacksAndMessages(null);
        if (web != null) web.destroy();
        super.onDestroy();
    }

    @Override
    public void onBackPressed() {
        if (web != null && web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }
}
