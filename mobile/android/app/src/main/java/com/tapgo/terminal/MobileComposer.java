package com.tapgo.terminal;

import android.content.Context;
import android.graphics.drawable.GradientDrawable;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.inputmethod.InputMethodManager;
import android.widget.*;

/** Input and persistent lower toolbar shared by new and existing conversations. */
final class MobileComposer extends LinearLayout {
    final EditText input;
    final Button model,permission,send,stop;
    final TextView balance;
    MobileComposer(Context context,int addLabel,Runnable add,Runnable chooseModel,Runnable choosePermission,Runnable submit,Runnable cancel) {
        super(context);setOrientation(VERTICAL);int inset=dp(8);setPadding(inset,inset,inset,inset);
        GradientDrawable background=new GradientDrawable();background.setColor(context.getColor(R.color.background));background.setStroke(dp(1),context.getColor(R.color.border));background.setCornerRadius(dp(24));setBackground(background);
        input=new EditText(context);input.setHint(R.string.message_hint);input.setMinLines(1);input.setMaxLines(5);input.setInputType(android.text.InputType.TYPE_CLASS_TEXT|android.text.InputType.TYPE_TEXT_FLAG_MULTI_LINE);input.setBackground(null);addView(input);
        LinearLayout toolbar=new LinearLayout(context);toolbar.setGravity(Gravity.CENTER_VERTICAL);addView(toolbar);
        Button plus=icon(addLabel,android.R.drawable.ic_input_add,add);toolbar.addView(plus,new LayoutParams(dp(44),dp(48)));
        permission=icon(R.string.permission,android.R.drawable.ic_lock_lock,choosePermission);toolbar.addView(permission,new LayoutParams(dp(44),dp(48)));
        LinearLayout metadata=new LinearLayout(context);metadata.setGravity(Gravity.CENTER_VERTICAL);toolbar.addView(metadata,new LayoutParams(0,dp(48),1));
        model=new Button(context);model.setText(R.string.model);model.setTextSize(11);model.setTextColor(context.getColor(R.color.secondary));model.setAllCaps(false);model.setMinWidth(0);model.setMinimumWidth(0);model.setPadding(0,0,0,0);model.setBackground(null);model.setSingleLine();model.setEllipsize(TextUtils.TruncateAt.END);model.setOnClickListener(v->chooseModel.run());metadata.addView(model,new LayoutParams(0,-1,1));
        balance=new TextView(context);balance.setTextSize(11);balance.setTextColor(context.getColor(R.color.secondary));balance.setSingleLine();metadata.addView(balance);
        toolbar.addView(icon(R.string.dismiss_keyboard,android.R.drawable.ic_menu_close_clear_cancel,()->((InputMethodManager)context.getSystemService(Context.INPUT_METHOD_SERVICE)).hideSoftInputFromWindow(input.getWindowToken(),0)),new LayoutParams(dp(44),dp(48)));
        send=icon(R.string.send,android.R.drawable.ic_menu_upload,submit);toolbar.addView(send,new LayoutParams(dp(44),dp(48)));
        stop=icon(R.string.stop,android.R.drawable.ic_media_pause,cancel);toolbar.addView(stop,new LayoutParams(dp(44),dp(48)));stop.setVisibility(GONE);
    }
    void running(boolean running){send.setVisibility(running?GONE:VISIBLE);stop.setVisibility(running?VISIBLE:GONE);stop.setEnabled(running);}
    private int dp(int value){return Math.round(value*getResources().getDisplayMetrics().density);}
    private Button icon(int label,int drawable,Runnable action){Button button=new Button(getContext());button.setContentDescription(getContext().getString(label));button.setTooltipText(getContext().getString(label));button.setMinWidth(0);button.setMinimumWidth(0);button.setPadding(dp(8),dp(12),dp(8),dp(12));button.setBackground(null);android.graphics.drawable.Drawable image=getContext().getDrawable(drawable);if(image!=null)image.setTint(getContext().getColor(R.color.primary));button.setCompoundDrawablesWithIntrinsicBounds(image,null,null,null);button.setOnClickListener(v->action.run());return button;}
}
