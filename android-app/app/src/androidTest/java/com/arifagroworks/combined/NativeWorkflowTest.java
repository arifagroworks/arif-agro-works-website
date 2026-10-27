package com.arifagroworks.combined;

import android.content.Intent;
import android.os.SystemClock;
import android.webkit.WebView;
import androidx.test.platform.app.InstrumentationRegistry;
import androidx.test.rule.ActivityTestRule;
import androidx.test.uiautomator.By;
import androidx.test.uiautomator.UiDevice;
import androidx.test.uiautomator.UiObject2;
import androidx.test.uiautomator.Until;
import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import static org.junit.Assert.*;

/** Entirely synthetic documents under loadDataWithBaseURL; no live login/mutation. */
public class NativeWorkflowTest {
    @Rule public ActivityTestRule<MainActivity> rule = new ActivityTestRule<>(MainActivity.class, false, false);
    private MainActivity activity;
    private UiDevice device;
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
    private void page(String body) throws Exception {
        InstrumentationRegistry.getInstrumentation().runOnMainSync(() -> activity.testWebView().loadDataWithBaseURL(NativePolicy.BASE+"native-fixture.html", "<!doctype html><html><meta name='viewport' content='width=device-width, initial-scale=1'><title>AAW-Print-Test</title><style>body{font:22px sans-serif;padding:20px}button,input{font:22px sans-serif;padding:15px;margin:15px;display:block}@media print{button,input{display:none}}</style>"+body+"</html>","text/html","UTF-8",null));
        boolean ready=false;
        for(int i=0;i<100;i++){ if("true".equals(js("!!window.AAWNativeSupport"))){ready=true;break;}SystemClock.sleep(100); }
        assertTrue("Origin-scoped native bridge installed",ready);
    }
    private UiObject2 findText(String text) { return device.wait(Until.findObject(By.text(text)), 15000); }
    private void savePicker() throws Exception {
        UiObject2 save=device.wait(Until.findObject(By.res("com.android.documentsui","action_menu_save")),15000);
        if(save==null)save=findText("SAVE");if(save==null)save=findText("Save");
        assertNotNull("Android Save document action",save);save.click();
    }
    @Test public void csvExportUsesSystemPickerAndPreservesBytes() throws Exception {
        page("<h1>AAW synthetic CSV</h1><button onclick=\"const a=document.createElement('a');a.download='AAW-native-smoke.csv';a.href=URL.createObjectURL(new Blob(['name,amount\\nSynthetic Worker,123.45\\n'],{type:'text/csv'}));a.click()\">Export CSV</button>");
        UiObject2 button=findText("Export CSV");assertNotNull(button);button.click();savePicker();
        for(int i=0;i<100&&activity.lastSavedUri==null;i++)SystemClock.sleep(100);
        assertNotNull("Saved URI returned",activity.lastSavedUri);
        try(InputStream in=activity.getContentResolver().openInputStream(activity.lastSavedUri)){
            ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] buffer=new byte[1024];int n;while((n=in.read(buffer))!=-1)bytes.write(buffer,0,n);
            assertEquals("name,amount\nSynthetic Worker,123.45\n",bytes.toString("UTF-8"));
        }
    }
    @Test public void importFilePickerCanBeOpenedAndCanceled() throws Exception {
        page("<h1>AAW import fixture</h1><label>Import JSON<input type='file' accept='.json' aria-label='Import JSON'></label>");
        UiObject2 input=device.wait(Until.findObject(By.clazz("android.widget.Button")),15000);
        if(input==null)input=findText("Choose File");assertNotNull("File input",input);input.click();
        assertTrue("Android Files picker",device.wait(Until.hasObject(By.pkg("com.android.documentsui")),15000));
        device.pressBack();SystemClock.sleep(500);assertFalse(activity.isFinishing());
        assertEquals("true",js("!!document.querySelector('input[type=file]')"));
    }
    @Test public void nativePrintSavesARealPdf() throws Exception {
        page("<h1>AAW-NATIVE-PRINT-FIXTURE</h1><p>Synthetic invoice only. Amount 123.45</p><button onclick='window.print()'>Print Test PDF</button>");
        UiObject2 button=findText("Print Test PDF");assertNotNull(button);button.click();
        UiObject2 print=device.wait(Until.findObject(By.res("com.android.printspooler","print_button")),20000);
        assertNotNull("System PDF print preview",print);for(int i=0;i<100&&!print.isEnabled();i++)SystemClock.sleep(100);assertTrue("Print button enabled",print.isEnabled());print.click();savePicker();SystemClock.sleep(2000);
        String listing=device.executeShellCommand("find /sdcard/Download -name '*.pdf' -type f");
        assertTrue("Saved PDF exists",listing.contains(".pdf"));
    }
    @Test public void backNavigationAndKeyboardKeepTheAppUsable() throws Exception {
        page("<h1>AAW navigation fixture</h1><input aria-label='Test name' id='name' placeholder='Test name'><button onclick=\"location.hash='second'\">Next screen</button>");
        UiObject2 input=device.wait(Until.findObject(By.clazz("android.widget.EditText")),15000);assertNotNull(input);input.click();input.setText("Synthetic Name");device.pressBack();
        assertEquals("\"Synthetic Name\"",js("document.getElementById('name').value"));
        findText("Next screen").click();assertEquals("\"#second\"",js("location.hash"));device.pressBack();SystemClock.sleep(300);
        assertFalse(activity.isFinishing());assertEquals("\"\"",js("location.hash"));
    }
}
