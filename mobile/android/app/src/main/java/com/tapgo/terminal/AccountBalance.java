package com.tapgo.terminal;

import org.json.JSONArray;
import org.json.JSONObject;
import java.math.BigDecimal;
import java.math.RoundingMode;

/** Available primary-currency wallets; unrelated currencies never inflate the displayed total. */
final class AccountBalance {
    final BigDecimal recharge,bonus;
    private AccountBalance(BigDecimal recharge,BigDecimal bonus){this.recharge=recharge;this.bonus=bonus;}
    static AccountBalance read(JSONObject account){
        if(!account.optString("status").equals("ready"))return null;
        BigDecimal[] totals={BigDecimal.ZERO,BigDecimal.ZERO};boolean found=false;String[] keys={"value","bonusWallets"};
        for(int i=0;i<keys.length;i++){JSONArray wallets=account.optJSONArray(keys[i]);if(wallets==null)continue;for(int j=0;j<wallets.length();j++){JSONObject wallet=wallets.optJSONObject(j);if(wallet==null||!wallet.optString("currency").equals("CNY"))continue;try{totals[i]=totals[i].add(new BigDecimal(wallet.getString("balance")));found=true;}catch(Exception malformed){return null;}}}
        return found?new AccountBalance(totals[0],totals[1]):null;
    }
    static String format(BigDecimal value){return "¥"+value.setScale(2,RoundingMode.HALF_UP).toPlainString();}
    String total(){return format(recharge.add(bonus));}
}
