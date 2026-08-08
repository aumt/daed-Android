package io.github.aumt.daedtile;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

/**
 * Headless entry opened from the Quick-Settings tile: ColorOS launches it
 * directly on long-press, stock Android via the tile-detail gear. It shows no
 * UI — it opens the daed web UI and finishes immediately. There is no launcher
 * entry, so the app has no desktop/app-drawer icon.
 */
public class MainActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(Daedctl.WEBUI_URL)));
        } catch (Exception ignored) {
            // No browser available; nothing to show.
        }
        finish();
    }
}
