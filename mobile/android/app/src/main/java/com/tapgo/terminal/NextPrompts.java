package com.tapgo.terminal;

import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.List;

/** Latest-turn recommendations recovered from the Host; no method submits a message. */
final class NextPrompts {
    int turn=-1;
    boolean failed;
    final List<String> prompts=new ArrayList<>();
    void reset(){turn=-1;failed=false;prompts.clear();}
    void consume(String type,JSONObject data){
        if(type.equals("turn/start")){reset();turn=data.optInt("turn",-1);}
        else if(type.equals("session/next-prompts-result")&&turn>=0&&data.optInt("turn",-1)==turn)restore(data,false);
    }
    void restore(JSONObject value,boolean running){
        if(running||value==null||value.optInt("turn",-1)<0)return;
        String status=value.optString("status");
        if(!status.equals("idle")&&!status.equals("ready")&&!status.equals("error"))return;
        JSONArray raw=value.optJSONArray("prompts");if(raw==null||raw.length()>3)return;
        List<String> parsed=new ArrayList<>();
        for(int i=0;i<raw.length();i++){
            Object item=raw.opt(i);if(!(item instanceof String))return;
            String prompt=((String)item).trim();if(prompt.isEmpty())return;
            if(!parsed.contains(prompt))parsed.add(prompt);
        }
        turn=value.optInt("turn");failed=status.equals("error");prompts.clear();
        if(status.equals("ready"))prompts.addAll(parsed);
    }
    static String appending(String prompt,String draft){return draft.isEmpty()?prompt:draft+"\n\n"+prompt;}
}
