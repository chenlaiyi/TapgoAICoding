package com.tapgo.terminal;

import android.app.Activity;
import android.app.AlertDialog;
import android.os.Handler;
import android.widget.Toast;
import org.json.JSONArray;
import org.json.JSONObject;
import org.json.JSONException;
import java.util.concurrent.ExecutorService;
import java.util.function.BooleanSupplier;

/** Model, permission and balance preview for an uncreated conversation. */
final class NewConversationComposer {
    final MobileComposer view;
    private final Activity activity;
    private final RemoteClient client;
    private final ExecutorService worker;
    private final Handler handler;
    private final String origin;
    private final BooleanSupplier active;
    private JSONArray models=new JSONArray(),presets=new JSONArray();
    private String permission;
    private int balanceRevision;

    NewConversationComposer(Activity activity,RemoteClient client,ExecutorService worker,Handler handler,
                            String origin,BooleanSupplier active,Runnable browse,Runnable submit) {
        this.activity=activity;this.client=client;this.worker=worker;this.handler=handler;this.origin=origin;this.active=active;
        view=new MobileComposer(activity,R.string.add_project,browse,this::chooseModel,this::choosePermission,submit,()->{});
        view.balance.setText(R.string.balance_unavailable);
    }
    String permission(){return permission;}
    void submitting(boolean value){view.input.setEnabled(!value);view.model.setEnabled(!value);view.permission.setEnabled(!value);view.send.setEnabled(!value);}
    void load(){
        worker.execute(()->{try {
            JSONObject catalog=client.rpc("session/modelCatalog",new JSONObject());
            JSONArray all=new JSONArray(),groups=catalog.optJSONArray("groups");
            if(groups!=null)for(int i=0;i<groups.length();i++) {
                JSONObject group=groups.getJSONObject(i);JSONArray rows=group.optJSONArray("models");
                if(rows!=null)for(int j=0;j<rows.length();j++)all.put(new JSONObject(rows.getJSONObject(j).toString()).put("provider",group.getString("id")));
            }
            JSONArray options=client.rpc("permissionPresets/catalog",new JSONObject()).optJSONArray("options");
            handler.post(()->{if(!active.getAsBoolean())return;
                models=all;presets=options==null?new JSONArray():options;
                try {
                    String saved=activity.getSharedPreferences("models",0).getString(origin,null);
                    JSONObject selection=saved==null?catalog.optJSONObject("default"):new JSONObject(saved);
                    if(selection!=null) {
                        if(saved==null)remember(selection);
                        for(int i=0;i<models.length();i++) {
                            JSONObject item=models.optJSONObject(i);
                            if(item.optString("provider").equals(selection.optString("provider"))&&item.optString("id").equals(selection.optString("model")))showModel(item);
                        }
                    }
                    updateBalance();
                }catch(JSONException invalid){unavailable(R.string.no_models);}
            });
        }catch(Exception failure){handler.post(()->unavailable(R.string.no_models));}});
    }
    private void remember(JSONObject selection){activity.getSharedPreferences("models",0).edit().putString(origin,selection.toString()).apply();}
    private void showModel(JSONObject item){view.model.setText(ModelDisplay.name(item.optString("name"),item.optString("id")));}
    private void chooseModel(){
        if(models.length()==0){unavailable(R.string.no_models);return;}
        String[] labels=new String[models.length()];for(int i=0;i<labels.length;i++)labels[i]=models.optJSONObject(i).optString("name");
        new AlertDialog.Builder(activity).setTitle(R.string.model).setItems(labels,(dialog,index)->{
            JSONObject chosen=models.optJSONObject(index);
            try{remember(new JSONObject().put("provider",chosen.getString("provider")).put("model",chosen.getString("id")));showModel(chosen);updateBalance();}
            catch(JSONException invalid){unavailable(R.string.no_models);}
        }).show();
    }
    private void choosePermission(){
        if(presets.length()==0){unavailable(R.string.no_permissions);return;}
        String[] labels=new String[presets.length()];for(int i=0;i<labels.length;i++)labels[i]=presets.optJSONObject(i).optString("name");
        new AlertDialog.Builder(activity).setTitle(R.string.permission).setItems(labels,(dialog,index)->{
            permission=presets.optJSONObject(index).optString("value");view.permission.setContentDescription(labels[index]);
        }).show();
    }
    private void updateBalance(){
        int revision=++balanceRevision;String provider;
        try{String saved=activity.getSharedPreferences("models",0).getString(origin,null);provider=saved==null?null:new JSONObject(saved).optString("provider");}
        catch(JSONException invalid){unavailable(R.string.no_models);return;}
        view.balance.setText(R.string.balance_unavailable);
        worker.execute(()->{MobileBalances value=MobileBalances.load(client,provider);handler.post(()->{
            if(!active.getAsBoolean()||revision!=balanceRevision)return;
            String amount=value.available(provider);view.balance.setText(amount==null?activity.getString(R.string.balance_unavailable):activity.getString(R.string.balance,amount));
        });});
    }
    private void unavailable(int message){if(active.getAsBoolean())Toast.makeText(activity,message,Toast.LENGTH_LONG).show();}
}
