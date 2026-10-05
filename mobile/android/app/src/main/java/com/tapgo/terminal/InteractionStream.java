package com.tapgo.terminal;

import android.os.Handler;
import okhttp3.*;
import org.json.JSONObject;
import java.util.LinkedHashMap;
import java.util.UUID;
import java.util.concurrent.ExecutorService;

/** Foreground Host confirmations with bounded reconnects and generation-owned callbacks. */
final class InteractionStream {
    private final MainActivity activity;
    private final RemoteClient client;
    private final ExecutorService worker;
    private final Handler handler;
    private final long generation;
    private final LinkedHashMap<String,JSONObject> pending=new LinkedHashMap<>();
    private WebSocket socket;
    private String clientId;
    private String streamId;
    private boolean stopped=true, showing, sending;
    private int retry;
    private long epoch;
    android.app.AlertDialog dialog;
    InteractionStream(MainActivity activity,RemoteClient client,ExecutorService worker,Handler handler,long generation){this.activity=activity;this.client=client;this.worker=worker;this.handler=handler;this.generation=generation;}
    void start(){if(!stopped)return;stopped=false;connect();}
    void stop(){stopped=true;sending=false;epoch++;if(socket!=null){socket.cancel();socket=null;}clientId=null;pending.clear();showing=false;if(dialog!=null){dialog.dismiss();dialog=null;}}
    private void connect(){long current=++epoch;worker.execute(()->{
        try{client.authenticate();handler.post(()->{if(stopped||current!=epoch)return;streamId=UUID.randomUUID().toString();socket=client.events(new WebSocketListener(){
            @Override public void onOpen(WebSocket ws,Response response){handler.post(()->{if(stopped||current!=epoch){ws.cancel();return;}try{ws.send(new JSONObject().put("type","open").put("streamId",streamId).put("endpoint","$events").put("payload",new JSONObject().put("args",new JSONObject())).toString());}catch(Exception exception){ws.cancel();reconnect(current);}});}
            @Override public void onMessage(WebSocket ws,String message){handler.post(()->{if(stopped||current!=epoch)return;try{
                JSONObject frame=new JSONObject(message);if(!streamId.equals(frame.optString("streamId")))return;
                if(frame.optString("type").equals("error")){ws.cancel();reconnect(current);return;}if(!frame.optString("type").equals("item"))return;
                JSONObject value=frame.getJSONObject("value");String type=value.optString("type");
                if(type.equals("ready")){clientId=value.getString("clientId");retry=0;showNext();}
                else if(type.equals("cancel")){String id=value.optString("eventId");boolean currentDialog=!pending.isEmpty()&&pending.keySet().iterator().next().equals(id);pending.remove(id);if(currentDialog){if(dialog!=null)dialog.dismiss();showing=false;showNext();}}
                else if(type.equals("waterfall")&&value.has("request")&&(value.optString("event").equals("approval/request")||value.optString("event").equals("user-questions/request"))){pending.put(value.getString("eventId"),value);showNext();}
            }catch(Exception exception){ws.cancel();reconnect(current);}});}
            @Override public void onFailure(WebSocket ws,Throwable error,Response response){handler.post(()->reconnect(current));}
            @Override public void onClosed(WebSocket ws,int code,String reason){handler.post(()->reconnect(current));}
        });});}catch(Exception exception){handler.post(()->reconnect(current));}
    });}
    private void reconnect(long current){if(stopped||current!=epoch)return;epoch++;clientId=null;if(socket!=null){socket.cancel();socket=null;}int delay=Math.min(30,1<<Math.min(retry++,5));long scheduled=epoch;handler.postDelayed(()->{if(!stopped&&scheduled==epoch)connect();},delay*1000L);}
    private void showNext(){if(showing||clientId==null||pending.isEmpty()||!activity.acceptsInteraction(generation))return;showing=true;activity.interaction(pending.values().iterator().next(),this);}
    void answer(String id,JSONObject outcome,Runnable delivered){if(sending)return;if(clientId==null){android.widget.Toast.makeText(activity,R.string.delivery_error,android.widget.Toast.LENGTH_LONG).show();return;}sending=true;String recipient=clientId;long current=epoch;worker.execute(()->{
        try{client.rpc("$events/result",new JSONObject().put("clientId",recipient).put("eventId",id).put("outcome",outcome));handler.post(()->{if(stopped||current!=epoch)return;sending=false;pending.remove(id);delivered.run();showing=false;showNext();});}
        catch(Exception exception){handler.post(()->{sending=false;if(!stopped)android.widget.Toast.makeText(activity,R.string.delivery_error,android.widget.Toast.LENGTH_LONG).show();});}
    });}
}
