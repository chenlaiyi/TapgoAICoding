package com.tapgo.terminal;
import org.json.*;
import org.junit.Test;
import static org.junit.Assert.*;

public class NextPromptsTest {
    @Test public void recommendationsFollowTheLatestTurnAndAppendToDrafts() throws Exception {
        ChatProjection state=new ChatProjection();
        state.receive(new JSONObject("{\"event\":{\"seq\":1,\"type\":\"turn/start\",\"data\":{\"turn\":1}}}"));
        state.receive(new JSONObject("{\"event\":{\"seq\":2,\"type\":\"turn/end\",\"data\":{\"turn\":1}}}"));
        state.receive(new JSONObject("{\"event\":{\"seq\":3,\"type\":\"session/next-prompts-result\",\"data\":{\"turn\":1,\"status\":\"ready\",\"prompts\":[\" 实施方案二 \",\"列出步骤\",\"实施方案二\"]}}}"));
        assertEquals(java.util.List.of("实施方案二","列出步骤"),state.nextPrompts.prompts);
        assertEquals("已有草稿\n\n实施方案二",NextPrompts.appending("实施方案二","已有草稿"));
        assertEquals("实施方案二",NextPrompts.appending("实施方案二",""));
        state.receive(new JSONObject("{\"event\":{\"seq\":4,\"type\":\"turn/start\",\"data\":{\"turn\":2}}}"));
        state.receive(new JSONObject("{\"event\":{\"seq\":5,\"type\":\"session/next-prompts-result\",\"data\":{\"turn\":1,\"status\":\"ready\",\"prompts\":[\"过期建议\"]}}}"));
        assertTrue(state.nextPrompts.prompts.isEmpty());
    }
    @Test public void snapshotsRestoreResultsWithoutCallsAndInvalidResultsAreIgnored() throws Exception {
        ChatProjection state=new ChatProjection();
        state.receive(new JSONObject("{\"type\":\"snapshot\",\"records\":[],\"projections\":{\"values\":{\"nextPrompts\":{\"turn\":3,\"status\":\"ready\",\"prompts\":[\"继续\"]}}}}"));
        assertEquals(java.util.List.of("继续"),state.nextPrompts.prompts);
        state.nextPrompts.restore(new JSONObject("{\"turn\":3,\"status\":\"ready\",\"prompts\":[\" \"]}"),false);
        state.nextPrompts.restore(new JSONObject("{\"turn\":3,\"status\":\"ready\",\"prompts\":[\"a\",\"b\",\"c\",\"d\"]}"),false);
        assertEquals(java.util.List.of("继续"),state.nextPrompts.prompts);
        state.nextPrompts.restore(new JSONObject("{\"turn\":3,\"status\":\"error\",\"prompts\":[]}"),false);
        assertTrue(state.nextPrompts.failed);assertTrue(state.nextPrompts.prompts.isEmpty());
    }
}
