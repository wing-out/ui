package center.dx.wingout;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import center.dx.wingout.WingOutBackgroundService;

public class WingOutBroadcastReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        Intent startServiceIntent = new Intent(context, WingOutBackgroundService.class);
        context.startService(startServiceIntent);
    }
}