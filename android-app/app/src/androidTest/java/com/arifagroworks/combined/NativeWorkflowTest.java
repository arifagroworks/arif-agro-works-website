package com.arifagroworks.combined;

import android.content.Intent;
import android.os.SystemClock;
import android.webkit.WebView;
import org.json.JSONArray;
import android.view.WindowInsets;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;
import androidx.test.uiautomator.Until;
import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TestWatcher;
import org.junit.runner.Description;
import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import static org.junit.Assert.*;

/** Hardcoded debug assets served at intercepted HTTPS URLs; no live login/mutation. */
public class NativeWorkflowTest {
    @Rule public ActivityTestRule<MainActivity> rule = new ActivityTestRule<>(MainActivity.class, false, false);
    private MainActivity activity;
    private UiDevice device;
    @Rule public TestWatcher diagnostics = new TestWatcher() {
        @Override protected void failed(Throwable error, Description description) {
            try {
                Log.e("AAW-Smoke", "Document: " + js("JSON.stringify({url:location.href,ready:document.readyState,html:document.body?.innerHTML})"));
                ByteArrayOutputStream hierarchy = new ByteArrayOutputStream();
                device.dumpWindowHierarchy(hierarchy);
                Log.e("AAW-Smoke", "UI: " + hierarchy.toString("UTF-8"));
            } catch (Exception ignored) { Log.e("AAW-Smoke", "Diagnostics unavailable", ignored); }
        }
    };
    @Before public void launch() throws Exception {
        device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation());
        activity = rule.launchActivity(new Intent().putExtra("aawNativeSmoke",true));
        for (int i = 0; i < 100 && activity.testWebView() == null; i++) SystemClock.sleep(100);
        assertNotNull(activity.testWebView());
    }
    private String js(String script) throws Exception {
        CountDownLatch done = new CountDownLatch(1); AtomicReference<String> value = new AtomicReference<>();
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> activity.testWebView().evaluateJavascript(script, text -> {value.set(text);done.countDown();}));
        assertTrue("JS response", done.await(10, TimeUnit.SECONDS)); return value.get();
    }
    private void page(String fixture) throws Exception {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> activity.testWebView().loadUrl(NativePolicy.BASE+"native-fixture-"+fixture+".html"));
        boolean ready=false;
        for(int i=0;i<100;i++){ if("true".equals(js("!!window.AAWNativeSupport&&document.readyState==='complete'&&document.body?.dataset.fixture==='"+fixture+"'"))){ready=true;break;}SystemClock.sleep(100); }
        assertTrue("Origin-scoped native bridge installed on the complete HTTPS fixture",ready);
    }
    private void tap(String selector) throws Exception {
        js("document.querySelector('"+selector+"').scrollIntoView({block:'center'})");
        CountDownLatch painted=new CountDownLatch(1);
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> activity.testWebView().postVisualStateCallback(1,new WebView.VisualStateCallback(){@Override public void onComplete(long id){painted.countDown();}}));
        assertTrue("Fixture painted",painted.await(10,TimeUnit.SECONDS));
        JSONArray box=new JSONArray(js("(()=>{const r=document.querySelector('"+selector+"').getBoundingClientRect();return [r.x+r.width/2,r.y+r.height/2,innerWidth]})()"));
        int[] position=new int[3];
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {activity.testWebView().getLocationOnScreen(position);position[2]=activity.testWebView().getWidth();});
        double scale=position[2]/box.getDouble(2);
        assertTrue("Tap actual rendered control",device.click(position[0]+(int)(box.getDouble(0)*scale),position[1]+(int)(box.getDouble(1)*scale)));
    }
    private boolean keyboardVisible() {
        AtomicReference<Boolean> visible=new AtomicReference<>(false);
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> {WindowInsets insets=activity.testWebView().getRootWindowInsets();visible.set(insets!=null&&insets.isVisible(WindowInsets.Type.ime()));});
        return visible.get();
    }
    private UiObject2 findText(String text) { return device.wait(Until.findObject(By.text(text)), 15000); }
    private void savePicker() throws Exception {
        UiObject2 save=device.wait(Until.findObject(By.res("com.android.documentsui","action_menu_save")),15000);
        if(save==null)save=findText("SAVE");if(save==null)save=findText("Save");
        assertNotNull("Android Save document action",save);save.click();
    }
    @Test public void csvExportUsesSystemPickerAndPreservesBytes() throws Exception {
        page("csv");
        tap("button");savePicker();
        for(int i=0;i<100&&activity.lastSavedUri==null;i++)SystemClock.sleep(100);
        assertNotNull("Saved URI returned",activity.lastSavedUri);
        try(InputStream in=activity.getContentResolver().openInputStream(activity.lastSavedUri)){
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] buffer=new byte[1024];int n;while((n=in.read(buffer))!=-1)bytes.write(buffer,0,n);
            assertEquals("name,amount\nSynthetic Worker,123.45\n",bytes.toString("UTF-8"));
        }
    }
    @Test public void importFilePickerCanBeOpenedAndCanceled() throws Exception {
        page("import");
        tap("input");
        assertTrue("Android Files picker",device.wait(Until.hasObject(By.pkg("com.android.documentsui")),15000));
        device.pressBack();SystemClock.sleep(500);assertFalse(activity.isFinishing());
        assertEquals("true",js("!!document.querySelector('input[type=file]')"));
    }
    @Test public void nativePrintSavesARealPdf() throws Exception {
        page("print");
        tap("button");
        UiObject2 print=device.wait(Until.findObject(By.res("com.android.printspooler","print_button")),20000);
        assertNotNull("System PDF print preview",print);for(int i=0;i<100&&!print.isEnabled();i++)SystemClock.sleep(100);assertTrue("Print button enabled",print.isEnabled());print.click();savePicker();SystemClock.sleep(2000);
        String listing=device.executeShellCommand("find /sdcard/Download -name '*.pdf' -type f");
        assertTrue("Saved PDF exists",listing.contains(".pdf"));
    }
    @Test public void backNavigationAndKeyboardKeepTheAppUsable() throws Exception {
        page("navigation");
        tap("#name");
        for(int i=0;i<100&&!keyboardVisible();i++)SystemClock.sleep(100);
        assertTrue("Real Android keyboard visible",keyboardVisible());
        device.executeShellCommand("input text Synthetic%sName");device.pressBack();
        assertEquals("\"Synthetic Name\"",js("document.getElementById('name').value"));
        tap("button");assertEquals("\"#second\"",js("location.hash"));device.pressBack();SystemClock.sleep(300);
        assertFalse(activity.isFinishing());assertEquals("\"\"",js("location.hash"));
    }
}
