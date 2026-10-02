package com.tapgo.terminal;

import java.util.Locale;

/** Compact model name matching the iOS composer label without a provider prefix. */
final class ModelDisplay {
    private ModelDisplay() {}
    static String name(String display,String modelId){
        String[] words=display.trim().split("\\s+");for(int i=0;i<words.length;i++)if(words[i].matches("[vV][0-9].*")){StringBuilder value=new StringBuilder();for(int j=i;j<words.length;j++){if(value.length()>0)value.append(' ');value.append(words[j]);}return value.toString();}
        String[] parts=modelId.split("-");StringBuilder value=new StringBuilder();for(int i=0;i<parts.length;i++){String part=parts[i];if(i==0&&part.equalsIgnoreCase("deepseek"))continue;if(part.isEmpty())continue;if(value.length()>0)value.append(' ');value.append(part.matches("[vV][0-9].*")?part.toUpperCase(Locale.ROOT):part.substring(0,1).toUpperCase(Locale.ROOT)+part.substring(1));}return value.length()==0?display:value.toString();
    }
}
