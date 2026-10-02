package com.tapgo.terminal;

import android.webkit.CookieManager;
import okhttp3.*;
import org.json.JSONObject;
import java.io.IOException;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

/** Same authenticated RPC envelope as the iOS client, sharing durable WebView cookies. */
final class RemoteClient {
    static final class Expired extends IOException {}
    final OkHttpClient http = new OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS).followRedirects(false).followSslRedirects(false).pingInterval(20, TimeUnit.SECONDS).build();
    private final ComputerStore.Computer computer;
    RemoteClient(ComputerStore.Computer computer) { this.computer = computer; }
    private Request.Builder request(String url) {
        Request.Builder result = new Request.Builder().url(url);
        String cookie = CookieManager.getInstance().getCookie(computer.origin);
        if (cookie != null) result.header("Cookie", cookie);
        return result;
    }
    private void cookies(Response response) {
        for (String value : response.headers("Set-Cookie")) CookieManager.getInstance().setCookie(computer.origin, value);
        CookieManager.getInstance().flush();
    }
    void authenticate() throws IOException {
        String url=computer.url;
        for(int redirects=0;redirects<5;redirects++){
            try(Response response=http.newCall(request(url).build()).execute()){
                cookies(response);
                if(response.code()==401||response.code()==403)throw new Expired();
                if(response.isSuccessful())return;
                if(response.code()==301||response.code()==302||response.code()==303||response.code()==307||response.code()==308){
                    String location=response.header("Location");HttpUrl next=location==null?null:response.request().url().resolve(location);
                    if(next==null||!PairingLink.sameOrigin(computer.origin,next.toString()))throw new IOException("Authentication redirect outside paired origin");
                    url=next.toString();continue;
                }
                throw new IOException("Authentication failed");
            }
        }
        throw new IOException("Authentication redirect limit reached");
    }
    JSONObject rpc(String method, JSONObject args) throws Exception {
        Object value=rpcValue(method,args);
        if(value==null||value==JSONObject.NULL)return new JSONObject();
        if(value instanceof JSONObject)return (JSONObject)value;
        throw new IOException("Expected object RPC result");
    }
    Object rpcValue(String method, JSONObject args) throws Exception {
        JSONObject envelope = new JSONObject().put("type", "client-request").put("rpcId", UUID.randomUUID().toString())
                .put("method", method).put("payload", new JSONObject().put("args", args));
        RequestBody body = RequestBody.create(envelope.toString(), MediaType.get("application/json"));
        for (int attempt = 0; attempt < 2; attempt++) {
            try (Response response = http.newCall(request(computer.origin + "/api/" + method).post(body).build()).execute()) {
                cookies(response);
                if (response.code() == 401) { if (attempt == 0) { authenticate(); continue; } throw new Expired(); }
                if (!response.isSuccessful() || response.body() == null) throw new IOException("RPC unavailable");
                JSONObject result = new JSONObject(response.body().string()).getJSONObject("result");
                if (!result.getBoolean("ok")) throw new IOException("RPC refused");
                return result.opt("value");
            }
        }
        throw new Expired();
    }
    JSONObject account() throws Exception {
        return rpc("account/getBalance",new JSONObject().put("client",new JSONObject().put("version",BuildConfig.VERSION_NAME).put("locale",java.util.Locale.getDefault().toLanguageTag()).put("timezoneOffsetSeconds",java.util.TimeZone.getDefault().getOffset(System.currentTimeMillis())/1000)));
    }
    WebSocket events(WebSocketListener listener) {
        return http.newWebSocket(request(computer.origin.replaceFirst("https:", "wss:") + "/api/remote.mux").build(), listener);
    }
    JSONObject baseline() throws Exception {
        java.util.concurrent.CountDownLatch done=new java.util.concurrent.CountDownLatch(1);
        java.util.concurrent.atomic.AtomicReference<JSONObject> result=new java.util.concurrent.atomic.AtomicReference<>();
        String stream=UUID.randomUUID().toString();
        WebSocket socket=events(new WebSocketListener(){
            @Override public void onOpen(WebSocket ws,Response response){try{ws.send(new JSONObject().put("type","open").put("streamId",stream).put("endpoint","workspace/follow").put("payload",new JSONObject().put("args",new JSONObject())).toString());}catch(Exception exception){done.countDown();}}
            @Override public void onMessage(WebSocket ws,String raw){try{JSONObject frame=new JSONObject(raw);JSONObject value=frame.optJSONObject("value");if(stream.equals(frame.optString("streamId"))&&value!=null&&value.optString("type").equals("baseline")){result.set(value.getJSONObject("value"));done.countDown();}}catch(Exception exception){done.countDown();}}
            @Override public void onFailure(WebSocket ws,Throwable error,Response response){done.countDown();}
        });
        try{if(!done.await(8,TimeUnit.SECONDS)||result.get()==null)throw new IOException("Workspace baseline unavailable");return result.get();}finally{socket.cancel();}
    }
    void close() { http.dispatcher().cancelAll(); http.dispatcher().executorService().execute(() -> http.connectionPool().evictAll()); }
}
