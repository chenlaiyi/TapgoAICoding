package com.tapgo.terminal;
import org.junit.Test;
import static org.junit.Assert.*;
public class ModelDisplayTest {
    @Test public void composerDropsProviderNameAndKeepsVersion(){assertEquals("V4 Pro",ModelDisplay.name("DeepSeek V4 Pro","deepseek-v4-pro"));assertEquals("V3 Chat",ModelDisplay.name("DeepSeek Chat","deepseek-v3-chat"));assertEquals("Fixture Model",ModelDisplay.name("验收模型","fixture-model"));}
}
