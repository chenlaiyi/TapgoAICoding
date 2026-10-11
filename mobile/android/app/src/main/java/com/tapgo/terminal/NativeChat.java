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
    private final MobileComposer composerView;
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
    private MobileBalances funds=new MobileBalances();
    private String selectedProvider;
    private long balanceRevision;
    private android.app.AlertDialog balanceDialog;
    NativeChat(MainActivity activity,LinearLayout root,RemoteClient client,ExecutorService worker,Handler handler,String id,String title,String origin,Runnable back,Runnable workspace){
        this.activity=activity;this.client=client;this.worker=worker;this.handler=handler;this.id=id;this.origin=origin;
        markdown=Markwon.builder(activity).usePlugin(TablePlugin.create(activity)).usePlugin(new AbstractMarkwonPlugin(){@Override public void configureConfiguration(MarkwonConfiguration.Builder builder){builder.linkResolver((view,link)->{Uri uri=Uri.parse(link);if("https".equals(uri.getScheme())){try{activity.startActivity(new Intent(Intent.ACTION_VIEW,uri));}catch(android.content.ActivityNotFoundException unavailable){Toast.makeText(activity,R.string.file_unavailable,Toast.LENGTH_LONG).show();}}});}}).build();
        LinearLayout toolbar=new LinearLayout(activity);toolbar.addView(button(R.string.back,back));toolbar.addView(button(R.string.workspace,workspace));toolbar.addView(button(R.string.settings,this::settings));root.addView(toolbar);
        TextView heading=text(title);heading.setTypeface(null,Typeface.BOLD);root.addView(heading);status=text(activity.getString(R.string.loading));root.addView(status);
        scroll=new ScrollView(activity);transcript=new LinearLayout(activity);transcript.setOrientation(LinearLayout.VERTICAL);scroll.addView(transcript);root.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout attachments=new LinearLayout(activity);photoPreview=new ImageView(activity);photoPreview.setScaleType(ImageView.ScaleType.CENTER_CROP);int previewSize=(int)(80*activity.getResources().getDisplayMetrics().density);attachments.addView(photoPreview,new LinearLayout.LayoutParams(previewSize,previewSize));removePhoto=button(R.string.remove_photo,this::clearPhoto);attachments.addView(removePhoto);root.addView(attachments);photoPreview.setVisibility(View.GONE);removePhoto.setVisibility(View.GONE);
        composerView=new MobileComposer(activity,R.string.photo,activity::pickChatPhoto,this::models,this::permissions,this::send,()->rpc("session/cancel",request(new JSONObject()),()->{}));
        composer=composerView.input;model=composerView.model;balanceView=composerView.balance;permission=composerView.permission;send=composerView.send;stop=composerView.stop;root.addView(composerView);connect();loadSettings();
    }
    private Button button(int label,Runnable action){Button b=new Button(activity);b.setText(label);b.setAllCaps(false);b.setTextSize(13);b.setTextColor(activity.getColor(R.color.primary));UiStyles.button(b);b.setOnClickListener(v->action.run());return b;}
    private TextView text(String value){TextView t=new TextView(activity);t.setText(value);t.setTextSize(16);t.setTextColor(activity.getColor(R.color.primary));t.setPadding(0,12,0,12);t.setTextIsSelectable(true);return t;}
    private JSONObject request(JSONObject fields){try{fields.put("sessionId",id);return new JSONObject().put("request",fields);}catch(JSONException exception){throw new IllegalStateException(exception);}}
    private void connect(){long current=++epoch;worker.execute(()->{try{client.authenticate();handler.post(()->{if(closed||paused||current!=epoch)return;String stream=UUID.randomUUID().toString();socket=client.events(new WebSocketListener(){
        @Override public void onOpen(WebSocket ws,Response response){try{ws.send(new JSONObject().put("type","open").put("streamId",stream).put("endpoint","session/follow").put("payload",new JSONObject().put("args",new JSONObject().put("request",new JSONObject().put("address",new JSONObject().put("kind","session").put("sessionId",id)).put("assistantStream",true)))).toString());}catch(JSONException exception){ws.cancel();handler.post(()->reconnect(current));}}
        @Override public void onMessage(WebSocket ws,String raw){handler.post(()->{if(closed||paused||current!=epoch)return;try{JSONObject frame=new JSONObject(raw);if(!stream.equals(frame.optString("streamId")))return;if(frame.optString("type").equals("error")){ws.cancel();reconnect(current);return;}if(frame.optString("type").equals("item")){JSONObject value=frame.getJSONObject("value");state.receive(value);JSONObject event=value.optJSONObject("event");
            if(event!=null&&event.optString("type").equals("model/selection")){JSONObject choice=event.optJSONObject("data");if(choice!=null)selectProvider(choice.optString("provider"));}
            if(event!=null&&event.optString("type").equals("turn/end"))refreshBalances();retry=0;status.setText(R.string.connected);render();}}catch(JSONException exception){ws.cancel();reconnect(current);}});}
        @Override public void onFailure(WebSocket ws,Throwable error,Response response){handler.post(()->reconnect(current));}
        @Override public void onClosed(WebSocket ws,int code,String reason){handler.post(()->reconnect(current));}
    });});}catch(Exception exception){handler.post(()->reconnect(current));}});}
    private void reconnect(long current){if(closed||paused||current!=epoch)return;epoch++;if(socket!=null){socket.cancel();socket=null;}status.setText(R.string.connecting_chat);long scheduled=epoch;handler.postDelayed(()->{if(!closed&&!paused&&scheduled==epoch)connect();},Math.min(30,1<<Math.min(retry++,5))*1000L);}
    void pause(){paused=true;epoch++;if(socket!=null){socket.cancel();socket=null;}}
    void resume(){if(paused&&!closed){paused=false;connect();refreshBalances();}}
    void close(){closed=true;pause();clearPhoto();}
    private void clearPhoto(){photo=null;photoPreview.setImageDrawable(null);photoPreview.setVisibility(View.GONE);removePhoto.setVisibility(View.GONE);if(previewBitmap!=null){previewBitmap.recycle();previewBitmap=null;}}
    private void render(){if(closed)return;
        JSONObject selection=state.projections.optJSONObject("modelSelection");JSONObject next=selection==null?null:selection.optJSONObject("next");if(next!=null){String id=next.optString("model");selectProvider(next.optString("provider"));for(int i=0;i<models.length();i++){JSONObject candidate=models.optJSONObject(i);if(candidate.optString("id").equals(id)&&candidate.optString("provider").equals(next.optString("provider"))){model.setText(ModelDisplay.name(candidate.optString("name",id),id));break;}}}
        JSONObject access=state.projections.optJSONObject("permissions");if(access!=null)for(int i=0;i<permissions.length();i++){JSONObject preset=permissions.optJSONObject(i);if(preset.optString("value").equals(access.optString("currentValue"))){permission.setContentDescription(preset.optString("name"));break;}}
        boolean atBottom=scroll.getChildAt(0)==null||scroll.getScrollY()+scroll.getHeight()>=scroll.getChildAt(0).getHeight()-80;transcript.removeAllViews();
        for(ChatProjection.Line line:state.lines){if(line.role.equals("turn")){String process=state.process(line);if(!process.isEmpty()){transcript.addView(button(R.string.reasoning,()->{if(!expandedTurns.add(line))expandedTurns.remove(line);render();}));if(expandedTurns.contains(line))transcript.addView(text(process));}continue;}TextView view=text(line.text);if(line.role.equals("assistant"))markdown.setMarkdown(view,line.text);else{GradientDrawable bg=new GradientDrawable();bg.setColor(0xff1767c7);bg.setCornerRadius(18);view.setTextColor(0xffffffff);view.setPadding(18,12,18,12);view.setBackground(bg);}transcript.addView(view);}
        if(!state.live.isEmpty()){TextView live=text("");markdown.setMarkdown(live,state.live);transcript.addView(live);}composerView.running(state.running);if(atBottom)scroll.post(()->scroll.fullScroll(View.FOCUS_DOWN));
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
            handler.post(()->{if(!closed){JSONObject selection=state.projections.optJSONObject("modelSelection");JSONObject next=selection==null?null:selection.optJSONObject("next");JSONObject fallback=catalog.optJSONObject("default");selectProvider(next!=null?next.optString("provider"):fallback==null?null:fallback.optString("provider"));refreshBalances();}});
        }catch(Exception exception){handler.post(()->{if(!closed)status.setText(R.string.no_models);});}});}
    private void selectProvider(String provider){
        if(Objects.equals(provider,selectedProvider))return;
        selectedProvider=provider;balanceRevision++;
        if(provider!=null&&!provider.equals("deepseek-account"))funds.providers.remove(provider);
        showBalance();refreshBalances();
    }
    private void showBalance(){String amount=funds.available(selectedProvider);balanceView.setText(amount==null?activity.getString(R.string.balance_unavailable):activity.getString(R.string.balance,amount));}
    private void refreshBalances(){
        long revision=++balanceRevision;String provider=selectedProvider;
        worker.execute(()->{MobileBalances value=MobileBalances.load(client,provider);handler.post(()->{if(closed||revision!=balanceRevision)return;funds=value;showBalance();if(balanceDialog!=null&&balanceDialog.isShowing())balanceDialog.setMessage(settingsSummary());});});
    }
    private String settingsSummary(){
        JSONObject usage=state.projections.optJSONObject("tokenUsage"),pressure=state.projections.optJSONObject("contextPressure");
        StringBuilder summary=new StringBuilder(funds.summary(activity));
        if(usage!=null){long total=0;for(String key:new String[]{"uncachedInputTokens","outputTokens","cacheReadTokens","cacheWriteTokens"})total+=usage.optLong(key);summary.append("\n").append(activity.getString(R.string.token_usage,total));}
        if(pressure!=null){long window=pressure.optLong("contextWindow");summary.append("\n").append(activity.getString(R.string.context_budget,Math.max(0,window-pressure.optLong("projectedTokens")),window));}
        return summary.toString();
    }
    private void settings(){
        balanceDialog=new android.app.AlertDialog.Builder(activity).setTitle(R.string.settings).setMessage(settingsSummary()).setPositiveButton(R.string.model,(d,w)->models()).setNeutralButton(R.string.permission,(d,w)->permissions()).setNegativeButton(R.string.close,null).create();
        balanceDialog.show();refreshBalances();
    }
    private void models(){if(models.length()==0){Toast.makeText(activity,R.string.no_models,Toast.LENGTH_LONG).show();loadSettings();return;}String[] names=new String[models.length()];for(int i=0;i<names.length;i++)names[i]=models.optJSONObject(i).optString("name",models.optJSONObject(i).optString("id"));new android.app.AlertDialog.Builder(activity).setTitle(R.string.model).setItems(names,(d,index)->{JSONObject chosen=models.optJSONObject(index);try{rpc("session/selectModel",request(new JSONObject().put("provider",chosen.getString("provider")).put("model",chosen.getString("id"))),()->{selectProvider(chosen.optString("provider"));refreshBalances();model.setText(ModelDisplay.name(chosen.optString("name"),chosen.optString("id")));try{activity.getSharedPreferences("models",0).edit().putString(origin,new JSONObject().put("provider",chosen.getString("provider")).put("model",chosen.getString("id")).toString()).apply();}catch(JSONException exception){status.setText(R.string.no_models);}});}catch(JSONException exception){status.setText(R.string.no_models);}}).show();}
    private void permissions(){if(permissions.length()==0){Toast.makeText(activity,R.string.no_permissions,Toast.LENGTH_LONG).show();return;}String[] names=new String[permissions.length()];for(int i=0;i<names.length;i++)names[i]=permissions.optJSONObject(i).optString("name",permissions.optJSONObject(i).optString("value"));new android.app.AlertDialog.Builder(activity).setTitle(R.string.permission).setItems(names,(d,index)->{JSONObject chosen=permissions.optJSONObject(index);new android.app.AlertDialog.Builder(activity).setTitle(names[index]).setMessage(chosen.optString("description")).setNegativeButton(R.string.cancel,null).setPositiveButton(R.string.submit,(x,y)->{try{rpc("commands/execute",new JSONObject().put("agentId",id).put("line","/permission "+chosen.getString("value")).put("submittedAttachments",new JSONArray()),()->permission.setContentDescription(names[index]));}catch(JSONException exception){status.setText(R.string.no_permissions);}}).show();}).show();}
    private void rpc(String method,JSONObject args,Runnable done){worker.execute(()->{try{JSONObject result=client.rpc(method,args);if(method.equals("commands/execute")&&(result.optJSONObject("result")==null||!result.optJSONObject("result").optString("kind").equals("success")))throw new java.io.IOException("Command rejected");handler.post(()->{if(!closed)done.run();});}catch(Exception exception){handler.post(()->{if(!closed)status.setText(R.string.delivery_error);});}});}
}
