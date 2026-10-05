package com.tapgo.terminal;
import org.json.*;
import java.util.*;

/** Projects compact session/follow events without displaying tool arguments or hidden record types. */
final class ChatProjection {
    static final class Line { final String role; String text; String reasoning=""; final LinkedHashMap<String,String> tools=new LinkedHashMap<>(); Line(String role,String text){this.role=role;this.text=text;} }
    final List<Line> lines=new ArrayList<>();
    final Set<Long> seen=new HashSet<>();
    String live="",reasoning="",activity="";
    boolean running;
    JSONObject projections=new JSONObject();
    Line currentTurn;
    String liveReasoning="";
    String process(Line line){StringBuilder value=new StringBuilder(line.reasoning);for(String tool:line.tools.values())value.append("\n").append(tool);if(line==currentTurn&&!liveReasoning.isEmpty())value.append("\n").append(liveReasoning);return value.toString().trim();}
    private void recordedReasoning(String value){if(value.isEmpty())return;if(!liveReasoning.isEmpty()&&reasoning.endsWith(liveReasoning))reasoning=reasoning.substring(0,reasoning.length()-liveReasoning.length());reasoning+=value;if(currentTurn!=null)currentTurn.reasoning+=value;liveReasoning="";}
    void receive(JSONObject value) throws JSONException {
        if(value.optString("type").equals("snapshot")){
            lines.clear();seen.clear();reasoning="";activity="";live="";running=false;currentTurn=null;liveReasoning="";
            JSONArray records=value.optJSONArray("records");if(records!=null)for(int i=0;i<records.length();i++)consume(records.getJSONObject(i).optJSONObject("event"));
            JSONObject assistant=value.optJSONObject("assistantStream");JSONObject attempt=assistant==null?null:assistant.optJSONObject("activeAttempt");if(attempt!=null){running=true;live=streamText(attempt.optJSONArray("stream"),"text");liveReasoning=streamText(attempt.optJSONArray("stream"),"reasoning");reasoning+=liveReasoning;}
            JSONObject p=value.optJSONObject("projections");if(p!=null&&p.optJSONObject("values")!=null)projections=p.getJSONObject("values");
        } else if(value.optJSONObject("event")!=null){consume(value.getJSONObject("event"));}
        else if(value.optString("type").equals("assistant-stream") && value.optJSONObject("frame")!=null){JSONObject stream=value.getJSONObject("frame");String type=stream.optString("type");if(type.equals("start")){live="";running=true;}else if(type.equals("chunk")){JSONObject chunk=stream.optJSONObject("chunk");if(chunk!=null){if(chunk.optString("type").equals("text-delta"))live+=chunk.optString("text");if(chunk.optString("type").equals("reasoning-delta")){String valueText=chunk.optString("text");reasoning+=valueText;liveReasoning+=valueText;}}}else if(type.equals("end")){JSONObject outcome=stream.optJSONObject("outcome");if(outcome!=null&&outcome.optString("kind").equals("abandoned")){live="";running=false;}}}
    }
    private void consume(JSONObject event) throws JSONException {
        if(event==null||!event.has("seq")||!seen.add(event.getLong("seq")))return;String type=event.optString("type");JSONObject data=event.optJSONObject("data");if(data==null)return;
        if(type.equals("turn/start")){running=true;currentTurn=new Line("turn","");lines.add(currentTurn);return;}if(type.equals("turn/end")){running=false;live="";if(currentTurn!=null)currentTurn.reasoning+=liveReasoning;liveReasoning="";return;}
        if(type.equals("tool/call")){String name=data.optString("name");activity+=name+"\n";if(currentTurn!=null)currentTurn.tools.put(data.optString("callId",Long.toString(event.getLong("seq"))),"… "+name);return;}
        if(type.equals("tool/result")){JSONObject message=data.optJSONObject("message");if(message!=null){JSONObject source=message.optJSONObject("source");String id=source==null?message.optString("toolCallId"):source.optString("callId",message.optString("toolCallId"));for(int i=lines.size()-1;i>=0;i--){Line turn=lines.get(i);String previous=turn.tools.get(id);if(previous!=null){boolean failed=message.optBoolean("isError");JSONArray blocks=message.optJSONArray("content");if(blocks!=null)for(int j=0;j<blocks.length();j++){JSONObject block=blocks.optJSONObject(j);if(block!=null)failed|=block.optBoolean("isError");}turn.tools.put(id,(failed?"! ":"✓ ")+previous.substring(2));break;}}}return;}
        if(type.equals("assistant/attempt")){recordedReasoning(streamText(data.optJSONArray("stream"),"reasoning"));return;}
        if(!type.equals("user/message")&&!type.equals("assistant/message"))return;
        JSONObject source=data.optJSONObject("source");if(type.equals("user/message")&&source!=null&&!source.optString("kind").equals("user"))return;
        JSONObject message=type.equals("user/message")?data:data.optJSONObject("message");if(message==null)return;
        JSONArray blocks=message.optJSONArray("content");StringBuilder text=new StringBuilder();if(blocks!=null)for(int i=0;i<blocks.length();i++){JSONObject block=blocks.optJSONObject(i);if(block==null)continue;if(block.optString("type").equals("text")){if(text.length()>0)text.append("\n\n");text.append(block.optString("text"));}else if(block.optString("type").equals("reasoning"))recordedReasoning(block.optString("text"));}
        recordedReasoning(streamText(data.optJSONArray("stream"),"reasoning"));if(text.length()>0)lines.add(new Line(type.equals("user/message")?"user":"assistant",text.toString()));if(type.equals("assistant/message"))live="";
    }
    private static String streamText(JSONArray stream,String kind){StringBuilder text=new StringBuilder();if(stream!=null)for(int i=0;i<stream.length();i++){JSONObject item=stream.optJSONObject(i);if(item==null)continue;String type=item.optString("type");if(type.equals(kind+"-delta"))text.append(item.optString("text"));else if(type.equals(kind+"-chunks")){JSONArray values=item.optJSONArray("texts");if(values!=null)for(int j=0;j<values.length();j++)text.append(values.optString(j));}}return text.toString();}
}
