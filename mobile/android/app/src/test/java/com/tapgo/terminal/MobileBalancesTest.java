package com.tapgo.terminal;
import org.json.*;
import org.junit.Test;
import static org.junit.Assert.*;

public class MobileBalancesTest {
    @Test public void selectedCredentialNeverFallsBackToAccount() throws Exception {
        MobileBalances funds=new MobileBalances();
        funds.account=AccountBalance.read(new JSONObject("{\"status\":\"ready\",\"value\":[{\"currency\":\"CNY\",\"balance\":\"-0.05\"}]}"));
        funds.providers.put("deepseek-official",MobileBalances.amounts(new JSONArray("[{\"currency\":\"CNY\",\"amount\":\"86.77\"}]")));
        assertEquals("¥-0.05",funds.available("deepseek-account"));
        assertEquals("¥86.77",funds.available("deepseek-official"));
        assertNull(funds.available("unsupported"));
        funds.providers.clear();assertNull(funds.available("deepseek-official"));
        assertEquals("¥-0.05",funds.available("deepseek-account"));
    }
    @Test public void currenciesAndDecimalPrecisionStaySeparate() throws Exception {
        assertEquals("¥0.30 · $1.24",MobileBalances.amounts(new JSONArray("[{\"currency\":\"CNY\",\"amount\":\"0.1\"},{\"currency\":\"CNY\",\"amount\":\"0.2\"},{\"currency\":\"USD\",\"amount\":\"1.235\"}]")));
        assertNull(MobileBalances.amounts(JSONObject.NULL));assertNull(MobileBalances.amounts(new JSONArray()));
        assertNull(MobileBalances.amounts(new JSONArray("[{\"currency\":\"CNY\",\"amount\":\"broken\"}]")));
    }
}
