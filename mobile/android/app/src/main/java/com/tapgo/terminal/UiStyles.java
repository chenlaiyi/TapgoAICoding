package com.tapgo.terminal;

import android.content.Context;
import android.graphics.drawable.GradientDrawable;
import android.widget.Button;

/** Shared light/dark button treatment for native home and conversation controls. */
final class UiStyles {
    private UiStyles() {}
    static void button(Button button) {
        Context context=button.getContext();float density=context.getResources().getDisplayMetrics().density;
        GradientDrawable background=new GradientDrawable();background.setColor(context.getColor(R.color.background));background.setStroke(Math.max(1,(int)density),context.getColor(R.color.border));background.setCornerRadius(12*density);
        button.setBackground(background);button.setElevation(0);button.setStateListAnimator(null);button.setMinHeight((int)(48*density));button.setMinimumHeight((int)(48*density));button.setPadding((int)(12*density),(int)(6*density),(int)(12*density),(int)(6*density));
    }
}
