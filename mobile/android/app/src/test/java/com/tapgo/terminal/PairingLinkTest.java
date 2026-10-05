package com.tapgo.terminal;
import org.junit.Test;
import static org.junit.Assert.*;
public class PairingLinkTest {
    @Test public void directAndDeepLinksPreserveOriginAndName(){PairingLink link=PairingLink.parse("https://work.example:8443/?token=fixture&name=Office%20PC");assertEquals("https://work.example:8443",link.origin);assertEquals("Office PC",link.name);assertEquals(link.url,PairingLink.parse("dsh-mobile://?url=https%3A%2F%2Fwork.example%3A8443%2F%3Ftoken%3Dfixture%26name%3DOffice%2520PC").url);}
    @Test public void refusesUntrustedPairingForms(){String[] invalid={"http://work.example/?token=fixture","https://user@work.example/?token=fixture","https://work.example/path?token=fixture","https://work.example/?token=","https://work.example/?token=a&token=b","https://work.example/?token=x#fragment","javascript:alert(1)","dsh-mobile://?url=ftp%3A%2F%2Fwork.example"};for(String value:invalid){try{PairingLink.parse(value);fail(value);}catch(IllegalArgumentException expected){}}}
    @Test public void navigationComparesAuthority(){assertTrue(PairingLink.sameOrigin("https://work.example","https://work.example:443/api"));assertFalse(PairingLink.sameOrigin("https://work.example","https://work.example.evil.test/"));assertFalse(PairingLink.sameOrigin("https://work.example","https://work.example:8443/"));assertFalse(PairingLink.sameOrigin("https://work.example","https://user@work.example/"));assertFalse(PairingLink.sameOrigin("https://work.example","file:///tmp/data"));}
}
