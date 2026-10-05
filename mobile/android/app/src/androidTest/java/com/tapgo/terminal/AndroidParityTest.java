package com.tapgo.terminal;
import android.content.Intent;
import android.net.Uri;
import androidx.test.core.app.ActivityScenario;
import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;
import org.junit.Test;
import org.junit.runner.RunWith;
import static androidx.test.espresso.Espresso.onView;
import static androidx.test.espresso.action.ViewActions.*;
import static androidx.test.espresso.assertion.ViewAssertions.matches;
import static androidx.test.espresso.matcher.ViewMatchers.*;
import static org.junit.Assert.*;
import static androidx.test.espresso.web.sugar.Web.onWebView;
import static androidx.test.espresso.web.webdriver.DriverAtoms.*;
import static androidx.test.espresso.web.assertion.WebViewAssertions.webMatches;
import androidx.test.espresso.web.webdriver.Locator;
import static org.hamcrest.Matchers.containsString;

@RunWith(AndroidJUnit4.class)
public class AndroidParityTest {
    private void waitText(String text) throws Exception {
        long end=System.currentTimeMillis()+15000;
        while(System.currentTimeMillis()<end){try{onView(withText(text)).check(matches(isDisplayed()));return;}catch(androidx.test.espresso.NoMatchingViewException|AssertionError missing){Thread.sleep(200);}}
        onView(withText(text)).check(matches(isDisplayed()));
    }
    private void waitEnabled(String text,boolean enabled) throws Exception {
        long end=System.currentTimeMillis()+15000;
        while(System.currentTimeMillis()<end){try{onView(withText(text)).check(matches(enabled?isEnabled():org.hamcrest.Matchers.not(isEnabled())));return;}catch(AssertionError pending){Thread.sleep(200);}}
        onView(withText(text)).check(matches(enabled?isEnabled():org.hamcrest.Matchers.not(isEnabled())));
    }
    @Test public void welcomeUsesSharedBrand(){
        android.content.Context context=InstrumentationRegistry.getInstrumentation().getTargetContext();
        context.getSharedPreferences("connections",0).edit().clear().commit();
        try(ActivityScenario<MainActivity> scenario=ActivityScenario.launch(MainActivity.class)){
            onView(withText("点点够终端")).check(matches(isDisplayed()));onView(withText("组装无限可能，共探智能上限")).check(matches(isDisplayed()));
            onView(withText("连接电脑")).perform(click());onView(withText("扫描二维码")).check(matches(isDisplayed()));onView(withText("从剪贴板粘贴")).check(matches(isDisplayed()));
        }
    }
    @Test public void pairingApprovalAndSessionWorkspace() throws Exception {
        android.content.Context context=InstrumentationRegistry.getInstrumentation().getTargetContext();context.getSharedPreferences("connections",0).edit().clear().commit();
        Intent intent=new Intent(context,MainActivity.class).setAction(Intent.ACTION_VIEW).setData(Uri.parse("dsh-mobile://?url=https%3A%2F%2Flocalhost%3A9443%2F%3Ftoken%3Dfixture%26name%3DAndroid%2520Test%2520PC"));
        try(ActivityScenario<MainActivity> scenario=ActivityScenario.launch(intent)){
            new RemoteClient(new ComputerStore(context).current()).authenticate();
            waitText("允许一次");onView(withText("允许一次")).perform(click());waitText("是否继续模拟器验收？");onView(withText("继续验收")).perform(click());onView(withText("提交")).perform(click());waitText("Android Test PC");waitText("已连接");
            assertFalse(context.getSharedPreferences("connections",0).getString("encrypted","").contains("token=fixture"));
            ComputerStore store=new ComputerStore(context);assertEquals("Android Test PC",store.current().name());
            onView(withText("Android 验收对话\n/work/Android")).perform(click());
            waitText("安卓原生对话已连接");waitText("余额 ¥12.50");
            onView(withText("设置")).perform(click());onView(withText(containsString("充值余额 ¥10.00"))).check(matches(isDisplayed()));onView(withText(containsString("赠送余额 ¥2.50"))).check(matches(isDisplayed()));onView(withText(containsString("本会话已使用 100 令牌"))).check(matches(isDisplayed()));onView(withText(containsString("750 / 1000"))).check(matches(isDisplayed()));onView(withText("关闭")).perform(click());
            android.content.ContentValues photoValues=new android.content.ContentValues();photoValues.put(android.provider.MediaStore.Images.Media.DISPLAY_NAME,"TapgoFixture.jpg");photoValues.put(android.provider.MediaStore.Images.Media.MIME_TYPE,"image/jpeg");
            Uri photo=context.getContentResolver().insert(android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI,photoValues);assertNotNull(photo);
            try(java.io.OutputStream output=context.getContentResolver().openOutputStream(photo)){android.graphics.Bitmap bitmap=android.graphics.Bitmap.createBitmap(32,32,android.graphics.Bitmap.Config.ARGB_8888);bitmap.eraseColor(android.graphics.Color.BLUE);bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG,80,output);bitmap.recycle();}
            try{scenario.onActivity(activity->activity.onActivityResult(502,android.app.Activity.RESULT_OK,new Intent().setData(photo)));waitText("移除照片");}finally{context.getContentResolver().delete(photo,null,null);}
            onView(withHint("发送消息…")).perform(typeText("test"),replaceText("模拟器消息"),closeSoftKeyboard());
            onView(withText("发送")).perform(click());waitText("流式验收回复");
            onView(withHint("发送消息…")).perform(replaceText("停止验收"),closeSoftKeyboard());onView(withText("发送")).perform(click());waitEnabled("停止",true);onView(withText("停止")).perform(click());waitEnabled("停止",false);
            onView(withText("模型")).perform(click());waitText("验收模型");onView(withText("验收模型")).perform(click());
            onView(withText("访问权限")).perform(click());waitText("安全模式");onView(withText("安全模式")).perform(click());waitText("验收权限确认");onView(withText("提交")).perform(click());waitText("安全模式");
            onView(withText("完整工作区")).perform(click());
            waitText("返回");
            long end=System.currentTimeMillis()+15000; boolean selected=false;
            while(System.currentTimeMillis()<end){try{onWebView().withElement(findElement(Locator.ID,"selection")).check(webMatches(getText(),containsString("session-one")));selected=true;break;}catch(RuntimeException|AssertionError pending){Thread.sleep(200);}}
            assertTrue("Workspace must open the selected session",selected);
            onView(withText("返回")).perform(click());waitText("新对话");onView(withText("新对话")).perform(click());
            onView(withText("添加项目文件夹")).perform(click());waitText("选择此文件夹");onView(withText("新建文件夹")).perform(click());
            onView(withHint("文件夹名称")).perform(replaceText("AndroidFixture"));onView(withId(android.R.id.button1)).perform(click());
            waitText("选择此文件夹");onView(withText("选择此文件夹")).perform(click());waitText("安卓新项目");
            onView(withText("发送")).perform(click());waitText("安卓原生对话已连接");
        }
        try(ActivityScenario<MainActivity> reopened=ActivityScenario.launch(MainActivity.class)){waitText("Android Test PC");}
        context.getSharedPreferences("connections",0).edit().clear().commit();
    }
}
