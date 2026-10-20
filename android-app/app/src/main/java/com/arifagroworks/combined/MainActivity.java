
package com.arifagroworks.combined;

import android.app.Activity;
import android.os.Bundle;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.graphics.Color;
import android.widget.LinearLayout;
import android.widget.Button;
import android.view.ViewGroup;

public class MainActivity extends Activity {
    WebView web;
    String base = "https://arifagroworks.github.io/arif-agro-works-website/";

    @Override
    public void onCreate(Bundle state) {
        super.onCreate(state);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.rgb(3, 15, 32));

        LinearLayout bar = new LinearLayout(this);
        bar.setPadding(8, 12, 8, 12);

        Button website = new Button(this);
        website.setText("Website");

        Button software = new Button(this);
        software.setText("Software");

        bar.addView(website, new LinearLayout.LayoutParams(0, -2, 1));
        bar.addView(software, new LinearLayout.LayoutParams(0, -2, 1));

        web = new WebView(this);
        web.setWebViewClient(new WebViewClient());
        web.setWebChromeClient(new WebChromeClient());

        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);

        root.addView(bar);
        root.addView(web, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));

        setContentView(root);

        website.setOnClickListener(v -> web.loadUrl(base));
        software.setOnClickListener(v -> web.loadUrl(base + "portal/index.html"));

        web.loadUrl(base);
    }

    @Override
    public void onBackPressed() {
        if (web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }
}
