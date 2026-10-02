package com.tapgo.terminal;
import org.json.JSONObject;
import org.junit.Test;
import static org.junit.Assert.*;

public class AccountBalanceTest {
    @Test public void rechargeAndBonusShareOnePrimaryCurrencyTotal() throws Exception {
        AccountBalance value=AccountBalance.read(new JSONObject("{\"status\":\"ready\",\"value\":[{\"currency\":\"USD\",\"balance\":\"99\"},{\"currency\":\"CNY\",\"balance\":\"10.12\"}],\"bonusWallets\":[{\"currency\":\"CNY\",\"balance\":\"2.345\"}]}"));
        assertNotNull(value);assertEquals("¥12.47",value.total());assertEquals("¥10.12",AccountBalance.format(value.recharge));assertEquals("¥2.35",AccountBalance.format(value.bonus));
    }
    @Test public void absentOrMalformedWalletsDoNotAppearAsZeroBalance() throws Exception {
        assertNull(AccountBalance.read(new JSONObject("{\"status\":\"unavailable\"}")));
        assertNull(AccountBalance.read(new JSONObject("{\"status\":\"ready\",\"value\":[{\"currency\":\"USD\",\"balance\":\"1\"}]}")));
        assertNull(AccountBalance.read(new JSONObject("{\"status\":\"ready\",\"value\":[{\"currency\":\"CNY\",\"balance\":\"invalid\"}]}")));
    }
}
