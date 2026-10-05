package com.tapgo.terminal;
import org.json.*;
import org.junit.Test;
import static org.junit.Assert.*;
public class ChatProjectionTest {
    @Test public void snapshotLiveAndFinalReplyShareHistoryWithoutDuplicatingEvents() throws Exception {
        ChatProjection state=new ChatProjection();
        JSONObject user=new JSONObject("{\"seq\":1,\"type\":\"user/message\",\"data\":{\"source\":{\"kind\":\"user\"},\"content\":[{\"type\":\"text\",\"text\":\"检查项目\"}]}}");
        state.receive(new JSONObject().put("type","snapshot").put("records",new JSONArray().put(new JSONObject().put("event",user))));
        state.receive(new JSONObject().put("event",user));assertEquals(1,state.lines.size());assertEquals("检查项目",state.lines.get(0).text);
        state.receive(new JSONObject("{\"type\":\"assistant-stream\",\"frame\":{\"type\":\"start\"}}"));
        state.receive(new JSONObject("{\"type\":\"assistant-stream\",\"frame\":{\"type\":\"chunk\",\"chunk\":{\"type\":\"text-delta\",\"text\":\"正在检查\"}}}"));assertEquals("正在检查",state.live);
        state.receive(new JSONObject("{\"event\":{\"seq\":2,\"type\":\"assistant/message\",\"data\":{\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"**检查完成**\"}]}}}}"));assertEquals("",state.live);assertEquals("**检查完成**",state.lines.get(1).text);
        state.receive(new JSONObject("{\"event\":{\"seq\":3,\"type\":\"turn/end\",\"data\":{\"turn\":1}}}"));assertFalse(state.running);
    }
    @Test public void compactSessionRecordsMatchNativeTranscriptExpectedOutput() throws Exception {
        JSONObject fixture;try(java.io.InputStream input=getClass().getResourceAsStream("/expected/native-chat.json")){assertNotNull(input);fixture=new JSONObject(new String(input.readAllBytes(),java.nio.charset.StandardCharsets.UTF_8));}
        ChatProjection state=new ChatProjection();JSONArray frames=fixture.getJSONArray("frames");for(int i=0;i<frames.length();i++)state.receive(frames.getJSONObject(i));
        JSONObject expected=fixture.getJSONObject("expected");JSONArray lines=expected.getJSONArray("lines");assertEquals(lines.length(),state.lines.size());for(int i=0;i<lines.length();i++){assertEquals(lines.getJSONObject(i).getString("role"),state.lines.get(i).role);assertEquals(lines.getJSONObject(i).getString("text"),state.lines.get(i).text);}
        assertEquals(expected.getString("reasoning"),state.reasoning);assertEquals(expected.getString("activity"),state.activity);assertEquals(expected.getBoolean("running"),state.running);
    }
    @Test public void turnProcessesKeepToolCompletionAndReasoningWithTheirOwnTurn() throws Exception {
        ChatProjection state=new ChatProjection();
        state.receive(new JSONObject("{\"event\":{\"seq\":1,\"type\":\"turn/start\",\"data\":{\"turn\":1}}}"));
        state.receive(new JSONObject("{\"type\":\"assistant-stream\",\"frame\":{\"type\":\"chunk\",\"chunk\":{\"type\":\"reasoning-delta\",\"text\":\"检查文件\"}}}"));
        state.receive(new JSONObject("{\"event\":{\"seq\":2,\"type\":\"tool/call\",\"data\":{\"callId\":\"call-one\",\"name\":\"read_file\"}}}"));
        state.receive(new JSONObject("{\"event\":{\"seq\":3,\"type\":\"tool/result\",\"data\":{\"message\":{\"source\":{\"callId\":\"call-one\"},\"isError\":true}}}}"));
        state.receive(new JSONObject("{\"event\":{\"seq\":4,\"type\":\"turn/end\",\"data\":{\"turn\":1}}}"));
        ChatProjection.Line first=state.currentTurn;assertTrue(state.process(first).contains("! read_file"));assertTrue(state.process(first).contains("检查文件"));
        state.receive(new JSONObject("{\"event\":{\"seq\":5,\"type\":\"turn/start\",\"data\":{\"turn\":2}}}"));assertEquals("",state.process(state.currentTurn));assertTrue(state.process(first).contains("检查文件"));
    }
    @Test public void hiddenRecordKindsDoNotBecomeUserMessages() throws Exception {
        ChatProjection state=new ChatProjection();state.receive(new JSONObject("{\"event\":{\"seq\":1,\"type\":\"user/message\",\"data\":{\"source\":{\"kind\":\"system\"},\"content\":[{\"type\":\"text\",\"text\":\"hidden\"}]}}}"));assertTrue(state.lines.isEmpty());
        state.receive(new JSONObject("{\"event\":{\"seq\":2,\"type\":\"tool/call\",\"data\":{\"name\":\"read_file\",\"arguments\":\"private\"}}}"));assertEquals("read_file\n",state.activity);assertFalse(state.activity.contains("private"));
    }
}
