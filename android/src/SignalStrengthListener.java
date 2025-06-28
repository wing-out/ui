package center.dx.wingout;

import android.app.Activity;
import android.content.Context;
import android.telephony.PhoneStateListener;
import android.telephony.SignalStrength;
import android.telephony.TelephonyManager;

public class SignalStrengthListener {
    private static Activity m_activity;

    public static void init(Activity activity) {
        m_activity = activity;
    }

    public static native void signalStrengthChanged(int strength);

    public static void installSignalStrengthListener() {
        final TelephonyManager telephonyManager = (TelephonyManager) m_activity.getSystemService(Context.TELEPHONY_SERVICE);
        m_activity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                telephonyManager.listen(new PhoneStateListener() {
                    @Override
                    public void onSignalStrengthsChanged(SignalStrength signalStrength) {
                        super.onSignalStrengthsChanged(signalStrength);
                        int level = 0;
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                            level = signalStrength.getLevel(); // 0-4
                        } else {
                            // Legacy method
                            level = signalStrength.getGsmSignalStrength();
                        }
                        signalStrengthChanged(level);
                    }
                }, PhoneStateListener.LISTEN_SIGNAL_STRENGTHS);
            }
        });
    }
}