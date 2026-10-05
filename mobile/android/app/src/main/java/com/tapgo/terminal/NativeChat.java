package com.tapgo.terminal;
import android.content.*;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Handler;
import android.view.View;
import android.view.inputmethod.InputMethodManager;
import android.widget.*;
import io.noties.markwon.*;
import io.noties.markwon.ext.tables.TablePlugin;
import okhttp3.*;
import org.json.*;
import java.util.*;
import java.util.concurrent.ExecutorService;

/** Native conversation, live follow stream and model/permission controls using the iOS RPCs. */
final class NativeChat {
    private final MainActivity activity;
    private final RemoteClient client;
    private final ExecutorService worker;
    private final Handler handler;
    private final String id,origin;
    private final ChatProjection state=new ChatProjection();
    private final LinearLayout transcript;
    private final ScrollView scroll;
    private final TextView status,balanceView;
    private final EditText composer;
    private final Button send,stop,model,permission,removePhoto;
    private final ImageView photoPreview;
    private android.graphics.Bitmap previewBitmap;
    private final Markwon markdown;
    private JSONArray models=new JSONArray(),permissions=new JSONArray();
    private boolean closed,paused,sending;
    private final Set<ChatProjection.Line> expandedTurns=Collections.newSetFromMap(new IdentityHashMap<>());
    private long epoch;
    private int retry;
    private WebSocket socket;
    private byte[] photo;
    private String walletDetails="";
    NativeChat(MainActivity activity,LinearLayout root,RemoteClient client,ExecutorService worker,Handler handler,String id,String title,String origin,Runnable back,Runnable workspace){
        this.activity=activity;this.client=client;this.worker=worker;this.handler=handler;this.id=id;this.origin=origin;
        markdown=Markwon.builder(activity).usePlugin(TablePlugin.create(activity)).usePlugin(new AbstractMarkwonPlugin(){@Override public void configureConfiguration(MarkwonConfiguration.Builder builder){builder.linkResolver((view,link)->{Uri uri=Uri.parse(link);if("https".equals(uri.getScheme())){try{activity.startActivity(new Intent(Intent.ACTION_VIEW,uri));}catch(android.content.ActivityNotFoundException unavailable){Toast.makeText(activity,R.string.file_unavailable,Toast.LENGTH_LONG).show();}}});}}).build();
        LinearLayout toolbar=new LinearLayout(activity);toolbar.addView(button(R.string.back,back));toolbar.addView(button(R.string.workspace,workspace));toolbar.addView(button(R.string.settings,this::settings));root.addView(toolbar);
        TextView heading=text(title);heading.setTypeface(null,Typeface.BOLD);root.addView(heading);status=text(activity.getString(R.string.loading));root.addView(status);balanceView=text("");balanceView.setTextSize(13);balanceView.setTextColor(activity.getColor(R.color.secondary));root.addView(balanceView);
        scroll=new ScrollView(activity);transcript=new LinearLayout(activity);transcript.setOrientation(LinearLayout.VERTICAL);scroll.addView(transcript);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout controls=new LinearLayout(activity);model=button(R.string.model,this::models);permission=button(R.string.permission,this::permissions);controls.addView(model);controls.addView(permission);controls.addView(button(R.string.photo,activity::pickChatPhoto));root.addView(controls);
        LinearLayout attachments=new LinearLayout(activity);photoPreview=new ImageView(activity);photoPreview.setScaleType(ImageView.ScaleType.CENTER_CROP);int previewSize=(int)(80*activity.getResources().getDisplayMetrics().density);attachments.addView(photoPreview,new LinearLayout.LayoutParams(previewSize,previewSize));removePhoto=button(R.string.remove_photo,this::clearPhoto);attachments.addView(removePhoto);root.addView(attachments);photoPreview.setVisibility(View.GONE);removePhoto.setVisibility(View.GONE);
        composer=new EditText(activity);composer.setHint(R.string.message_hint);composer.setMinLines(1);composer.setMaxLines(5);composer.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE);root.addView(composer);
        LinearLayout actions=new LinearLayout(activity);send=button(R.string.send,this::send);stop=button(R.string.stop,()->rpc("session/cancel",request(new JSONObject()),()->{}));actions.addView(send);actions.addView(stop);actions.addView(button(R.string.dismiss_keyboard,()->((InputMethodManager)activity.getSystemService(Context.INPUT_METHOD_SERVICE)).hideSoftInputFromWindow(composer.getWindowToken(),0)));root.addView(actions);connect();loadSettings();
    }
    private Button button(int label,Runnable action){Button b=new Button(activity);b.setText(label);b.setAllCaps(false);b.setTextSize(13);b.setTextColor(activity.getColor(R.color.primary));UiStyles.button(b);b.setOnClickListener(v->action.run());return b;}
    private TextView text(String value){TextView t=new TextView(activity);t.setText(value);t.setTextSize(16);t.setTextColor(activity.getColor(R.color.primary));t.setPadding(0,12,0,12);t.setTextIsSelectable(true);return t;}
    private JSONObject request(JSONObject fields){try{fields.put("sessionId",id);return new JSONObject().put("request",fields);}catch(JSONException exception){throw new IllegalStateException(exception);}}
    private void connect(){long current=++epoch;worker.execute(()->{try{client.authenticate();handler.post(()->{if(closed||paused||current!=epoch)return;String stream=UUID.randomUUID().toString();socket=client.events(new WebSocketListener(){
        @Override public void onOpen(WebSocket ws,Response response){try{ws.send(new JSONObject().put("type","open").put("streamId",stream).put("endpoint","session/follow").put("payload",new JSONObject().put("args",new JSONObject().put("request",new JSONObject().put("address",new JSONObject().put("kind","session").put("sessionId",id)).put("assistantStream",true)))).toString());}catch(JSONException exception){ws.cancel();handler.post(()->reconnect(current));}}
        @Override public void onMessage(WebSocket ws,String raw){handler.post(()->{if(closed||paused||current!=epoch)return;try{JSONObject frame=new JSONObject(raw);if(!stream.equals(frame.optString("streamId")))return;if(frame.optString("type").equals("error")){ws.cancel();reconnect(current);return;}if(frame.optString("type").equals("item")){state.receive(frame.getJSONObject("value"));retry=0;status.setText(R.string.connected);render();}}catch(JSONException exception){ws.cancel();reconnect(current);}});}
        @Override public void onFailure(WebSocket ws,Throwable error,Response response){handler.post(()->reconnect(current));}
        @Override public void onClosed(WebSocket ws,int code,String reason){handler.post(()->reconnect(current));}
    });});}catch(Exception exception){handler.post(()->reconnect(current));}});}
    private void reconnect(long current){if(closed||paused||current!=epoch)return;epoch++;if(socket!=null){socket.cancel();socket=null;}status.setText(R.string.connecting_chat);long scheduled=epoch;handler.postDelayed(()->{if(!closed&&!paused&&scheduled==epoch)connect();},Math.min(30,1<<Math.min(retry++,5))*1000L);}
    void pause(){paused=true;epoch++;if(socket!=null){socket.cancel();socket=null;}}
    void resume(){if(paused&&!closed){paused=false;connect();}}
    void close(){closed=true;pause();clearPhoto();}
    private void clearPhoto(){photo=null;photoPreview.setImageDrawable(null);photoPreview.setVisibility(View.GONE);removePhoto.setVisibility(View.GONE);if(previewBitmap!=null){previewBitmap.recycle();previewBitmap=null;}}
    private void render(){if(closed)return;
        JSONObject selection=state.projections.optJSONObject("modelSelection");JSONObject next=selection==null?null:selection.optJSONObject("next");if(next!=null){String id=next.optString("model");for(int i=0;i<models.length();i++){JSONObject candidate=models.optJSONObject(i);if(candidate.optString("id").equals(id)&&candidate.optString("provider").equals(next.optString("provider"))){model.setText(ModelDisplay.name(candidate.optString("name",id),id));break;}}}
        JSONObject access=state.projections.optJSONObject("permissions");if(access!=null)for(int i=0;i<permissions.length();i++){JSONObject preset=permissions.optJSONObject(i);if(preset.optString("value").equals(access.optString("currentValue"))){permission.setText(preset.optString("name"));break;}}
        boolean atBottom=scroll.getChildAt(0)==null||scroll.getScrollY()+scroll.getHeight()>=scroll.getChildAt(0).getHeight()-80;transcript.removeAllViews();
        for(ChatProjection.Line line:state.lines){if(line.role.equals("turn")){String process=state.process(line);if(!process.isEmpty()){transcript.addView(button(R.string.reasoning,()->{if(!expandedTurns.add(line))expandedTurns.remove(line);render();}));if(expandedTurns.contains(line))transcript.addView(text(process));}continue;}TextView view=text(line.text);if(line.role.equals("assistant"))markdown.setMarkdown(view,line.text);else{GradientDrawable bg=new GradientDrawable();bg.setColor(0xff1767c7);bg.setCornerRadius(18);view.setTextColor(0xffffffff);view.setPadding(18,12,18,12);view.setBackground(bg);}transcript.addView(view);}
        if(!state.live.isEmpty()){TextView live=text("");markdown.setMarkdown(live,state.live);transcript.addView(live);}stop.setEnabled(state.running);if(atBottom)scroll.post(()->scroll.fullScroll(View.FOCUS_DOWN));
    }
    void photo(Uri uri){worker.execute(()->{try(java.io.InputStream input=activity.getContentResolver().openInputStream(uri)){if(input==null)throw new java.io.IOException();java.io.ByteArrayOutputStream bytes=new java.io.ByteArrayOutputStream();byte[] buffer=new byte[8192];int n;while((n=input.read(buffer))!=-1){bytes.write(buffer,0,n);if(bytes.size()>12*1024*1024)throw new java.io.IOException();}byte[] data=bytes.toByteArray();android.graphics.BitmapFactory.Options options=new android.graphics.BitmapFactory.Options();options.inJustDecodeBounds=true;android.graphics.BitmapFactory.decodeByteArray(data,0,data.length,options);options.inSampleSize=1;while(options.outWidth/options.inSampleSize>2048||options.outHeight/options.inSampleSize>2048)options.inSampleSize*=2;options.inJustDecodeBounds=false;android.graphics.Bitmap bitmap=android.graphics.BitmapFactory.decodeByteArray(data,0,data.length,options);if(bitmap==null)throw new java.io.IOException();java.io.ByteArrayOutputStream jpeg=new java.io.ByteArrayOutputStream();bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG,85,jpeg);bitmap.recycle();byte[] encoded=jpeg.toByteArray();android.graphics.BitmapFactory.Options previewOptions=new android.graphics.BitmapFactory.Options();previewOptions.inSampleSize=8;android.graphics.Bitmap preview=android.graphics.BitmapFactory.decodeByteArray(encoded,0,encoded.length,previewOptions);handler.post(()->{if(closed){if(preview!=null)preview.recycle();return;}clearPhoto();photo=encoded;previewBitmap=preview;photoPreview.setImageBitmap(preview);photoPreview.setVisibility(View.VISIBLE);removePhoto.setVisibility(View.VISIBLE);status.setText(R.string.photo_ready);});}catch(Exception exception){handler.post(()->{if(!closed)Toast.makeText(activity,R.string.photo_error,Toast.LENGTH_LONG).show();});}});}
    void prefill(String value){composer.setText(value);if(!value.trim().isEmpty())send();}
    private void send(){String message=composer.getText().toString().trim();if(sending||(message.isEmpty()&&photo==null))return;sending=true;send.setEnabled(false);byte[] attachment=photo;
        try{JSONArray content=new JSONArray();if(!message.isEmpty())content.put(new JSONObject().put("type","text").put("text",message));if(attachment!=null)content.put(new JSONObject().put("type","image").put("mediaType","image/jpeg").put("data",android.util.Base64.encodeToString(attachment,android.util.Base64.NO_WRAP)));
            JSONObject payload=request(new JSONObject().put("requestId",UUID.randomUUID().toString()).put("mode","queue").put("content",content).put("clientTimeZone",TimeZone.getDefault().getID()));
            worker.execute(()->{try{client.rpc("session/prompt",payload);handler.post(()->{if(closed)return;sending=false;send.setEnabled(true);composer.setText("");clearPhoto();});}catch(Exception exception){handler.post(()->{if(closed)return;sending=false;send.setEnabled(true);status.setText(R.string.send_failed);});}});
        }catch(JSONException exception){sending=false;send.setEnabled(true);status.setText(R.string.send_failed);}
    }
    private void loadSettings(){worker.execute(()->{try{JSONObject catalog=client.rpc("session/modelCatalog",new JSONObject());JSONArray all=new JSONArray();JSONArray groups=catalog.optJSONArray("groups");if(groups!=null)for(int i=0;i<groups.length();i++){JSONObject group=groups.getJSONObject(i);JSONArray rows=group.optJSONArray("models");if(rows!=null)for(int j=0;j<rows.length();j++)all.put(new JSONObject(rows.getJSONObject(j).toString()).put("provider",group.getString("id")));}JSONArray access=client.rpc("permissionPresets/catalog",new JSONObject()).optJSONArray("options");handler.post(()->{if(closed)return;models=all;permissions=access==null?new JSONArray():access;});
            try{AccountBalance account=AccountBalance.read(client.account());handler.post(()->{if(!closed){walletDetails=account==null?"":activity.getString(R.string.recharge_balance,AccountBalance.format(account.recharge))+"\n"+activity.getString(R.string.bonus_balance,AccountBalance.format(account.bonus));balanceView.setText(account==null?"":activity.getString(R.string.balance,account.total()));}});}catch(Exception unavailable){handler.post(()->{if(!closed)balanceView.setText(R.string.balance_unavailable);});}
        }catch(Exception exception){handler.post(()->{if(!closed)status.setText(R.string.no_models);});}});}
    private void settings(){
        JSONObject usage=state.projections.optJSONObject("tokenUsage"),pressure=state.projections.optJSONObject("contextPressure");
        StringBuilder summary=new StringBuilder(balanceView.getText());summary.append("\n").append(walletDetails);
        if(usage!=null){long total=0;for(String key:new String[]{"uncachedInputTokens","outputTokens","cacheReadTokens","cacheWriteTokens"})total+=usage.optLong(key);summary.append("\n").append(activity.getString(R.string.token_usage,total));}
        if(pressure!=null){long window=pressure.optLong("contextWindow");summary.append("\n").append(activity.getString(R.string.context_budget,Math.max(0,window-pressure.optLong("projectedTokens")),window));}
        new android.app.AlertDialog.Builder(activity).setTitle(R.string.settings).setMessage(summary.toString()).setPositiveButton(R.string.model,(d,w)->models()).setNeutralButton(R.string.permission,(d,w)->permissions()).setNegativeButton(R.string.close,null).show();
    }
    private void models(){if(models.length()==0){Toast.makeText(activity,R.string.no_models,Toast.LENGTH_LONG).show();loadSettings();return;}String[] names=new String[models.length()];for(int i=0;i<names.length;i++)names[i]=models.optJSONObject(i).optString("name",models.optJSONObject(i).optString("id"));new android.app.AlertDialog.Builder(activity).setTitle(R.string.model).setItems(names,(d,index)->{JSONObject chosen=models.optJSONObject(index);try{rpc("session/selectModel",request(new JSONObject().put("provider",chosen.getString("provider")).put("model",chosen.getString("id"))),()->{model.setText(ModelDisplay.name(chosen.optString("name"),chosen.optString("id")));try{activity.getSharedPreferences("models",0).edit().putString(origin,new JSONObject().put("provider",chosen.getString("provider")).put("model",chosen.getString("id")).toString()).apply();}catch(JSONException exception){status.setText(R.string.no_models);}});}catch(JSONException exception){status.setText(R.string.no_models);}}).show();}
    private void permissions(){if(permissions.length()==0){Toast.makeText(activity,R.string.no_permissions,Toast.LENGTH_LONG).show();return;}String[] names=new String[permissions.length()];for(int i=0;i<names.length;i++)names[i]=permissions.optJSONObject(i).optString("name",permissions.optJSONObject(i).optString("value"));new android.app.AlertDialog.Builder(activity).setTitle(R.string.permission).setItems(names,(d,index)->{JSONObject chosen=permissions.optJSONObject(index);new android.app.AlertDialog.Builder(activity).setTitle(names[index]).setMessage(chosen.optString("description")).setNegativeButton(R.string.cancel,null).setPositiveButton(R.string.submit,(x,y)->{try{rpc("commands/execute",new JSONObject().put("agentId",id).put("line","/permission "+chosen.getString("value")).put("submittedAttachments",new JSONArray()),()->permission.setText(names[index]));}catch(JSONException exception){status.setText(R.string.no_permissions);}}).show();}).show();}
    private void rpc(String method,JSONObject args,Runnable done){worker.execute(()->{try{JSONObject result=client.rpc(method,args);if(method.equals("commands/execute")&&(result.optJSONObject("result")==null||!result.optJSONObject("result").optString("kind").equals("success")))throw new java.io.IOException("Command rejected");handler.post(()->{if(!closed)done.run();});}catch(Exception exception){handler.post(()->{if(!closed)status.setText(R.string.delivery_error);});}});}
}
