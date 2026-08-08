package io.github.aumt.daedtile;

import android.app.Activity;
import android.content.ComponentName;
import android.content.Intent;
import android.graphics.Typeface;
import android.net.Uri;
import android.os.Bundle;
import android.service.quicksettings.TileService;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Launcher entry for the tile app: shows the current proxy state, a refresh
 * button and the web-UI shortcut, plus instructions for adding the tile.
 */
public class MainActivity extends Activity {

    private TextView mStatus;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Long-pressing the QS tile shows the system tile-detail sheet; its
        // gear entry launches this activity via QS_TILE_PREFERENCES. Open the
        // web UI right away so the long-press path lands on the panel.
        if (TileService.ACTION_QS_TILE_PREFERENCES.equals(getIntent().getAction())) {
            openWeb();
            finish();
            return;
        }

        // Ask the system to (re)listen to the tile so its state refreshes.
        try {
            TileService.requestListeningState(this,
                    new ComponentName(this, DaedTileService.class));
        } catch (Exception ignored) {
        }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setGravity(Gravity.CENTER_HORIZONTAL);
        int pad = dp(24);
        root.setPadding(pad, dp(56), pad, pad);

        root.addView(label(getString(R.string.main_title), 20, true));

        mStatus = label(getString(R.string.main_status_unknown), 15, false);
        mStatus.setPadding(0, dp(12), 0, dp(24));
        root.addView(mStatus);

        Button refresh = new Button(this);
        refresh.setText(R.string.main_refresh);
        refresh.setOnClickListener(v -> refreshStatus());
        root.addView(refresh);

        Button web = new Button(this);
        web.setText(R.string.main_open_web);
        web.setOnClickListener(v -> openWeb());
        root.addView(web);

        TextView hint = label(getString(R.string.main_hint), 13, false);
        hint.setPadding(0, dp(24), 0, 0);
        root.addView(hint);

        setContentView(root);
        refreshStatus();
    }

    private void refreshStatus() {
        int res;
        if (!Daedctl.isDaedRunning()) {
            res = R.string.main_status_daed_down;
        } else if (Daedctl.isProxyRunning()) {
            res = R.string.main_status_running;
        } else {
            res = R.string.main_status_stopped;
        }
        mStatus.setText(res);
    }

    private void openWeb() {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(Daedctl.WEBUI_URL)));
        } catch (Exception e) {
            mStatus.setText(R.string.main_open_web_failed);
        }
    }

    private TextView label(String s, float sp, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(sp);
        if (bold) {
            t.setTypeface(Typeface.DEFAULT_BOLD);
        }
        t.setGravity(Gravity.CENTER);
        return t;
    }

    private int dp(int v) {
        return Math.round(getResources().getDisplayMetrics().density * v);
    }
}
