package com.tapgo.terminal;

import org.json.JSONArray;
import org.json.JSONObject;
import java.math.BigDecimal;
import java.util.Map;
import java.util.TreeMap;

/** Host-owned credentials are queried independently; unavailable providers never use account funds. */
final class MobileBalances {
    AccountBalance account;
    final Map<String,String> providers=new TreeMap<>();
    String available(String provider){return "deepseek-account".equals(provider)?(account==null?null:account.total()):providers.get(provider);}
    static String amounts(Object value){
        if(!(value instanceof JSONArray))return null;
        JSONArray rows=(JSONArray)value;Map<String,BigDecimal> totals=new TreeMap<>();
        try{for(int i=0;i<rows.length();i++){
            JSONObject row=rows.getJSONObject(i);String currency=row.getString("currency");
            if(currency.isEmpty())return null;
            totals.put(currency,totals.getOrDefault(currency,BigDecimal.ZERO).add(new BigDecimal(row.getString("amount"))));
        }}catch(Exception malformed){return null;}
        StringBuilder text=new StringBuilder();
        for(Map.Entry<String,BigDecimal> row:totals.entrySet()){
            if(text.length()>0)text.append(" · ");
            String symbol=row.getKey().equals("CNY")?"¥":row.getKey().equals("USD")?"$":row.getKey().equals("EUR")?"€":row.getKey()+" ";
            text.append(symbol).append(row.getValue().setScale(2,java.math.RoundingMode.HALF_UP).toPlainString());
        }
        return text.length()==0?null:text.toString();
    }
    static MobileBalances load(RemoteClient client,String provider){
        MobileBalances result=new MobileBalances();
        try{result.account=AccountBalance.read(client.account());}catch(Exception unavailable){/* The API query remains independent of account login. */}
        java.util.Set<String> routes=new java.util.TreeSet<>();routes.add("deepseek-official");
        if(provider!=null&&!provider.isEmpty()&&!provider.equals("deepseek-account"))routes.add(provider);
        for(String route:routes){try{
            String amount=amounts(client.rpcValue("llm/getBalance",new JSONObject().put("provider",route)));
            if(amount!=null)result.providers.put(route,amount);
        }catch(Exception unavailable){/* The selected provider stays unavailable without a wallet fallback. */}}
        return result;
    }
    String summary(MainActivity activity){
        String missing=activity.getString(R.string.balance_unavailable);
        String value=activity.getString(R.string.account_balance,account==null?missing:account.total());
        if(account!=null)value+="\n"+activity.getString(R.string.recharge_balance,AccountBalance.format(account.recharge))+"\n"+activity.getString(R.string.bonus_balance,AccountBalance.format(account.bonus));
        return value+"\n"+activity.getString(R.string.api_balance,providers.getOrDefault("deepseek-official",missing));
    }
}
