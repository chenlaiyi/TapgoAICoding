package com.tapgo.terminal;

import android.app.AlertDialog;
import android.content.ClipboardManager;
import android.content.Intent;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.*;
import android.widget.*;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import com.google.zxing.integration.android.IntentIntegrator;
import com.google.zxing.integration.android.IntentResult;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Native pairing/home shell; conversation and workspace capabilities use the shipped Host client. */
public final class MainActivity extends AppCompatActivity {
    private ComputerStore store;
    private RemoteClient client;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private final Handler handler = new Handler(Looper.getMainLooper());
    private LinearLayout root, list;
    private TextView status,homeBalance;
    private EditText search;
    private JSONArray sessions = new JSONArray();
    private JSONArray workspaces=new JSONArray();
    private WebView web;
    private ValueCallback<Uri[]> fileResult;
    private long generation;
    private boolean foreground, loading, groupProjects;
    private InteractionStream interactions;
    private NativeChat chat;
    private final Runnable refreshLoop = new Runnable() {
        public void run() { if (foreground && web == null && store != null && store.current() != null) refresh(); handler.postDelayed(this, 15000); }
    };
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private int color(int value) { return getColor(value); }
    private TextView text(String value, int size) {
        TextView view = new TextView(this); view.setText(value); view.setTextSize(size); view.setTextColor(color(R.color.primary)); view.setPadding(0, dp(6), 0, dp(6)); return view;
    }
    private Button button(int title, Runnable action) {
        Button view = new Button(this); view.setText(title); view.setAllCaps(false); view.setTextColor(color(R.color.primary)); UiStyles.button(view); view.setOnClickListener(v -> action.run()); return view;
    }
    private LinearLayout column() { LinearLayout value = new LinearLayout(this); value.setOrientation(LinearLayout.VERTICAL); return value; }
    private void base() {
        if(chat!=null){chat.close();chat=null;}
        if (web != null) { web.stopLoading(); web.destroy(); web = null; }
        root = column(); root.setBackgroundColor(color(R.color.background)); root.setPadding(dp(24), 0, dp(24), 0); setContentView(root);
        ViewCompat.setOnApplyWindowInsetsListener(root, (view, insets) -> {
            androidx.core.graphics.Insets bars = insets.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.ime());
            view.setPadding(dp(24) + bars.left, bars.top, dp(24) + bars.right, bars.bottom); return insets;
        });
        ViewCompat.requestApplyInsets(root);
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state); CookieManager.getInstance().setAcceptCookie(true);
        try { store = new ComputerStore(this); } catch (Exception exception) { storageFailure(); return; }
        if (getIntent().getData() != null) { pair(getIntent().getData().toString()); } else showHome();
        getOnBackPressedDispatcher().addCallback(this, new androidx.activity.OnBackPressedCallback(true) {
            public void handleOnBackPressed() { if(chat!=null){showHome();}else if (web != null) { if (web.canGoBack()) web.goBack(); else showHome(); } else moveTaskToBack(true); }
        });
    }
    @Override protected void onNewIntent(Intent intent) { super.onNewIntent(intent); setIntent(intent); if (intent.getData() != null) pair(intent.getData().toString()); }
    @Override protected void onResume() { super.onResume(); foreground = true; handler.removeCallbacks(refreshLoop); handler.post(refreshLoop); if (interactions != null && web == null) interactions.start(); if(chat!=null)chat.resume(); }
    @Override protected void onPause() { foreground = false; if(chat!=null)chat.pause(); handler.removeCallbacks(refreshLoop); if (interactions != null) interactions.stop(); CookieManager.getInstance().flush(); super.onPause(); }
    @Override protected void onDestroy() {
        handler.removeCallbacksAndMessages(null); if (interactions != null) interactions.stop(); if (client != null) client.close(); worker.shutdownNow();
        if (fileResult != null) { fileResult.onReceiveValue(null); fileResult = null; } if (web != null) web.destroy(); if(chat!=null)chat.close(); super.onDestroy();
    }
    private void storageFailure() { new AlertDialog.Builder(this).setMessage(R.string.storage_error).setPositiveButton(R.string.close, (d,w) -> finish()).setCancelable(false).show(); }
    private void notice(int message) { Toast.makeText(this, message, Toast.LENGTH_LONG).show(); }
    private boolean persist() {
        try { store.save(); return true; } catch (Exception exception) { try { store = new ComputerStore(this); } catch (Exception recovery) { storageFailure(); } notice(R.string.storage_error); return false; }
    }
    private void brand() {
        LinearLayout header = new LinearLayout(this); header.setGravity(android.view.Gravity.CENTER_VERTICAL); header.setPadding(0, dp(32), 0, dp(32));
        ImageView image = new ImageView(this); image.setImageResource(R.drawable.brand_mark); header.addView(image, new LinearLayout.LayoutParams(dp(48), dp(48)));
        TextView name = text(getString(R.string.app_name), 28); name.setTypeface(null, Typeface.BOLD); name.setPadding(dp(12), 0, 0, 0); header.addView(name); root.addView(header);
    }
    private void showHome() {
        generation++; loading = false; sessions = new JSONArray(); if (interactions != null) interactions.stop(); interactions = null;
        if (client != null) client.close(); client = store.current() == null ? null : new RemoteClient(store.current()); base();
        if (store.current() == null) { showWelcome(); return; }
        LinearLayout toolbar = new LinearLayout(this);
        toolbar.addView(button(R.string.switch_computer, this::selectComputer)); toolbar.addView(button(R.string.settings, this::settings)); root.addView(toolbar);
        TextView name = text(store.current().name(), 23); name.setTypeface(null, Typeface.BOLD); root.addView(name);
        status = text(getString(R.string.loading), 13); status.setTextColor(color(R.color.secondary)); root.addView(status);homeBalance=text("",13);homeBalance.setTextColor(color(R.color.secondary));root.addView(homeBalance);
        search = new EditText(this); search.setSingleLine(true); search.setHint(R.string.search); root.addView(search);
        search.addTextChangedListener(new android.text.TextWatcher() {
            public void beforeTextChanged(CharSequence s,int start,int count,int after) {}
            public void onTextChanged(CharSequence s,int start,int before,int count) { renderSessions(); }
            public void afterTextChanged(android.text.Editable value) {}
        });
        LinearLayout actions = new LinearLayout(this); actions.addView(button(R.string.refresh, this::refresh)); actions.addView(button(R.string.sort_project, () -> { groupProjects = !groupProjects; renderSessions(); })); root.addView(actions);
        ScrollView scroll = new ScrollView(this); list = column(); scroll.addView(list); root.addView(scroll, new LinearLayout.LayoutParams(-1,0,1));
        root.addView(button(R.string.new_chat, this::newChat)); root.addView(button(R.string.workspace, () -> openWorkspace(null, false)));
        interactions = new InteractionStream(this, client, worker, handler, generation); if (foreground) interactions.start(); refresh();
    }
    private void showWelcome() {
        brand(); root.addView(new View(this), new LinearLayout.LayoutParams(1,0,1));
        TextView slogan = text(getString(R.string.slogan), 22); slogan.setTypeface(null, Typeface.BOLD); root.addView(slogan);
        TextView description = text(getString(R.string.description), 21); description.setTextColor(color(R.color.secondary)); root.addView(description);
        TextView help = text(getString(R.string.connect_help), 16); help.setTextColor(color(R.color.secondary)); help.setPadding(0,dp(24),0,dp(24)); root.addView(help);
        Button connect = button(R.string.connect_computer, this::connectionDialog); connect.setTextColor(color(R.color.inverse));
        GradientDrawable background = new GradientDrawable(); background.setColor(color(R.color.primary)); background.setCornerRadius(dp(12)); connect.setBackground(background); root.addView(connect);
        for (ComputerStore.Computer c : store.computers) { Button saved = new Button(this); saved.setText(c.name()); saved.setAllCaps(false); saved.setOnClickListener(v -> { store.active=c.origin; if (persist()) showHome(); }); root.addView(saved); }
        root.addView(new View(this), new LinearLayout.LayoutParams(1,0,1));
    }
    private void pair(String value) {
        try { store.pair(PairingLink.parse(value)); showHome(); }
        catch (IllegalArgumentException exception) { notice(R.string.invalid_link); }
        catch (Exception exception) { notice(R.string.storage_error); try { store=new ComputerStore(this); } catch(Exception recovery) { storageFailure(); } }
        if(root==null && store!=null) showHome();
    }
    private void connectionDialog() {
        LinearLayout form = column(); form.setPadding(dp(24),0,dp(24),0);
        EditText input = new EditText(this); input.setHint(R.string.link_hint); input.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_VARIATION_URI); form.addView(input);
        form.addView(button(R.string.paste, () -> { ClipboardManager cb=(ClipboardManager)getSystemService(CLIPBOARD_SERVICE); if(cb.hasPrimaryClip() && cb.getPrimaryClip().getItemCount()>0) input.setText(cb.getPrimaryClip().getItemAt(0).coerceToText(this)); }));
        form.addView(button(R.string.scan, () -> new IntentIntegrator(this).setDesiredBarcodeFormats(Collections.singletonList("QR_CODE")).setPrompt(getString(R.string.scan)).setBeepEnabled(false).setOrientationLocked(false).initiateScan()));
        AlertDialog dialog = new AlertDialog.Builder(this).setTitle(R.string.connect_computer).setView(form).setNegativeButton(R.string.cancel,null).setPositiveButton(R.string.connect,null).create();
        dialog.setOnShowListener(d -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> { try { PairingLink.parse(input.getText().toString()); dialog.dismiss(); pair(input.getText().toString()); } catch(IllegalArgumentException exception) { input.setError(getString(R.string.invalid_link)); } })); dialog.show();
    }
    private void selectComputer() {
        String[] names=new String[store.computers.size()+1]; for(int i=0;i<store.computers.size();i++) names[i]=store.computers.get(i).name(); names[names.length-1]=getString(R.string.connect_computer);
        new AlertDialog.Builder(this).setTitle(R.string.switch_computer).setItems(names,(d,index)-> { if(index==store.computers.size()) connectionDialog(); else {store.active=store.computers.get(index).origin; if(persist()) showHome();} }).show();
    }
    private void settings() {
        ComputerStore.Computer c=store.current(); if(c==null) return;
        new AlertDialog.Builder(this).setTitle(c.name()).setMessage(c.origin).setPositiveButton(R.string.rename,(d,w)-> {
            EditText input=new EditText(this); input.setText(c.name()); AlertDialog rename=new AlertDialog.Builder(this).setTitle(R.string.rename).setView(input).setNegativeButton(R.string.cancel,null).setPositiveButton(R.string.save,null).create();
            rename.setOnShowListener(x->rename.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{String value=input.getText().toString().trim(); if(value.isEmpty()||value.length()>80){input.setError(getString(R.string.name_error));return;}c.customName=value;if(persist()){rename.dismiss();showHome();}}));rename.show();
        }).setNeutralButton(R.string.connect_computer,(d,w)->connectionDialog()).setNegativeButton(R.string.remove,(d,w)->new AlertDialog.Builder(this).setMessage(R.string.remove_confirm).setNegativeButton(R.string.cancel,null).setPositiveButton(R.string.remove,(x,y)-> {
            store.computers.remove(c); store.active=null; if(persist()) { showHome(); }
        }).show()).show();
    }
    private void refresh() {
        if(client==null||loading||web!=null||chat!=null) return; loading=true; long current=generation; RemoteClient remote=client;
        worker.execute(()-> { try { JSONArray rows=remote.rpc("session/list",new JSONObject().put("_request",new JSONObject())).getJSONArray("items");JSONArray projects=remote.baseline().getJSONArray("items");handler.post(()-> {if(current!=generation)return;loading=false;workspaces=projects;sessions=rows;status.setText(R.string.connected);renderSessions();});
            try{AccountBalance balance=AccountBalance.read(remote.account());handler.post(()->{if(current==generation&&chat==null&&web==null)homeBalance.setText(balance==null?"":getString(R.string.balance,balance.total()));});}catch(Exception unavailable){handler.post(()->{if(current==generation&&chat==null&&web==null)homeBalance.setText("");});}
        }
            catch(Exception exception){handler.post(()->{if(current!=generation)return;loading=false;status.setText(exception instanceof RemoteClient.Expired?R.string.expired:R.string.unavailable);});} });
    }
    private void renderSessions() {
        if(list==null || search==null || web!=null) return; list.removeAllViews(); String query=search.getText().toString().trim().toLowerCase(Locale.ROOT); List<JSONObject> rows=new ArrayList<>();
        for(int i=0;i<sessions.length();i++){JSONObject row=sessions.optJSONObject(i);if(row!=null && row.optString("cwd","").length()>0 && (title(row)+row.optString("cwd")).toLowerCase(Locale.ROOT).contains(query)) rows.add(row);}
        rows.sort((a,b)->groupProjects?a.optString("cwd").compareTo(b.optString("cwd")):Double.compare(b.optDouble("updatedAt"),a.optDouble("updatedAt")));
        String project=null;
        for(JSONObject row:rows){String cwd=row.optString("cwd");if(groupProjects&&!cwd.equals(project)){project=cwd;TextView label=text(cwd,14);label.setTextColor(color(R.color.secondary));list.addView(label);}
            Button item=new Button(this);item.setAllCaps(false);item.setGravity(android.view.Gravity.START);item.setText(getString(R.string.session_row,title(row),row.optBoolean("running")?getString(R.string.running_tag):"",cwd));UiStyles.button(item);item.setOnClickListener(v->openChat(row.optString("sessionId"),title(row)));list.addView(item);}
        if(rows.isEmpty())list.addView(text(getString(R.string.empty),16));
    }
    private String title(JSONObject row){JSONObject p=row.optJSONObject("projections");JSONObject values=p==null?null:p.optJSONObject("values");return values==null?getString(R.string.untitled):values.optString("title",getString(R.string.untitled));}
    private Spinner projectPicker;
    private void newChat(){
        LinearLayout form=column();EditText input=new EditText(this);input.setHint(R.string.message_hint);form.addView(input);
        Spinner projects=new Spinner(this);projectPicker=projects;List<String> names=new ArrayList<>();names.add(getString(R.string.other_project));for(int i=0;i<workspaces.length();i++)names.add(workspaces.optJSONObject(i).optString("title"));projects.setAdapter(new ArrayAdapter<>(this,android.R.layout.simple_spinner_dropdown_item,names));form.addView(projects);
        Button browse=button(R.string.add_project,()->browseDirectory(null));form.addView(browse);
        AlertDialog dialog=new AlertDialog.Builder(this).setTitle(R.string.new_chat).setView(form).setNegativeButton(R.string.cancel,null).setPositiveButton(R.string.send,null).create();
        dialog.setOnShowListener(d->dialog.getButton(-1).setOnClickListener(v->{dialog.getButton(-1).setEnabled(false);RemoteClient remote=client;long current=generation;String connectionOrigin=store.current().origin;String message=input.getText().toString();JSONObject project=projects.getSelectedItemPosition()==0?null:workspaces.optJSONObject(projects.getSelectedItemPosition()-1);
            worker.execute(()->{try{JSONObject request=new JSONObject();if(project!=null)request.put("workspaceId",project.getString("workspaceId"));String id=remote.rpc("session/create",new JSONObject().put("request",request)).getString("sessionId");String remembered=getSharedPreferences("models",0).getString(connectionOrigin,null);if(remembered!=null){JSONObject choice=new JSONObject(remembered);remote.rpc("session/selectModel",new JSONObject().put("request",choice.put("sessionId",id)));}
                handler.post(()->{if(current!=generation)return;dialog.dismiss();openChat(id,getString(R.string.new_chat));chat.prefill(message);});
            }catch(Exception exception){handler.post(()->{if(current!=generation)return;dialog.getButton(-1).setEnabled(true);notice(R.string.unavailable);});}});
        }));dialog.setOnDismissListener(d->{if(projectPicker==projects)projectPicker=null;});dialog.show();
    }
    private void browseDirectory(String path){
        RemoteClient remote=client;long current=generation;
        worker.execute(()->{try{
            JSONObject args=new JSONObject();if(path!=null)args.put("path",path);
            JSONObject listing=remote.rpc("directoryPicker/list",args);
            handler.post(()->{if(current!=generation)return;
                List<String> names=new ArrayList<>(),paths=new ArrayList<>();
                names.add(getString(R.string.select_directory));paths.add(listing.optString("path"));
                JSONArray crumbs=listing.optJSONArray("crumbs");if(crumbs!=null&&crumbs.length()>1){names.add(getString(R.string.parent_directory));paths.add(crumbs.optJSONObject(crumbs.length()-2).optString("path"));}
                JSONArray entries=listing.optJSONArray("entries");if(entries!=null)for(int i=0;i<entries.length();i++){JSONObject entry=entries.optJSONObject(i);if(entry==null||entry.optBoolean("hidden"))continue;names.add(entry.optString("name"));paths.add(entry.optString("path"));}
                new AlertDialog.Builder(this).setTitle(listing.optString("path")).setItems(names.toArray(new String[0]),(d,index)->{if(index==0)registerProject(paths.get(0));else browseDirectory(paths.get(index));}).setNeutralButton(R.string.create_directory,(d,w)->createDirectory(listing.optString("path"))).setNegativeButton(R.string.cancel,null).show();
            });
        }catch(Exception exception){handler.post(()->{if(current==generation)notice(R.string.unavailable);});}});
    }
    private void createDirectory(String parent){
        EditText input=new EditText(this);input.setSingleLine(true);input.setHint(R.string.directory_name);
        AlertDialog dialog=new AlertDialog.Builder(this).setTitle(R.string.create_directory).setView(input).setNegativeButton(R.string.cancel,null).setPositiveButton(R.string.create_directory,null).create();
        dialog.setOnShowListener(d->dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->{
            String name=input.getText().toString().trim();if(name.isEmpty()||name.equals(".")||name.equals("..")||name.contains("/")||name.contains("\\")){input.setError(getString(R.string.invalid_directory));return;}
            RemoteClient remote=client;long current=generation;dialog.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(false);
            worker.execute(()->{try{Object value=remote.rpcValue("directoryPicker/createDirectory",new JSONObject().put("path",parent).put("name",name));if(!(value instanceof String))throw new java.io.IOException("Expected directory path");handler.post(()->{if(current==generation){dialog.dismiss();browseDirectory((String)value);}});}catch(Exception exception){handler.post(()->{if(current==generation){dialog.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(true);input.setError(getString(R.string.unavailable));}});}});
        }));dialog.show();
    }
    private void registerProject(String path){RemoteClient remote=client;long current=generation;worker.execute(()->{try{JSONObject project=remote.rpc("workspace/create",new JSONObject().put("request",new JSONObject().put("path",path))).getJSONObject("workspace");handler.post(()->{if(current!=generation)return;workspaces.put(project);if(projectPicker!=null){List<String> names=new ArrayList<>();names.add(getString(R.string.other_project));for(int i=0;i<workspaces.length();i++)names.add(workspaces.optJSONObject(i).optString("title"));projectPicker.setAdapter(new ArrayAdapter<>(this,android.R.layout.simple_spinner_dropdown_item,names));projectPicker.setSelection(workspaces.length());}notice(R.string.project_added);});}catch(Exception exception){handler.post(()->notice(R.string.unavailable));}});}
    private void openChat(String id,String title){
        if(interactions!=null)interactions.stop();long current=++generation;loading=false;base();
        chat=new NativeChat(this,root,client,worker,handler,id,title,store.current().origin,this::showHome,()->openWorkspace(id,false));
        interactions=new InteractionStream(this,client,worker,handler,current);if(foreground)interactions.start();
    }
    void pickChatPhoto(){try{startActivityForResult(new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/*"),502);}catch(android.content.ActivityNotFoundException exception){notice(R.string.file_unavailable);}}
    private void openWorkspace(String sessionId, boolean newChat) {
        ComputerStore.Computer c=store.current();if(c==null)return;long current=++generation;loading=false;if(interactions!=null)interactions.stop();
        RemoteClient remote=client;worker.execute(()->{try{remote.authenticate();handler.post(()->{if(current!=generation)return;showWorkspace(c,sessionId,newChat);});}catch(Exception exception){handler.post(()->{if(current!=generation)return;notice(exception instanceof RemoteClient.Expired?R.string.expired:R.string.unavailable);showHome();});}});
    }
    @SuppressWarnings("SetJavaScriptEnabled")
    private void showWorkspace(ComputerStore.Computer c,String sessionId,boolean newChat) {
        base();root.addView(button(R.string.back,this::showHome));web=new WebView(this);WebSettings settings=web.getSettings();settings.setJavaScriptEnabled(true);settings.setDomStorageEnabled(true);settings.setAllowFileAccess(false);settings.setAllowContentAccess(false);settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);settings.setMediaPlaybackRequiresUserGesture(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web,false);WebView.setWebContentsDebuggingEnabled(BuildConfig.DEBUG);
        String script=sessionId==null?(newChat?"localStorage.removeItem('dsh.sessions.current');":"") : "localStorage.setItem('dsh.sessions.current',"+JSONObject.quote("{\"sessionId\":"+JSONObject.quote(sessionId)+"}")+");";
        boolean early=WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT);
        if(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT) && !script.isEmpty())WebViewCompat.addDocumentStartJavaScript(web,script,Collections.singleton(c.origin));
        web.setWebViewClient(new WebViewClient(){boolean selected=early||script.isEmpty();
            public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request){if(PairingLink.sameOrigin(c.origin,request.getUrl().toString()))return false;notice(R.string.origin_blocked);return true;}
            public void onPageFinished(WebView view,String url){if(!selected&&PairingLink.sameOrigin(c.origin,url)){selected=true;view.evaluateJavascript(script,result->view.reload());}CookieManager.getInstance().flush();}
            public void onReceivedHttpError(WebView view,WebResourceRequest request,WebResourceResponse response){if(request.isForMainFrame()&&response.getStatusCode()==401){notice(R.string.expired);showHome();}}
            public void onReceivedError(WebView view,WebResourceRequest request,WebResourceError error){if(request.isForMainFrame()){new AlertDialog.Builder(MainActivity.this).setMessage(R.string.unavailable).setPositiveButton(R.string.retry,(d,w)->view.reload()).setNegativeButton(R.string.back,(d,w)->showHome()).show();}}
        });
        web.setWebChromeClient(new WebChromeClient(){public boolean onShowFileChooser(WebView view,ValueCallback<Uri[]> callback,FileChooserParams params){if(fileResult!=null)fileResult.onReceiveValue(null);fileResult=callback;Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*").putExtra(Intent.EXTRA_ALLOW_MULTIPLE,params.getMode()==FileChooserParams.MODE_OPEN_MULTIPLE);try{startActivityForResult(intent,501);}catch(android.content.ActivityNotFoundException exception){callback.onReceiveValue(null);fileResult=null;notice(R.string.file_unavailable);}return true;}});
        root.addView(web,new LinearLayout.LayoutParams(-1,0,1));web.loadUrl(c.origin+"/");
    }
    @Override protected void onActivityResult(int request,int result,Intent data){super.onActivityResult(request,result,data);
        if(request==502){if(result==RESULT_OK&&data!=null&&data.getData()!=null&&"content".equals(data.getData().getScheme())&&chat!=null)chat.photo(data.getData());return;}
        if(request==501){if(fileResult!=null){List<Uri> values=new ArrayList<>();if(result==RESULT_OK&&data!=null){if(data.getClipData()!=null){for(int i=0;i<data.getClipData().getItemCount();i++){Uri uri=data.getClipData().getItemAt(i).getUri();if("content".equals(uri.getScheme()))values.add(uri);}}else if(data.getData()!=null&&"content".equals(data.getData().getScheme()))values.add(data.getData());}fileResult.onReceiveValue(values.isEmpty()?null:values.toArray(new Uri[0]));fileResult=null;}return;}
        IntentResult scan=IntentIntegrator.parseActivityResult(request,result,data);if(scan!=null&&scan.getContents()!=null)pair(scan.getContents());
    }
    boolean acceptsInteraction(long current){return current==generation&&foreground&&web==null&&!isFinishing();}
    void interaction(JSONObject event,InteractionStream stream){InteractionDialog.show(this,event,stream);}
}
