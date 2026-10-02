package com.tapgo.terminal;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import org.json.JSONArray;
import org.json.JSONObject;
import java.security.KeyStore;
import java.util.ArrayList;
import java.util.List;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** Device-local pairing records encrypted with a non-exportable Android Keystore key. */
final class ComputerStore {
    static final class Computer {
        final String origin, url, sourceName;
        String customName;
        Computer(PairingLink link, String customName) {
            this.origin = link.origin; this.url = link.url; this.sourceName = link.name; this.customName = customName;
        }
        String name() { return customName == null ? sourceName : customName; }
    }
    final List<Computer> computers = new ArrayList<>();
    String active;
    private final Context context;
    private static final String KEY = "tapgo.pairing.v1";
    ComputerStore(Context context) throws Exception {
        this.context = context;
        String encoded = context.getSharedPreferences("connections", 0).getString("encrypted", null);
        if (encoded == null) return;
        JSONObject envelope = new JSONObject(encoded);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(envelope.getString("iv"), Base64.NO_WRAP)));
        JSONObject data = new JSONObject(new String(cipher.doFinal(Base64.decode(envelope.getString("data"), Base64.NO_WRAP)), java.nio.charset.StandardCharsets.UTF_8));
        JSONArray rows = data.getJSONArray("computers");
        for (int i = 0; i < rows.length(); i++) {
            JSONObject row = rows.getJSONObject(i);
            computers.add(new Computer(PairingLink.parse(row.getString("url")), row.isNull("name") ? null : row.getString("name")));
        }
        active = data.optString("active", null);
        if (current() == null) active = null;
    }
    Computer current() { for (Computer c : computers) if (c.origin.equals(active)) return c; return null; }
    void pair(PairingLink link) throws Exception {
        Computer previous = null;
        for (Computer c : computers) if (c.origin.equals(link.origin)) previous = c;
        computers.remove(previous);
        computers.add(new Computer(link, previous == null ? null : previous.customName)); active = link.origin; save();
    }
    void save() throws Exception {
        JSONArray rows = new JSONArray();
        for (Computer c : computers) rows.put(new JSONObject().put("url", c.url).put("name", c.customName == null ? JSONObject.NULL : c.customName));
        byte[] plain = new JSONObject().put("active", active).put("computers", rows).toString().getBytes(java.nio.charset.StandardCharsets.UTF_8);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
        String encoded = new JSONObject().put("iv", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
                .put("data", Base64.encodeToString(cipher.doFinal(plain), Base64.NO_WRAP)).toString();
        if (!context.getSharedPreferences("connections", 0).edit().putString("encrypted", encoded).commit()) throw new java.io.IOException("Pairing persistence failed");
    }
    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (store.containsAlias(KEY)) return (SecretKey) store.getKey(KEY, null);
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(KEY, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return generator.generateKey();
    }
}
