package center.dx.wingout2;

import android.app.Activity;
import android.content.Context;
import android.telephony.PhoneStateListener;
import android.telephony.SignalStrength;
import android.telephony.TelephonyManager;

public class SignalHelper {
    private static Activity m_activity;

    public static void init(Activity activity) {
        m_activity = activity;
    }

    // Native callback implemented in platformcontroller.cpp
    public static native void onSignalStrengthChanged(int strength);

    public static void installSignalStrengthListener() {
        if (m_activity == null) {
            return;
        }

        final TelephonyManager telephonyManager =
            (TelephonyManager) m_activity.getSystemService(Context.TELEPHONY_SERVICE);
        if (telephonyManager == null) {
            return;
        }

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
                            level = signalStrength.getGsmSignalStrength();
                        }
                        onSignalStrengthChanged(level);
                    }
                }, PhoneStateListener.LISTEN_SIGNAL_STRENGTHS);
            }
        });
    }
}
