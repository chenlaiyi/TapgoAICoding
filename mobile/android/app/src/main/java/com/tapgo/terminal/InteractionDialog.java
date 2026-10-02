package com.tapgo.terminal;

import android.app.AlertDialog;
import android.widget.*;
import org.json.*;
import java.util.*;

/** Explicit allow/reject/defer and complete question answers, delivered before dismissing. */
final class InteractionDialog {
    static void show(MainActivity activity,JSONObject event,InteractionStream stream){
        String id=event.optString("eventId");JSONObject request=event.optJSONObject("request");if(request==null)return;
        if(event.optString("event").equals("approval/request")){
            JSONObject reason=request.optJSONObject("displayReason");String message=request.optString("toolName")+"\n"+(reason==null?request.optString("reason"):reason.optString("zh",request.optString("reason")));
            AlertDialog d=new AlertDialog.Builder(activity).setTitle(R.string.approval).setMessage(message).setCancelable(false)
                    .setPositiveButton(R.string.allow_once,null).setNegativeButton(R.string.reject,null).setNeutralButton(R.string.defer,null).create();
            d.setOnShowListener(v->{d.getButton(-1).setOnClickListener(x->send(stream,id,"allowed-once",d));d.getButton(-2).setOnClickListener(x->send(stream,id,"rejected",d));d.getButton(-3).setOnClickListener(x->defer(stream,id,d));});stream.dialog=d;d.show();return;
        }
        JSONArray questions=request.optJSONArray("questions");if(questions==null||questions.length()==0)return;
        LinearLayout content=new LinearLayout(activity);content.setOrientation(LinearLayout.VERTICAL);int padding=(int)(24*activity.getResources().getDisplayMetrics().density);content.setPadding(padding,0,padding,0);
        List<List<CompoundButton>> options=new ArrayList<>();List<EditText> custom=new ArrayList<>();List<CheckBox> skips=new ArrayList<>();
        for(int i=0;i<questions.length();i++){
            JSONObject question=questions.optJSONObject(i);if(question==null)return;TextView title=new TextView(activity);title.setText(question.optString("question"));title.setTextSize(18);content.addView(title);
            TextView detail=new TextView(activity);detail.setText(question.optString("detail"));content.addView(detail);
            List<CompoundButton> choices=new ArrayList<>();boolean multiple=question.optBoolean("multiSelect");RadioGroup radios=new RadioGroup(activity);JSONArray declared=question.optJSONArray("options");
            if(declared!=null)for(int j=0;j<declared.length();j++){JSONObject option=declared.optJSONObject(j);if(option==null)continue;CompoundButton button=multiple?new CheckBox(activity):new RadioButton(activity);button.setId(android.view.View.generateViewId());button.setText(option.optString("label"));choices.add(button);if(multiple)content.addView(button);else radios.addView(button);}
            if(!multiple)content.addView(radios);options.add(choices);EditText other=new EditText(activity);other.setHint(R.string.other_answer);content.addView(other);custom.add(other);CheckBox skip=new CheckBox(activity);skip.setText(R.string.skip_question);content.addView(skip);skips.add(skip);skip.setOnCheckedChangeListener((button,checked)->{for(CompoundButton choice:choices){if(checked)choice.setChecked(false);choice.setEnabled(!checked);}other.setEnabled(!checked);if(checked)other.setText("");});
        }
        ScrollView scroll=new ScrollView(activity);scroll.addView(content);AlertDialog d=new AlertDialog.Builder(activity).setTitle(R.string.question).setView(scroll).setCancelable(false).setPositiveButton(R.string.submit,null).setNeutralButton(R.string.defer,null).create();
        d.setOnShowListener(v->{d.getButton(-3).setOnClickListener(x->defer(stream,id,d));d.getButton(-1).setOnClickListener(x->{try{JSONArray answers=new JSONArray();for(int i=0;i<questions.length();i++){JSONArray selected=new JSONArray();for(CompoundButton option:options.get(i))if(option.isChecked())selected.put(option.getText().toString());String other=custom.get(i).getText().toString().trim();if(selected.length()==0&&other.isEmpty()&&!skips.get(i).isChecked()){custom.get(i).setError(activity.getString(R.string.required_answer));return;}JSONObject answer=new JSONObject().put("id",questions.getJSONObject(i).getString("id")).put("selected",selected);if(!other.isEmpty())answer.put("custom",other);answers.put(answer);}stream.answer(id,new JSONObject().put("kind","result").put("value",new JSONObject().put("answers",answers)),d::dismiss);}catch(JSONException exception){android.widget.Toast.makeText(activity,R.string.delivery_error,android.widget.Toast.LENGTH_LONG).show();}});});stream.dialog=d;d.show();
    }
    private static void send(InteractionStream stream,String id,String result,AlertDialog dialog){try{stream.answer(id,new JSONObject().put("kind","result").put("value",result),dialog::dismiss);}catch(JSONException exception){throw new IllegalStateException(exception);}}
    private static void defer(InteractionStream stream,String id,AlertDialog dialog){try{stream.answer(id,new JSONObject().put("kind","next"),dialog::dismiss);}catch(JSONException exception){throw new IllegalStateException(exception);}}
}
